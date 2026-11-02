#!/usr/bin/env bash
# One-time development setup inside WSL Ubuntu 24.04:
# PostgreSQL 16 + PostGIS, GDAL, Redis, and a Python virtualenv with the backend requirements.
# Run from Windows:  wsl -d Ubuntu -- bash "/mnt/c/Users/User_PC/Desktop/Local Vendors/scripts/setup_wsl.sh"
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/../backend" && pwd)"
VENV="$HOME/.venvs/micro_bargain"

echo "==> Installing system packages (asks for your Ubuntu password once)"
sudo apt-get update
sudo apt-get install -y \
    postgresql postgresql-16-postgis-3 \
    gdal-bin libgdal-dev libgeos-dev libproj-dev \
    redis-server python3-venv python3-dev build-essential

echo "==> Starting PostgreSQL and Redis"
sudo service postgresql start
sudo service redis-server start

echo "==> Creating database user and database (development only)"
# SUPERUSER lets the test runner create test databases with the PostGIS extension.
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'micro_bargain') THEN
    CREATE ROLE micro_bargain LOGIN PASSWORD 'micro_bargain' SUPERUSER;
  END IF;
END
$$;
SQL
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'micro_bargain'" | grep -q 1 \
    || sudo -u postgres createdb -O micro_bargain micro_bargain
sudo -u postgres psql -d micro_bargain -c "CREATE EXTENSION IF NOT EXISTS postgis;"

echo "==> Creating Python virtualenv at $VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install -r "$BACKEND_DIR/requirements/development.txt"

if [ ! -f "$BACKEND_DIR/.env" ]; then
    echo "==> Creating backend/.env"
    SECRET=$("$VENV/bin/python" -c "import secrets; print(secrets.token_urlsafe(50))")
    sed "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$SECRET|" "$BACKEND_DIR/.env.example" > "$BACKEND_DIR/.env"
fi

echo "==> Checking GeoDjango"
cd "$BACKEND_DIR"
"$VENV/bin/python" manage.py check

echo ""
echo "Setup complete. Postgres + PostGIS, Redis and the virtualenv are ready."
