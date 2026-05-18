#!/usr/bin/env bash
# Provisions CloudPulse AWS infrastructure via Terraform.
# Usage: bash terraform-deploy.sh [destroy]
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")/../infrastructure/terraform" && pwd)"
ACTION="${1:-apply}"

echo "=========================================="
echo "  CloudPulse Terraform Deployment"
echo "  Directory: $TF_DIR"
echo "=========================================="

cd "$TF_DIR"

# ── Init ─────────────────────────────────────────────────────────────
echo "[1/3] terraform init..."
terraform init

if [ "$ACTION" = "destroy" ]; then
    echo "[!] Destroying infrastructure..."
    terraform destroy -auto-approve
    echo "Infrastructure destroyed."
    exit 0
fi

# ── Plan ─────────────────────────────────────────────────────────────
echo "[2/3] terraform plan..."
terraform plan -out=tfplan

# ── Apply ────────────────────────────────────────────────────────────
echo "[3/3] terraform apply..."
terraform apply tfplan

echo ""
echo "=========================================="
echo "  Deployment complete! Outputs:"
echo "=========================================="
terraform output

echo ""
echo "Next steps:"
echo "  1. SSH to app server:     ssh -i ~/.ssh/id_rsa ubuntu@\$(terraform output -raw app_server_public_ip)"
echo "  2. SSH to Jenkins server: ssh -i ~/.ssh/id_rsa ubuntu@\$(terraform output -raw jenkins_server_public_ip)"
echo "  3. Run on app server:     bash /tmp/setup-ec2.sh <YOUR_REPO_URL>"
echo "=========================================="
