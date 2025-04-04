#!/bin/bash

# ====== ASCII ART ======
echo "

.%%..%%...%%%%...%%..%%...%%%%...%%..%%..%%%%%%...........%%%%...%%%%%...%%..%%..%%%%%...%%%%%%...%%%%..
.%%%.%%..%%..%%..%%%.%%..%%......%%.%%.....%%............%%..%%..%%..%%...%%%%...%%..%%....%%....%%..%%.
.%%.%%%..%%..%%..%%.%%%..%%.%%%..%%%%......%%............%%......%%%%%.....%%....%%%%%.....%%....%%..%%.
.%%..%%..%%..%%..%%..%%..%%..%%..%%.%%.....%%............%%..%%..%%..%%....%%....%%........%%....%%..%%.
.%%..%%...%%%%...%%..%%...%%%%...%%..%%..%%%%%%...........%%%%...%%..%%....%%....%%........%%.....%%%%..
........................................................................................................
"

# ====== INPUT ============
read -p "🔐 Masukkan PRIVATE_KEY: " PRIVATE_KEY
read -p "⛽ Masukkan Gas Price (default: 300): " GAS_PRICE
GAS_PRICE=${GAS_PRICE:-300}
read -p "👤 Masukkan USER untuk executor (default: root): " EXECUTOR_USER
EXECUTOR_USER=${EXECUTOR_USER:-root}

# ====== PILIH RPC ==========
echo "🔌 Pilih RPC yang akan digunakan:"
echo "1. Default RPC"
echo "2. Alchemy RPC"
echo "3. BlockPI RPC (multi URL input)"
read -p "Masukkan pilihan (1/2/3): " RPC_CHOICE

# ====== HANDLE PILIHAN RPC =======
if [[ "$RPC_CHOICE" == "2" ]]; then
    read -p "🔗 Masukkan Alchemy API Key: " APIKEY_ALCHEMY
    RPC_ENDPOINTS='{
      "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
      "arbt": ["https://arbitrum-sepolia.g.alchemy.com/v2/'"$APIKEY_ALCHEMY"'"] ,
      "bast": ["https://base-sepolia.g.alchemy.com/v2/'"$APIKEY_ALCHEMY"'"] ,
      "blst": ["https://blast-sepolia.g.alchemy.com/v2/'"$APIKEY_ALCHEMY"'"] ,
      "opst": ["https://opt-sepolia.g.alchemy.com/v2/'"$APIKEY_ALCHEMY"'"] ,
      "unit": ["https://unichain-sepolia.g.alchemy.com/v2/'"$APIKEY_ALCHEMY"'"] 
    }'

elif [[ "$RPC_CHOICE" == "3" ]]; then
    echo "🔌 Masukkan semua URL BlockPI kamu (1 baris per URL), diakhiri dengan baris kosong:"
    BLOCKPI_URLS=()
    while read -r line; do
        [[ -z "$line" ]] && break
        BLOCKPI_URLS+=("$line")
    done

    map_rpc_key() {
        local url=$1
        case $url in
            *t3rn-b2n*) echo "l2rn" ;;
            *arbitrum*) echo "arbt" ;;
            *base*) echo "bast" ;;
            *blast*) echo "blst" ;;
            *optimism*) echo "opst" ;;
            *unichain*) echo "unit" ;;
            *) echo "unknown" ;;
        esac
    }

    RPC_ENDPOINTS="{"
    for url in "${BLOCKPI_URLS[@]}"; do
        key=$(map_rpc_key "$url")
        if [[ "$key" != "unknown" ]]; then
            RPC_ENDPOINTS+='"'$key'": ["'$url'"],'
        fi
    done
    RPC_ENDPOINTS="${RPC_ENDPOINTS%,}}"

