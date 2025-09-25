#!/bin/bash
# -------------------------------------------------------------------------- #
#         Complete ClickHouse Monitoring Stack Installation Script         #
# -------------------------------------------------------------------------- #
# Author:   Ajink Gupta (github.com/ajinkgupta)                              #
# Contact:  ajink@duck.com                                                   #
# Built at: hawky.ai                                                         #
# -------------------------------------------------------------------------- #

set -e

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Main Script ---
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Interactive ClickHouse Monitoring Stack Installation    ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}"
   exit 1
fi

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 1/6: Setup ClickHouse Credentials ===${NC}"
## -------------------------------------------------------------------------- ##

# Prompt user for credentials interactively
read -p "Enter the desired ClickHouse username: " CLICKHOUSE_USER
while [[ -z "$CLICKHOUSE_USER" ]]; do
    echo -e "${RED}Username cannot be empty.${NC}"
    read -p "Enter the desired ClickHouse username: " CLICKHOUSE_USER
done

read -sp "Enter the desired ClickHouse password: " CLICKHOUSE_PASSWORD
while [[ -z "$CLICKHOUSE_PASSWORD" ]]; do
    echo -e "\n${RED}Password cannot be empty.${NC}"
    read -sp "Enter the desired ClickHouse password: " CLICKHOUSE_PASSWORD
done
echo # Newline after hidden password input

GRAFANA_ADMIN_PASS="admin"

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 2/6: Updating System & Installing Dependencies ===${NC}"
## -------------------------------------------------------------------------- ##
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    wget \
    software-properties-common \
    jq \
    net-tools

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 3/6: Installing and Securing ClickHouse ===${NC}"
## -------------------------------------------------------------------------- ##
# Add official ClickHouse repository
rm -f /etc/apt/sources.list.d/clickhouse.list
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-server clickhouse-client
echo -e "${GREEN}ClickHouse installed successfully.${NC}"

