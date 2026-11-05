#!/usr/bin/env bash
# One-command setup of the backend on a fresh Ubuntu 22.04/24.04 server (x86 or ARM, e.g. Oracle Cloud Free).
# Run from the project folder on the server:   bash deploy/setup_server.sh [domain]
#
# Without a domain it uses <ip>.sslip.io (free, works with HTTPS). Safe to run again: existing
# secrets in backend/.env are kept; it only rebuilds and restarts the containers.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DIR="$(pwd)"

echo "==> Installing Docker"
if ! command -v docker >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2 curl openssl cron >/dev/null
  sudo systemctl enable --now docker
fi
DOCKER="sudo docker"

echo "==> Opening ports 80 and 443"
# Oracle's Ubuntu images block everything except SSH in iptables; cloud firewalls (security lists) are separate.
for port in 80 443; do
  sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
done
if command -v netfilter-persistent >/dev/null; then sudo netfilter-persistent save >/dev/null 2>&1 || true; fi

# Small servers need swap to build the images.
if [ "$(free -m | awk '/Mem:/ {print $2}')" -lt 3000 ] && ! sudo swapon --show | grep -q swapfile; then
  echo "==> Adding 2 GB swap"
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
fi

IP="$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)"
DOMAIN="${1:-${IP//./-}.sslip.io}"
case "$(uname -m)" in
  aarch64|arm64) POSTGIS_IMAGE="imresamu/postgis:16-3.4" ;;
  *)             POSTGIS_IMAGE="postgis/postgis:16-3.4" ;;
esac
printf "DOMAIN=%s\nPOSTGIS_IMAGE=%s\n" "$DOMAIN" "$POSTGIS_IMAGE" > .env
echo "==> Domain: https://$DOMAIN"

if [ ! -f backend/.env ]; then
  echo "==> Writing backend/.env with new random secrets"
  cp backend/.env.example backend/.env
  set_env() { sed -i "s|^$1=.*|$1=$2|" backend/.env; grep -q "^$1=" backend/.env || echo "$1=$2" >> backend/.env; }
  set_env DJANGO_SETTINGS_MODULE config.settings.production
  set_env DJANGO_SECRET_KEY "$(openssl rand -hex 40)"
  set_env DJANGO_DEBUG False
  set_env DJANGO_ALLOWED_HOSTS "$DOMAIN"
  set_env CSRF_TRUSTED_ORIGINS "https://$DOMAIN"
  set_env POSTGRES_PASSWORD "$(openssl rand -hex 24)"
  set_env POSTGRES_HOST db
  set_env REDIS_URL redis://redis:6379/0
  # Until MSG91 / Razorpay / Firebase are approved this is a TEST server: OTPs are in the logs, payments are fake.
  set_env ALLOW_TEST_BACKENDS True
  chmod 600 backend/.env
else
  sed -i "s|^DJANGO_ALLOWED_HOSTS=.*|DJANGO_ALLOWED_HOSTS=$DOMAIN|; s|^CSRF_TRUSTED_ORIGINS=.*|CSRF_TRUSTED_ORIGINS=https://$DOMAIN|" backend/.env
fi

echo "==> Building and starting (first time takes 5-15 minutes)"
$DOCKER compose -f docker-compose.prod.yml up -d --build

echo "==> Waiting for https://$DOMAIN/health/"
for _ in $(seq 1 60); do
  if curl -sf "https://$DOMAIN/health/" >/dev/null; then OK=1; break; fi
  sleep 5
done

echo "==> Daily database backup at 02:30"
( crontab -l 2>/dev/null | grep -v backup_db.sh; echo "30 2 * * * BACKUP_DIR=$HOME/backups $APP_DIR/scripts/backup_db.sh >> $HOME/backup.log 2>&1" ) | crontab -

echo
if [ "${OK:-0}" = 1 ]; then
  echo "LIVE: https://$DOMAIN/api/v1/    docs: https://$DOMAIN/api/docs/    admin: https://$DOMAIN/admin/"
else
  echo "Containers started but https://$DOMAIN is not answering yet."
  echo "Check the cloud firewall allows TCP 80 and 443, then: sudo docker compose -f docker-compose.prod.yml logs caddy web"
fi
echo "Create the admin login:  sudo docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser"
echo "See login OTPs (test mode): sudo docker compose -f docker-compose.prod.yml logs -f web | grep 'SMS to'"
