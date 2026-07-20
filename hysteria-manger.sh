#!/bin/bash
# =============================================
# Hysteria 2 Interactive Manager (Optimized v4.1)
# =============================================

HYSTERIA_BIN="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
SERVICE_DIR="/etc/systemd/system"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure core directory exists
mkdir -p "$CONFIG_DIR"

print_header() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}    Hysteria 2 Interactive Manager      ${NC}"
    echo -e "${BLUE}========================================${NC}"
}

check_installed() {
    if [ ! -f "$HYSTERIA_BIN" ]; then
        echo -e "${RED}Hysteria 2 is not installed!${NC}"
        read -p "Do you want to install it now via official script? (y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            echo "Installing dependencies..."
            apt-get update -y || yum update -y
            apt-get install -y curl wget jq openssl || yum install -y curl wget jq openssl
            
            echo "Downloading latest Hysteria release..."
            LATEST_TAG=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | jq -r .tag_name)
            if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
                LATEST_TAG="v2.6.0"
            fi
            
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64) BINARY_NAME="hysteria-linux-amd64" ;;
                aarch64|arm64) BINARY_NAME="hysteria-linux-arm64" ;;
                *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
            esac
            
            wget -O "$HYSTERIA_BIN" "https://github.com/apernet/hysteria/releases/download/${LATEST_TAG}/${BINARY_NAME}"
            chmod +x "$HYSTERIA_BIN"
            echo -e "${GREEN}Installation successful.${NC}"
        else
            echo "Aborting execution."
            exit 1
        fi
    fi
}

ask_value() {
    local prompt=$1
    local default=$2
    local var_name=$3
    read -p "$prompt [Default: $default]: " value
    if [ -z "$value" ]; then
        value=$default
    fi
    eval "$var_name=\"$value\""
}

# New Helper function to pick bandwidth from a list
select_bandwidth() {
    echo -e "\n${YELLOW}Select Bandwidth (symmetric up/down):${NC}"
    echo "1) 128 mbps"
    echo "2) 256 mbps"
    echo "3) 512 mbps"
    echo "4) 768 mbps"
    echo "5) 1024 mbps"
    echo "6) 15144 mbps"
    echo "7) 2048 mbps"
    echo "8) Custom Value"
    read -p "Selection [Default 3 - 512 mbps]: " bw_choice
    
    case "$bw_choice" in
        1) echo "128mbps" ;;
        2) echo "256mbps" ;;
        4) echo "768mbps" ;;
        5) echo "1024mbps" ;;
        6) echo "15144mbps" ;;
        7) echo "2048mbps" ;;
        8) 
            read -p "Enter custom bandwidth (e.g., 100mbps): " custom_bw
            echo "$custom_bw"
            ;;
        *) echo "512mbps" ;; # Default back to 512
    esac
}

# New Helper function to pick SNI from a list
select_sni() {
    echo -e "\n${YELLOW}Select SNI Target (High traffic foreign domains in Iran):${NC}"
    echo "1) play.google.com (Google Play)"
    echo "2) speedtest.net (Ookla Speedtest)"
    echo "3) www.cloudflare.com (Cloudflare)"
    echo "4) www.microsoft.com (Microsoft)"
    echo "5) dl.discordapp.net (Discord CDN)"
    echo "6) Custom SNI"
    read -p "Selection [Default 1]: " sni_choice
    
    case "$sni_choice" in
        1) echo "play.google.com" ;;
        2) echo "speedtest.net" ;;
        3) echo "www.cloudflare.com" ;;
        4) echo "www.microsoft.com" ;;
        5) echo "dl.discordapp.net" ;;
        6)
            read -p "Enter custom SNI: " custom_sni
            echo "$custom_sni"
            ;;
        *) echo "play.google.com" ;;
    esac
}