# FIXED: Configure ClickHouse step-by-step to avoid startup conflicts
# Clean up any existing configs first
rm -rf /etc/clickhouse-server/config.d/*
rm -rf /etc/clickhouse-server/users.d/*

# Backup the original config
cp /etc/clickhouse-server/config.xml /etc/clickhouse-server/config.xml.backup

# Step 1: Configure external access in main config
echo -e "${BLUE}Configuring ClickHouse for external access...${NC}"
sed -i 's/<!-- <listen_host>0.0.0.0<\/listen_host> -->/<listen_host>0.0.0.0<\/listen_host>/' /etc/clickhouse-server/config.xml

# Test restart with basic config
systemctl restart clickhouse-server
sleep 3
if ! systemctl is-active --quiet clickhouse-server; then
    echo -e "${RED}Error: ClickHouse failed to start with external access config.${NC}"
    journalctl -u clickhouse-server --no-pager -n 20
    exit 1
fi
echo -e "${GREEN}External access configured successfully.${NC}"

# Step 2: Add Prometheus configuration
echo -e "${BLUE}Adding Prometheus metrics endpoint...${NC}"
tee /etc/clickhouse-server/config.d/prometheus.xml > /dev/null <<EOF
<clickhouse>
    <prometheus>
        <endpoint>/metrics</endpoint>
        <port>9363</port>
        <metrics>true</metrics>
        <events>true</events>
        <asynchronous_metrics>true</asynchronous_metrics>
        <status_info>true</status_info>
    </prometheus>
</clickhouse>
EOF

# Test restart with Prometheus config
systemctl restart clickhouse-server
sleep 3
if ! systemctl is-active --quiet clickhouse-server; then
    echo -e "${RED}Error: ClickHouse failed to start with Prometheus config.${NC}"
    journalctl -u clickhouse-server --no-pager -n 20
    exit 1
fi
echo -e "${GREEN}Prometheus exporter enabled on port 9363.${NC}"

# Step 3: Add custom user configuration
echo -e "${BLUE}Creating custom ClickHouse user '${CLICKHOUSE_USER}'...${NC}"
PASSWORD_HASH=$(echo -n "$CLICKHOUSE_PASSWORD" | sha256sum | tr -d ' -')
tee /etc/clickhouse-server/users.d/admin-user.xml > /dev/null <<EOF
<clickhouse>
    <users>
        <${CLICKHOUSE_USER}>
            <password_sha256_hex>${PASSWORD_HASH}</password_sha256_hex>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </${CLICKHOUSE_USER}>
    </users>
</clickhouse>
EOF

# Final restart and verification
systemctl restart clickhouse-server
sleep 5
if ! systemctl is-active --quiet clickhouse-server; then
    echo -e "${RED}Error: ClickHouse failed to start with user config.${NC}"
    echo -e "${YELLOW}Trying to recover by removing user config...${NC}"
    rm -f /etc/clickhouse-server/users.d/admin-user.xml
    systemctl restart clickhouse-server
    sleep 3
    if systemctl is-active --quiet clickhouse-server; then
        echo -e "${YELLOW}ClickHouse recovered without custom user. You can use default user.${NC}"
    else
        echo -e "${RED}Failed to recover ClickHouse. Check logs manually.${NC}"
        journalctl -u clickhouse-server --no-pager -n 30
        exit 1
    fi
else
    echo -e "${GREEN}ClickHouse user '${CLICKHOUSE_USER}' configured successfully.${NC}"
fi

echo -e "${GREEN}ClickHouse server is running with all configurations.${NC}"

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 4/6: Installing and Configuring Prometheus ===${NC}"
## -------------------------------------------------------------------------- ##
PROM_VERSION="2.53.0"
useradd --system --no-create-home --shell /bin/false prometheus || true
mkdir -p /etc/prometheus /var/lib/prometheus
cd /tmp
wget -q -O prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf prometheus.tar.gz
cp prometheus-${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
cp prometheus-${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/
cp -r prometheus-${PROM_VERSION}.linux-amd64/{consoles,console_libraries} /etc/prometheus/
rm -rf prometheus-${PROM_VERSION}.linux-amd64 prometheus.tar.gz
echo -e "${GREEN}Prometheus v${PROM_VERSION} installed.${NC}"

# Configure Prometheus to scrape itself and ClickHouse (with authentication)
tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'clickhouse'
    static_configs:
      - targets: ['localhost:9363']
    basic_auth:
      username: '${CLICKHOUSE_USER}'
      password: '${CLICKHOUSE_PASSWORD}'
EOF

chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /usr/local/bin/{prometheus,promtool}
echo -e "${GREEN}Prometheus configured to scrape ClickHouse.${NC}"

# Setup Prometheus as a systemd service
tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

# Restart and verify Prometheus
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
sleep 5
if ! systemctl is-active --quiet prometheus; then
    echo -e "${RED}Error: Prometheus failed to start.${NC}"
    journalctl -u prometheus --no-pager
    exit 1
fi
echo -e "${GREEN}Prometheus service is running.${NC}"

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 5/6: Installing and Configuring Grafana ===${NC}"
## -------------------------------------------------------------------------- ##

# Ensure the keyrings directory exists before writing to it
mkdir -p /etc/apt/keyrings

wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y grafana
echo -e "${GREEN}Grafana installed successfully.${NC}"

# Start, enable, and verify Grafana
systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server
sleep 10 # Give Grafana time to start fully
if ! systemctl is-active --quiet grafana-server; then
    echo -e "${RED}Error: Grafana failed to start.${NC}"
    journalctl -u grafana-server --no-pager
    exit 1
fi
echo -e "${GREEN}Grafana service is running.${NC}"

# Automatically add Prometheus as a datasource
curl -s -u "admin:${GRAFANA_ADMIN_PASS}" \
     -H "Content-Type: application/json" \
     -X POST \
     -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy","isDefault":true}' \
     http://localhost:3000/api/datasources | jq
echo -e "${GREEN}Prometheus datasource added to Grafana.${NC}"

## -------------------------------------------------------------------------- ##
echo -e "\n${YELLOW}=== Step 6/6: Final Summary ===${NC}"
## -------------------------------------------------------------------------- ##
VM_IP=$(hostname -I | awk '{print $1}')
clear
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}          🎉 Stack Installation Complete! 🎉             ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}VM IP Address: ${YELLOW}${VM_IP}${NC}"
echo ""
echo -e "${YELLOW}📊 Service URLs:${NC}"
echo -e "  • Grafana:         ${BLUE}http://${VM_IP}:3000${NC} (Login: admin / ${GRAFANA_ADMIN_PASS})"
echo -e "  • Prometheus:      ${BLUE}http://${VM_IP}:9090${NC}"
echo -e "  • ClickHouse HTTP: ${BLUE}http://${VM_IP}:8123${NC}"
echo ""
echo -e "${YELLOW}🔐 Your Custom Credentials:${NC}"
echo -e "  • ClickHouse User: ${RED}${CLICKHOUSE_USER}${NC}"
echo -e "  • ClickHouse Pass: ${RED}${CLICKHOUSE_PASSWORD}${NC}"
echo ""
echo -e "${YELLOW}📈 Next Steps:${NC}"
echo -e "  1. Open Grafana in your browser."
echo -e "  2. Login and change the default admin password."
echo -e "  3. Import a Grafana dashboard for ClickHouse. A popular one is ID ${GREEN}14192${NC}."
echo ""
echo -e "${YELLOW}🛠️  Test ClickHouse Connection:${NC}"
echo -e "  • Run: ${GREEN}clickhouse-client --host 127.0.0.1 --user '${CLICKHOUSE_USER}' --password '${CLICKHOUSE_PASSWORD}' --query 'SELECT version()'${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