else
    echo "🔌 Menggunakan Default RPC"
    RPC_ENDPOINTS='{
      "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
      "arbt": ["https://arbitrum-sepolia.drpc.org"],
      "bast": ["https://base-sepolia-rpc.publicnode.com"],
      "blst": ["https://sepolia.blast.io"],
      "opst": ["https://sepolia.optimism.io"],
      "unit": ["https://unichain-sepolia.drpc.org"]
    }'
fi

# ====== INSTALL SETUP ==========
INSTALL_DIR="/home/$EXECUTOR_USER/t3rn"
ENV_FILE="/etc/t3rn-executor.env"
SERVICE_FILE="/etc/systemd/system/t3rn-executor.service"
EXECUTOR_VERSION="v0.61.0"
EXECUTOR_FILE="executor-linux-$EXECUTOR_VERSION.tar.gz"
EXECUTOR_URL="https://github.com/t3rn/executor-release/releases/download/$EXECUTOR_VERSION/$EXECUTOR_FILE"

sudo systemctl stop t3rn-executor.service &>/dev/null
sudo systemctl disable t3rn-executor.service &>/dev/null
sudo rm -rf "$INSTALL_DIR" "$ENV_FILE" "$SERVICE_FILE"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# Parallel Tasks
(
  echo "🔻 Mengunduh Executor..."
  wget -q "$EXECUTOR_URL" -O "$EXECUTOR_FILE" && \
  tar -xzf "$EXECUTOR_FILE" && \
  rm "$EXECUTOR_FILE"
  echo "✅ Executor siap."
) &

(
  echo "⚙ Membuat file ENV..."
  sleep 1
  cat <<EOF | sudo tee "$ENV_FILE" > /dev/null
RPC_ENDPOINTS='$RPC_ENDPOINTS'
EXECUTOR_MAX_L3_GAS_PRICE="$GAS_PRICE"
PRIVATE_KEY_LOCAL="$PRIVATE_KEY"
ENABLED_NETWORKS="l2rn,arbitrum-sepolia,base-sepolia,optimism-sepolia,unichain-sepolia,blast-sepolia"
EXECUTOR_PROCESS_BIDS_ENABLED=true
EXECUTOR_PROCESS_ORDERS_ENABLED=true
EXECUTOR_PROCESS_CLAIMS_ENABLED=true
EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true
EXECUTOR_PROCESS_ORDERS_API_ENABLED=true
LOG_PRETTY=false
EOF
  sudo chmod 600 "$ENV_FILE"
  echo "✅ ENV disimpan."
) &

wait

# ====== SYSTEMD SERVICE ======
echo "🛠️ Membuat systemd service..."
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=t3rn Executor Service
After=network.target

[Service]
User=$EXECUTOR_USER
WorkingDirectory=$INSTALL_DIR/executor/executor/bin
ExecStart=$INSTALL_DIR/executor/executor/bin/executor
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=10240
CPUSchedulingPolicy=rr
Environment=ENVIRONMENT=testnet
Environment=LOG_LEVEL=debug
Environment=LOG_PRETTY=false
EnvironmentFile=$ENV_FILE
Environment=ENABLED_NETWORKS=l2rn,arbitrum-sepolia,base-sepolia,blst-sepolia,optimism-sepolia,unichain-sepolia

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable t3rn-executor.service
sudo systemctl start t3rn-executor.service

# Status & Log
echo "✅ Instalasi selesai!"
sudo systemctl status t3rn-executor.service --no-pager
read -p "📜 Ingin melihat log realtime sekarang? (y/n): " LOG_CHOICE
if [[ "$LOG_CHOICE" == "y" || "$LOG_CHOICE" == "Y" ]]; then
    echo "📊 Menampilkan log... Tekan CTRL+C untuk keluar."
    sleep 1
    sudo journalctl -u t3rn-executor.service -f --no-hostname -o cat
else
    echo "🔧 Kamu bisa lihat log kapan saja dengan perintah berikut:"
    echo "    sudo journalctl -u t3rn-executor.service -f --no-hostname -o cat"
fi