manage_server() {
    echo -e "${YELLOW}=== Server Configuration ===${NC}"
    local config_file="$CONFIG_DIR/server-config.yaml"
    
    # Auto-generate keys if missing
    if [ ! -f "$CONFIG_DIR/self.crt" ]; then
        echo "Generating 10-year self-signed SSL certificates..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout "$CONFIG_DIR/self.key" \
          -out "$CONFIG_DIR/self.crt" \
          -subj "/CN=myserver"
        chmod 600 "$CONFIG_DIR/self.key"
        chmod 644 "$CONFIG_DIR/self.crt"
    fi

    # Calculate exact SHA256 pin
    local fingerprint=$(openssl x509 -noout -fingerprint -sha256 -in "$CONFIG_DIR/self.crt" | cut -d'=' -f2)

    # 1. Generate a random port between 10000 and 65000
    local RANDOM_PORT=$((RANDOM % 55001 + 10000))
    ask_value "Listen port" ":$RANDOM_PORT" LISTEN_PORT
    
    ask_value "Obfs (gecko) password" "$(openssl rand -hex 12)" OBFS_PASS
    ask_value "Auth password" "$(openssl rand -hex 12)" AUTH_PASS
    ask_value "Masquerade URL" "https://play.google.com" MASQ_URL
    
    # 2. Select Bandwidth
    local SPEED=$(select_bandwidth)

    cat > "$config_file" << EOC
listen: "$LISTEN_PORT"

tls:
  cert: $CONFIG_DIR/self.crt
  key: $CONFIG_DIR/self.key

obfs:
  type: gecko
  gecko:
    password: "$OBFS_PASS"
    minPacketSize: 512
    maxPacketSize: 1200

masquerade:
  type: proxy
  proxy:
    url: "$MASQ_URL"
    rewriteHost: true

auth:
  type: password
  password: "$AUTH_PASS"

quic:
  initStreamReceiveWindow: 50331648
  maxStreamReceiveWindow: 100663296
  initConnReceiveWindow: 100663296
  maxConnReceiveWindow: 201326592
  maxIdleTimeout: 30s
  keepAlivePeriod: 10s

bandwidth:
  up: $SPEED
  down: $SPEED

speedTest: true
EOC

    echo -e "${GREEN}Server configuration file deployed.${NC}"
    read -p "Do you want to manually verify/edit config? (y/n): " edit
    [[ "$edit" =~ ^[Yy]$ ]] && nano "$config_file"

    create_service "hysteria-server" "$HYSTERIA_BIN server --config $config_file"
    
    local public_ip=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
    echo -e "\n${BLUE}====================================================${NC}"
    echo -e "${YELLOW}           CLIENT CONFIGURATION REFERENCES          ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo "Server Address: ${public_ip}${LISTEN_PORT}"
    echo "Auth Password:  $AUTH_PASS"
    echo "Obfs Password:  $OBFS_PASS"
    echo "Tls SHA256 Pin: $fingerprint"
    echo -e "${BLUE}====================================================${NC}\n"
}

