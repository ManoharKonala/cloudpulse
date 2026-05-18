#!/usr/bin/env bash
# Bootstraps a fresh Ubuntu 22.04 EC2 instance with Docker, clones CloudPulse,
# and starts all services. Run as: bash setup-ec2.sh <YOUR_GITHUB_REPO_URL>
set -euo pipefail

REPO_URL="${1:-https://github.com/manoharkonala/cloudpulse.git}"
INSTALL_DIR="/opt/cloudpulse"

echo "=========================================="
echo "  CloudPulse EC2 Bootstrap"
echo "=========================================="

# ── System packages ──────────────────────────────────────────────────
echo "[1/5] Installing system packages..."
sudo apt-get update -y
sudo apt-get install -y \
    docker.io \
    docker-compose \
    git \
    curl \
    htop

# ── Docker ───────────────────────────────────────────────────────────
echo "[2/5] Configuring Docker..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker "$USER"

# ── Clone repo ───────────────────────────────────────────────────────
echo "[3/5] Cloning repository..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists — pulling latest..."
    cd "$INSTALL_DIR" && sudo git pull origin main
else
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
    sudo chown -R "$USER":"$USER" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── Start services ───────────────────────────────────────────────────
echo "[4/5] Starting CloudPulse services..."
# Run with newgrp to pick up docker group without logout
sudo docker-compose up -d

# ── Print access URLs ────────────────────────────────────────────────
echo "[5/5] Waiting for services to be ready..."
sleep 15

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")

echo ""
echo "=========================================="
echo "  CloudPulse is running!"
echo "=========================================="
echo "  Frontend:   http://${PUBLIC_IP}"
echo "  Prometheus: http://${PUBLIC_IP}:9090"
echo "  Grafana:    http://${PUBLIC_IP}:3000  (admin / admin123)"
echo "  Products API: http://${PUBLIC_IP}:5001/products"
echo "  Orders API:   http://${PUBLIC_IP}:5002/orders"
echo "=========================================="
