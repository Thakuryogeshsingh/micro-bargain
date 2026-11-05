#!/usr/bin/env bash
# Copies the committed code to the server and runs setup there. Run from WSL / Git Bash on this PC:
#   bash deploy/deploy_from_pc.sh <server-ip> <path-to-ssh-private-key> [ssh-user] [domain]
# ssh-user defaults to "ubuntu" (Oracle Cloud Ubuntu images). Only committed files are sent (git archive),
# so local secrets such as backend/.env never leave this PC.
set -euo pipefail
IP="${1:?server IP}"
KEY="${2:?path to SSH private key}"
USER_NAME="${3:-ubuntu}"
DOMAIN="${4:-}"
cd "$(dirname "$0")/.."
chmod 600 "$KEY" 2>/dev/null || true
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$USER_NAME@$IP")

echo "==> Sending code to $IP"
"${SSH[@]}" "sudo mkdir -p /opt/micro_bargain && sudo chown \$USER: /opt/micro_bargain"
git archive --format=tar HEAD | "${SSH[@]}" "tar -x -C /opt/micro_bargain"

echo "==> Running setup on the server"
"${SSH[@]}" "bash /opt/micro_bargain/deploy/setup_server.sh $DOMAIN"
