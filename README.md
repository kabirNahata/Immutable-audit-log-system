# Immutable Audit Log System

## Overview

The **Immutable Audit Log System** is a C++ application backed by PostgreSQL, designed to manage business orders with robust, tamper-evident audit logging. It ensures every change to business data is recorded immutably, supporting regulatory compliance and forensic analysis.

---

## Features

- **Order Management:** Insert, update, and delete orders.
- **Immutable Audit Logging:** Every change is logged with cryptographic hashes, preventing undetected tampering.
- **Audit Chain Verification:** Ensures the integrity of the audit log using hash chaining.
- **User-Friendly CLI:** Menu-driven interface for easy operation.

---

## Project Structure

```
Immutable audit log system/
├── main.cpp           # C++ source code for CLI application
├── setup.sql          # PostgreSQL schema, triggers, and functions
├── CMakeLists.txt     # Build configuration for CMake
```

---

## Components

### main.cpp

Implements the CLI application using [libpqxx](https://github.com/jtv/libpqxx) for PostgreSQL access.

- **insertOrder:** Adds a new order.
- **updateOrder:** Changes the status of an existing order.
- **deleteOrder:** Removes an order.
- **viewAuditLogs:** Displays all audit log entries.
- **verifyChain:** Checks the integrity of the audit log chain.

### setup.sql

Defines the PostgreSQL schema and logic for immutable audit logging.

- **Business Table (`app_order`):** Stores orders with automatic timestamping.
- **Audit Log Table (`audit_log`):** Records every change with cryptographic hashes.
- **Triggers:** 
  - Prevent updates/deletes on audit log (append-only).
  - Automatically log every insert, update, or delete on orders.
  - Chain each audit log entry using SHA-256 hashes.
- **Chain Verification Function:** Validates the integrity of the audit log.

### CMakeLists.txt

Configures the build using CMake.

- Requires C++20.
- Integrates with `libpqxx` via vcpkg.
- Builds the `immutable_audit` executable.

---

## Setup & Usage

### 1. Database Setup

1. Ensure PostgreSQL is installed.
2. Run `setup.sql` in your database:
   ```sh
   psql -U postgres -d immutable_demo -f setup.sql
   ```
3. Adjust connection info in `main.cpp` if needed.

### 2. Build the Application

1. Install [vcpkg](https://vcpkg.io/) and `libpqxx`:
   ```sh
   vcpkg install libpqxx
   ```
2. Configure and build:
   ```sh
   cmake -B build -S .
   cmake --build build
   ```

### 3. Run

```sh
./build/immutable_audit
```

---

## Security & Integrity

- **Immutability:** Audit log entries cannot be modified or deleted.
- **Hash Chaining:** Each entry includes a hash of the previous entry and its own data, forming a tamper-evident chain.
- **Verification:** The system can detect any break in the chain, ensuring audit integrity.

---

## Extensibility

- **Actor Tracking:** Logs the database user responsible for each change.
- **Custom Entities:** Easily extendable to other business tables.
- **Notes & Metadata:** Supports additional context in audit entries.

---

## Dependencies

- **C++20**
- **libpqxx** (PostgreSQL C++ client)
- **PostgreSQL** (with `pgcrypto` extension)

---

## Authors

- Kabir Nahata
---

## References

- [libpqxx Documentation](https://libpqxx.readthedocs.io/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pgcrypto Extension](https://www.postgresql.org/docs/current/pgcrypto.html)

