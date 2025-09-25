# ClickHouse Monitoring Stack Installer (`setup.sh`)

This script, created by **Ajink Gupta**, automates the installation and configuration of a complete monitoring stack for ClickHouse on **Ubuntu** and **Debian**-based systems. It interactively sets up **ClickHouse**, **Prometheus**, and **Grafana**, providing a production-ready monitoring solution in minutes.


## Features

* **Interactive Setup**: Prompts for a secure username and password for ClickHouse.
* **Fully Automated**: Installs and configures all necessary components without manual intervention.
* **Secure by Default**: Configures a dedicated, password-protected user for ClickHouse.
* **Built-in Metrics**: Utilizes ClickHouse's efficient built-in Prometheus exporter.
* **Grafana Integration**: Automatically adds Prometheus as a data source in Grafana.

---

## Prerequisites

* A fresh installation of **Ubuntu (20.04 or newer)** or **Debian (10 or newer)**.
* Root or `sudo` privileges.
* Git installed (`sudo apt install git`).
* Internet access to download packages.

---

## 🚀 Quick Start Installation

Follow these steps to get your monitoring stack running.

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/Ajinkgupta/clickhouse-monitoring-stack.git](https://github.com/Ajinkgupta/clickhouse-monitoring-stack.git)
    ```

2.  **Navigate into the directory:**
    ```bash
    cd clickhouse-monitoring-stack
    ```

3.  **Make the script executable:**
    ```bash
    chmod +x setup.sh
    ```

4.  **Run the installer with sudo:**
    ```bash
    sudo ./setup.sh
    ```
    The script will then guide you through setting up the ClickHouse credentials.

---

## What Happens Next?

After the script completes, it will display a **Final Summary** with all the necessary URLs and the credentials you created.

1.  **Access Grafana**: Open your web browser and navigate to `http://<your_server_ip>:3000`.
2.  **Login**: Use the default credentials `admin` / `admin`. You will be prompted to change the password on your first login.
3.  **Import a Dashboard**: To visualize your ClickHouse metrics, import a pre-made dashboard.
    * In Grafana, go to `Dashboards` -> `Import`.
    * Enter the ID `14192` (a popular dashboard for ClickHouse by Sentry) and click `Load`.
    * Select your `Prometheus` data source and finish the import.

---

## Components Installed

| Service | Port | Access URL | Description |
| :--- | :--- | :--- | :--- |
| **Grafana** | 3000 | `http://<your_server_ip>:3000` | Visualization and dashboarding. |
| **Prometheus** | 9090 | `http://<your_server_ip>:9090` | Metrics collection and time-series database. |
| **ClickHouse** | 8123 | `http://<your_server_ip>:8123` | HTTP client access to the database. |
| **CH Metrics** | 9363 | `http://<your_server_ip>:9363` | Prometheus metrics endpoint. |

---

## Author & Contact

* **Author**: Ajink Gupta ([github.com/ajinkgupta](https://github.com/ajinkgupta))
* **Contact**: ajink@duck.com
* **Built at**: hawky.ai