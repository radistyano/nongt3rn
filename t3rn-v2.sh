#!/bin/bash

# ASCII ART
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
read -p "🔗 Masukkan Alchemy API Key: " APIKEY_ALCHEMY
read -p "⛽ Masukkan Gas Price (default: 300): " GAS_PRICE
GAS_PRICE=${GAS_PRICE:-300}
read -p "👤 Masukkan USER untuk executor (default: root): " EXECUTOR_USER
EXECUTOR_USER=${EXECUTOR_USER:-root}

# Pilih RPC
echo "🔌 Pilih RPC yang akan digunakan:"
echo "1. Default RPC"
echo "2. Alchemy RPC"
echo "3. BlockPI RPC"
read -p "Masukkan pilihan (1/2/3): " RPC_CHOICE

# ====== RPC ENDPOINT BASED ON CHOICE ========
case $RPC_CHOICE in
    1)
        echo "🔌 Menggunakan Default RPC"
        RPC_ENDPOINTS='{
          "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
          "arbt": ["https://arbitrum-sepolia.drpc.org"],
          "bast": ["https://base-sepolia-rpc.publicnode.com"],
          "blst": ["https://sepolia.blast.io"],
          "opst": ["https://sepolia.optimism.io"],
          "unit": ["https://unichain-sepolia.drpc.org"]
        }'
        ;;
    2)
        echo "🔌 Menggunakan Alchemy RPC"
        RPC_ENDPOINTS='{
          "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
          "arbt": ["https://arbitrum-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
          "bast": ["https://base-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
          "blst": ["https://blast-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
          "opst": ["https://opt-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
          "unit": ["https://unichain-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"]
        }'
        ;;
    3)
        echo "🔌 Menggunakan BlockPI RPC"
        read -p "🔑 Masukkan API Key BlockPI Anda: " BLOCKPI_KEY
        RPC_ENDPOINTS='{
          "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"],
          "arbt": ["https://arbitrum-sepolia.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"],
          "bast": ["https://base-sepolia.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"],
          "blst": ["https://blast-sepolia.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"],
          "opst": ["https://optimism-sepolia.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"],
          "unit": ["https://unichain-sepolia.blockpi.network/v1/rpc/'"$BLOCKPI_KEY"'"]
        }'
        ;;
    *)
        echo "❌ Pilihan tidak valid. Menggunakan Default RPC."
        RPC_ENDPOINTS='{
          "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "http://b2n.rpc.caldera.xyz/http"],
          "arbt": ["https://arbitrum-sepolia.drpc.org"],
          "bast": ["https://base-sepolia-rpc.publicnode.com"],
          "blst": ["https://sepolia.blast.io"],
          "opst": ["https://sepolia.optimism.io"],
          "unit": ["https://unichain-sepolia.drpc.org"]
        }'
        ;;
esac

# ====== PREPARE ============
INSTALL_DIR="/home/$EXECUTOR_USER/t3rn"
ENV_FILE="/etc/t3rn-executor.env"
SERVICE_FILE="/etc/systemd/system/t3rn-executor.service"
EXECUTOR_VERSION="v0.61.0"
EXECUTOR_FILE="executor-linux-$EXECUTOR_VERSION.tar.gz"
EXECUTOR_URL="https://github.com/t3rn/executor-release/releases/download/$EXECUTOR_VERSION/$EXECUTOR_FILE"

# Clean up jika ada
sudo systemctl stop t3rn-executor.service &>/dev/null
sudo systemctl disable t3rn-executor.service &>/dev/null
sudo rm -rf "$INSTALL_DIR" "$ENV_FILE" "$SERVICE_FILE"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# ====== PROSES PARAREL ========

echo "🚀 Memulai instalasi paralel..."

# Download Executor
(
    echo "🔽 Mengunduh Executor..."
    wget -q "$EXECUTOR_URL" -O "$EXECUTOR_FILE" && \
    tar -xzf "$EXECUTOR_FILE" && \
    rm "$EXECUTOR_FILE"
    echo "✅ Executor siap."
) &

# Buat File ENV
(
    echo "⚙️ Membuat file ENV..."
    sleep 1 
    cat <<EOF | sudo tee "$ENV_FILE" > /dev/null
RPC_ENDPOINTS='$RPC_ENDPOINTS'
EXECUTOR_MAX_L3_GAS_PRICE="$GAS_PRICE"
PRIVATE_KEY_LOCAL="$PRIVATE_KEY"
ENABLED_NETWORKS="l2rn,arbitrum-sepolia,base-sepolia,optimism-sepolia,unichain-sepolia,blast-sepolia"
EOF
    sudo chmod 600 "$ENV_FILE"
    echo "✅ ENV berhasil disimpan."
) &

wait  # Tunggu semua proses paralel selesai

# Buat Service Systemd
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
RestartSec=10
Environment=ENVIRONMENT=testnet
Environment=LOG_LEVEL=debug
Environment=LOG_PRETTY=false
Environment=EXECUTOR_PROCESS_BIDS_ENABLED=true
Environment=EXECUTOR_PROCESS_ORDERS_ENABLED=true
Environment=EXECUTOR_PROCESS_CLAIMS_ENABLED=true
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=false
Environment=EXECUTOR_PROCESS_ORDERS_API_ENABLED=false
EnvironmentFile=$ENV_FILE
Environment=ENABLED_NETWORKS=l2rn,arbitrum-sepolia,base-sepolia,blst-sepolia,optimism-sepolia,unichain-sepolia

[Install]
WantedBy=multi-user.target
EOF

# Aktifkan service
sudo systemctl daemon-reload
sudo systemctl enable t3rn-executor.service
sudo systemctl start t3rn-executor.service

# Tampilkan status
echo "✅ Instalasi selesai!"
sudo systemctl status t3rn-executor.service --no-pager
