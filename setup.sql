-- Enable pgcrypto for hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Business table
CREATE TABLE app_order (
  order_id      BIGSERIAL PRIMARY KEY,
  customer_name TEXT NOT NULL,
  amount_npr    NUMERIC(12,2) NOT NULL CHECK (amount_npr >= 0),
  status        TEXT NOT NULL CHECK (status IN ('NEW','PAID','CANCELLED')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update 'updated_at'
CREATE OR REPLACE FUNCTION trg_order_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END$$;

CREATE TRIGGER app_order_touch_updated_at
BEFORE UPDATE ON app_order
FOR EACH ROW EXECUTE FUNCTION trg_order_touch_updated_at();

-- 2) Immutable audit log
CREATE TABLE audit_log (
  log_id    BIGSERIAL PRIMARY KEY,
  ts        TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor     TEXT NOT NULL,
  action    TEXT NOT NULL,
  entity    TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  data      JSONB NOT NULL,
  prev_hash BYTEA,
  curr_hash BYTEA,
  note      TEXT
);

-- Disallow update/delete
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC; -- to restrict all users use REVOKE ... FROM <role>; eg ADMIN

CREATE OR REPLACE FUNCTION trg_audit_block_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only';
END$$;

CREATE TRIGGER audit_block_update
BEFORE UPDATE ON audit_log
FOR EACH ROW EXECUTE FUNCTION trg_audit_block_change();

CREATE TRIGGER audit_block_delete
BEFORE DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION trg_audit_block_change();

-- 3) Hash function
CREATE OR REPLACE FUNCTION audit_compute_hash(
  p_prev_hash BYTEA,
  p_ts TIMESTAMPTZ,
  p_actor TEXT,
  p_action TEXT,
  p_entity TEXT,
  p_entity_id TEXT,
  p_data JSONB
) RETURNS BYTEA
LANGUAGE sql IMMUTABLE AS $$
  SELECT digest(
  concat_ws( '|',
    coalesce(encode(p_prev_hash, 'hex'), ''),
    to_char(p_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_actor,
    p_action,
    p_entity,
    p_entity_id,
    coalesce((
      SELECT jsonb_object_agg(key, value)
      FROM jsonb_each(p_data)
      ORDER BY 1
    )::text, '')
  ),
  'sha256'
);
$$;

-- 4) Chain trigger for audit_log
CREATE OR REPLACE FUNCTION trg_audit_log_chain()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_prev BYTEA;
BEGIN
  SELECT curr_hash INTO v_prev
  FROM audit_log
  ORDER BY log_id DESC
  LIMIT 1;

  NEW.prev_hash := v_prev;
  NEW.curr_hash := audit_compute_hash(
    NEW.prev_hash, NEW.ts, NEW.actor, NEW.action, NEW.entity, NEW.entity_id, NEW.data
  );

  RETURN NEW;
END$$;

CREATE TRIGGER audit_log_chain
BEFORE INSERT ON audit_log
FOR EACH ROW EXECUTE FUNCTION trg_audit_log_chain();

-- 5) Triggers on business table
CREATE OR REPLACE FUNCTION write_order_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_actor TEXT;
  v_action TEXT;
  v_data JSONB;
  v_entity TEXT := 'app_order';
  v_entity_id TEXT;
BEGIN
  v_actor := current_user;

  IF (TG_OP = 'INSERT') THEN
    v_action := 'INSERT';
    v_data := to_jsonb(NEW) - 'updated_at';
    v_entity_id := NEW.order_id::text;

  ELSIF (TG_OP = 'UPDATE') THEN
    v_action := 'UPDATE';
    v_data := jsonb_build_object(
                'old', to_jsonb(OLD) - 'updated_at',
                'new', to_jsonb(NEW) - 'updated_at'
              );
    v_entity_id := NEW.order_id::text;

  ELSIF (TG_OP = 'DELETE') THEN
    v_action := 'DELETE';
    v_data := to_jsonb(OLD) - 'updated_at';
    v_entity_id := OLD.order_id::text;
  END IF;

  INSERT INTO audit_log(actor, action, entity, entity_id, data, note)
  VALUES (v_actor, v_action, v_entity, v_entity_id, v_data, null);

  RETURN NULL;
END$$;

CREATE TRIGGER app_order_audit_ins
AFTER INSERT ON app_order
FOR EACH ROW EXECUTE FUNCTION write_order_audit();

CREATE TRIGGER app_order_audit_upd
AFTER UPDATE ON app_order
FOR EACH ROW EXECUTE FUNCTION write_order_audit();

CREATE TRIGGER app_order_audit_del
AFTER DELETE ON app_order
FOR EACH ROW EXECUTE FUNCTION write_order_audit();

-- 6) Chain verification function
CREATE OR REPLACE FUNCTION audit_verify_chain()
RETURNS TABLE(ok BOOLEAN, broken_at BIGINT, reason TEXT) LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
  v_prev BYTEA;
  v_recalc BYTEA;
BEGIN
  v_prev := NULL;

  FOR r IN
    SELECT log_id, ts, actor, action, entity, entity_id, data, prev_hash, curr_hash
    FROM audit_log
    ORDER BY log_id
  LOOP
    IF r.prev_hash IS DISTINCT FROM v_prev THEN
      RETURN QUERY SELECT FALSE, r.log_id, 'prev_hash mismatch';
      RETURN;
    END IF;

    v_recalc := audit_compute_hash(r.prev_hash, r.ts, r.actor, r.action, r.entity, r.entity_id, r.data);
    IF v_recalc IS DISTINCT FROM r.curr_hash THEN
      RETURN QUERY SELECT FALSE, r.log_id, 'curr_hash mismatch';
      RETURN;
    END IF;

    v_prev := r.curr_hash;
  END LOOP;

  RETURN QUERY SELECT TRUE, NULL::BIGINT, NULL::TEXT;
END$$;