manage_client() {
    echo -e "${YELLOW}=== Client Configuration ===${NC}"
    read -p "Client instance index identifier (e.g. 1): " num
    local config_file="$CONFIG_DIR/client${num}-config.yaml"
    local svc_name="hysteria-client${num}"

    ask_value "Server destination (IP:port)" "127.0.0.1:6900" SERVER_ADDR
    ask_value "Auth password" "" AUTH_PASS
    ask_value "Obfs password" "" OBFS_PASS
    
    # 3. Select SNI Target from list
    local SNI=$(select_sni)
    
    ask_value "Target pinSHA256 (Optional)" "" PIN_SHA
    
    # 2. Select Bandwidth
    local SPEED=$(select_bandwidth)

    cat > "$config_file" << EOC
server: "$SERVER_ADDR"
auth: "$AUTH_PASS"

tls:
  sni: "$SNI"
  insecure: true
EOC

    if [[ -n "$PIN_SHA" ]]; then
        echo "  pinSHA256: \"$PIN_SHA\"" >> "$config_file"
    fi

    cat >> "$config_file" << EOC

obfs:
  type: gecko
  gecko:
    password: "$OBFS_PASS"
    minPacketSize: 512
    maxPacketSize: 1200

transport:
  type: udp
  udp:
    minHopInterval: 15s
    maxHopInterval: 45s

quic:
  initStreamReceiveWindow: 50331648
  maxStreamReceiveWindow: 100663296
  initConnReceiveWindow: 100663296
  maxConnReceiveWindow: 201326592
  maxIdleTimeout: 30s
  keepAliveInterval: 10s
  maxIncomingStreams: 8192
  disablePathMTUDiscovery: false

bandwidth:
  up: $SPEED
  down: $SPEED
EOC

    # Optimized Port Forwarding Engine
    read -p "Do you want to add static port forwarding rules? (y/n): " add_fwd
    if [[ "$add_fwd" =~ ^[Yy]$ ]]; then
        read -p "How many ports do you want to forward?: " port_count
        
        if [[ "$port_count" -gt 0 ]] 2>/dev/null; then
            local tcp_block=""
            local udp_block=""
            
            for ((i=1; i<=port_count; i++)); do
                read -p "Enter Port #$i: " target_port
                if [[ -n "$target_port" ]]; then
                    tcp_block+=$'\n'"  - listen: \"0.0.0.0:$target_port\""$'\n'"    remote: \"127.0.0.1:$target_port\""
                    udp_block+=$'\n'"  - listen: \"0.0.0.0:$target_port\""$'\n'"    remote: \"127.0.0.1:$target_port\""
                fi
            done

            if [[ -n "$tcp_block" ]]; then
                echo "tcpForwarding:$tcp_block" >> "$config_file"
                echo "udpForwarding:$udp_block" >> "$config_file"
            fi
        else
            echo "Invalid count. Skipping forwarding setup."
        fi
    fi

    echo -e "${GREEN}Client runtime configuration compiled successfully.${NC}"
    read -p "Edit config structure manually? (y/n): " edit
    [[ "$edit" =~ ^[Yy]$ ]] && nano "$config_file"

    create_service "$svc_name" "$HYSTERIA_BIN client --config $config_file"

    read -p "Verify live service status check now? (y/n): " test_run
    if [[ "$test_run" =~ ^[Yy]$ ]]; then
        sleep 1
        if systemctl is-active --quiet "$svc_name"; then
            echo -e "${GREEN}Verification Success: Service $svc_name is currently active and running.${NC}"
        else
            echo -e "${RED}Verification Failure: Service $svc_name is inactive. Check logs using: journalctl -u $svc_name -n 20${NC}"
        fi
    fi
}

create_service() {
    local name=$1
    local cmd=$2
    
    cat > "$SERVICE_DIR/$name.service" << EOF
[Unit]
Description=Hysteria 2 Service Execution ($name)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$cmd
Restart=always
RestartSec=5
Nice=-10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$name"
    echo -e "${GREEN}Systemd node status initialized and started successfully for: $name${NC}"
}

setup_monitor() {
    echo -e "${YELLOW}Deploying cron-replacement automation watchdog...${NC}"
    
    cat > /usr/local/bin/hysteria-monitor.sh << 'MONITOR'
#!/bin/bash
for config in /etc/hysteria/client*-config.yaml; do
    if [ -f "$config" ]; then
        name=$(basename "$config" .yaml)
        svc_name="hysteria-$name"
        if systemctl list-unit-files "$svc_name.service" &>/dev/null; then
            if ! systemctl is-active --quiet "$svc_name"; then
                echo "$(date) - Watchdog triggered restart on instance: $svc_name" >> /var/log/hysteria-monitor.log
                systemctl restart "$svc_name"
            fi
        fi
    fi
done
MONITOR

    chmod +x /usr/local/bin/hysteria-monitor.sh

    cat > /etc/systemd/system/hysteria-monitor.timer << EOF
[Unit]
Description=Hysteria Client Instance Watchdog Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=45
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now hysteria-monitor.timer
    echo -e "${GREEN}Automated monitoring configuration successfully armed.${NC}"
}

# ===================== ENGINE EXECUTION RUNTIME =====================
print_header
check_installed

echo -e "\nSelect an option to proceed:"
echo "1) Configure Server Instance (Foreign Server)"
echo "2) Configure Client Instance (Iran Relay Server)"
echo "3) Deploy/Update Monitoring Daemon System"
echo "4) Terminate Script Execution"
echo "----------------------------------------"
read -p "Selection (1-4): " choice

case "$choice" in
    1) manage_server ;;
    2) manage_client ;;
    3) setup_monitor ;;
    4) echo "Exiting management utility."; exit 0 ;;
    *) echo -e "${RED}Error: Invalid operation range targeted.${NC}" ;;
esac

echo -e "${GREEN}Task cycle completed successfully.${NC}"
