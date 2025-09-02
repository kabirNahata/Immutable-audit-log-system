#include <pqxx/pqxx>
#include <iostream>
#include <string>

void insertOrder(pqxx::connection& c) {
    std::string name, status;
    double amount;

    // DO NOT ignore() here; we already did it after reading the menu choice.
    std::cout << "Enter customer name: ";
    std::getline(std::cin, name);

    std::cout << "Enter amount (NPR): ";
    std::cin >> amount;
    std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n'); // clear newline

    std::cout << "Enter status (e.g., NEW): ";
    std::getline(std::cin, status);

    pqxx::work tx{c};
    long id = tx.exec_prepared1("ins_order", name, amount, status)[0].as<long>();
    tx.commit();
    std::cout << "Inserted order with ID: " << id << "\n";
}

void updateOrder(pqxx::connection& c) {
    long id;
    std::string status;

    std::cout << "Enter order ID to update: ";
    std::cin >> id;
    std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');

    std::cout << "Enter new status: ";
    std::getline(std::cin, status);

    pqxx::work tx{c};
    tx.exec_prepared("upd_order_status", id, status);
    tx.commit();
    std::cout << "Updated order " << id << " to " << status << "\n";
}

void deleteOrder(pqxx::connection& c) {
    long id;
    std::cout << "Enter order ID to delete: ";
    std::cin >> id;
    std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');

    pqxx::work tx{c};
    tx.exec_prepared("del_order", id);
    tx.commit();
    std::cout << "Deleted order " << id << "\n";
}

void viewAuditLogs(pqxx::connection& c) {
    pqxx::read_transaction rx{c};
    auto r = rx.exec("SELECT log_id, ts, actor, action, entity, entity_id FROM audit_log ORDER BY log_id");
    std::cout << "\nAudit log:\n";
    for (auto const& row : r) {
        std::cout << row["log_id"].as<long>() << " "
                  << row["ts"].as<std::string>() << " "
                  << row["actor"].as<std::string>() << " "
                  << row["action"].as<std::string>() << " "
                  << row["entity"].as<std::string>() << " "
                  << row["entity_id"].as<std::string>() << "\n";
    }
}

void verifyChain(pqxx::connection& c) {
    pqxx::read_transaction rx{c};
    auto r = rx.exec("SELECT * FROM audit_verify_chain()");
    bool ok = r[0][0].as<bool>();
    std::cout << "\nChain OK? " << (ok ? "YES" : "NO") << "\n";
}

int main() {
    try {
        // Use key=value form to avoid URL-encoding hassles with '@' in passwords.
        // CHANGE the password/dbname if you used different values.
        const char* conninfo =
            "host=localhost port=5432 dbname=immutable_demo user=postgres password=password";
        pqxx::connection c{conninfo};

        // Prepare SQL statements once
        c.prepare("ins_order",
                  "INSERT INTO app_order(customer_name, amount_npr, status) "
                  "VALUES($1,$2,$3) RETURNING order_id");
        c.prepare("upd_order_status",
                  "UPDATE app_order SET status=$2 WHERE order_id=$1");
        c.prepare("del_order",
                  "DELETE FROM app_order WHERE order_id=$1");

        int choice = 0;
        while (true) {
            std::cout << "\n===== MENU =====\n";
            std::cout << "1. Insert Order\n";
            std::cout << "2. Update Order Status\n";
            std::cout << "3. Delete Order\n";
            std::cout << "4. View Audit Logs\n";
            std::cout << "5. Verify Audit Chain\n";
            std::cout << "6. Quit\n";
            std::cout << "Enter your choice: ";

            if (!(std::cin >> choice)) {
                std::cin.clear();
                std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
                std::cout << "Invalid input. Try again.\n";
                continue;
            }
            std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');

            switch (choice) {
                case 1: insertOrder(c); break;
                case 2: updateOrder(c); break;
                case 3: deleteOrder(c); break;
                case 4: viewAuditLogs(c); break;
                case 5: verifyChain(c); break;
                case 6: std::cout << "Exiting...\n"; return 0;
                default: std::cout << "Invalid choice, try again.\n";
            }
        }

    } catch (const std::exception &e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}
