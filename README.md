# Local Grocery Micro-Bargain

Hyperlocal grocery & live-bargain marketplace (pilot: Bharatpur).

```
Local Vendors/
├── backend/                 Django + DRF + PostGIS API (modular monolith)
│   ├── config/              settings (base/development/staging/production), urls, celery
│   ├── apps/                domain apps (see "Modules")
│   │   └── <app>/           models, serializers, views, urls, services, admin, tests/, [tasks]
│   ├── common/              permissions, pagination, exceptions, validators, utils
│   ├── templates/admin/     business dashboard for the Django admin
│   ├── requirements/        base / development / production
│   └── Dockerfile
├── mobile/                  Flutter app: customer + merchant in one app, switched by account role
│   └── lib/
│       ├── core/            config, network (Dio + JWT refresh), auth session, router, location, push, payments
│       ├── features/        auth, customer/*, merchant/*, notifications, support
│       └── shared/          models and reusable widgets
├── deploy/Caddyfile         HTTPS reverse proxy for production
├── scripts/                 setup_wsl.sh, backup_db.sh
├── docker-compose.yml       development stack
└── docker-compose.prod.yml  production stack (Caddy, Gunicorn, Celery, PostGIS, Redis)
```

## Modules

| App | What it does |
|---|---|
| accounts | OTP login (console or MSG91 SMS), JWT, profile |
| customers | search radius, notification preferences, addresses |
| merchants / shops | merchant registration, shop with GPS location, documents, admin approval |
| categories / products | catalogue with photos |
| inventory | optional stock-on-hand per product; deals can't exceed it; sales deduct it |
| deals | time-limited offers, PostGIS "near me" search, featured boost, view counts |
| reservations | reserve and pay at the shop; 4-digit pickup code; 45-minute hold |
| orders | multi-item orders, pickup or delivery, cash or online, coupons, delivery fee |
| payments | Razorpay orders, server-side signature check, idempotent webhook, refunds |
| commissions | configurable % per category (default 3%) on completed sales; settlement in admin |
| subscriptions | Free / Basic ₹199 / Premium ₹499 plans: live-deal limits, analytics, featured listing |
| advertisements | paid featured deals and home-screen banners |
| reviews | one rating per completed purchase; shop average; merchant replies; admin hiding |
| notifications | in-app inbox + FCM push; nearby/favourite deal alerts with daily cap and quiet hours |
| support | complaint tickets with a message thread; replies from the admin |
| analytics | admin dashboard and reports with Excel export; merchant sales analytics |
| audit | read-only log of approvals, refunds, settlements |

## Backend setup

### Option W — WSL Ubuntu (what this machine uses)

One-time: `wsl -d Ubuntu -- bash "/mnt/c/Users/User_PC/Desktop/Local Vendors/scripts/setup_wsl.sh"`

Then, inside `wsl -d Ubuntu`:

```bash
sudo service postgresql start && sudo service redis-server start   # after a Windows restart
cd "/mnt/c/Users/User_PC/Desktop/Local Vendors/backend"
~/.venvs/micro_bargain/bin/pip install -r requirements/development.txt
~/.venvs/micro_bargain/bin/python manage.py migrate
~/.venvs/micro_bargain/bin/python manage.py createsuperuser        # admin login (phone + password)
~/.venvs/micro_bargain/bin/python -m pytest                        # full test suite on PostGIS
~/.venvs/micro_bargain/bin/python manage.py runserver 0.0.0.0:8000 --noreload
~/.venvs/micro_bargain/bin/celery -A config worker -B -l info      # expiry jobs, pushes, refunds
```

`--noreload` avoids a slow start: the auto-reloader scans the Windows `.venv` folder through `/mnt/c`.
In development the login OTP is printed in the runserver log (`SMS to 98xxxxxxxx: 123456`).

### Option A — Docker

```bash
cp backend/.env.example backend/.env      # set DJANGO_SECRET_KEY
docker compose up -d --build
docker compose exec web python manage.py migrate
docker compose exec web python manage.py createsuperuser
```

URLs: API `http://localhost:8000/api/v1/`, Swagger `http://localhost:8000/api/docs/`,
Admin `http://localhost:8000/admin/`, business dashboard `http://localhost:8000/admin/dashboard/`.

### Development stand-ins

Everything works without third-party accounts:

| Setting | Development | Production |
|---|---|---|
| `SMS_BACKEND` | `console` (OTP in the log) | `msg91` + `MSG91_AUTH_KEY`, `MSG91_OTP_TEMPLATE_ID` (DLT-approved template with an `otp` variable) |
| `PUSH_BACKEND` | `console` (inbox only) | `fcm` + `FCM_CREDENTIALS_FILE` |
| `PAYMENT_BACKEND` | `fake` (app shows a "test payment" dialog) | `razorpay` + `RAZORPAY_KEY_ID/SECRET/WEBHOOK_SECRET` |

`config.settings.production` refuses to start with any development stand-in.

### Firebase (push notifications)

1. Firebase console → create a project → add an Android app with package `com.microbargain.micro_bargain`.
2. Download `google-services.json` into `mobile/android/app/` and add the Google services Gradle plugin
   (Firebase console shows the two lines).
3. Project settings → Service accounts → Generate new private key. Save the JSON outside the repo and set
   `PUSH_BACKEND=fcm`, `FCM_CREDENTIALS_FILE=/path/to/key.json` in `backend/.env`.

Without `google-services.json` the app runs normally and notifications appear in its inbox only.

### Razorpay

1. Create a Razorpay account, get test keys (Settings → API keys).
2. `PAYMENT_BACKEND=razorpay`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` in `backend/.env`.
3. Webhooks → URL `https://<domain>/api/v1/payments/webhook/`, events `payment.captured`, `payment.failed`,
   `refund.processed`, `refund.failed`; put the webhook secret in `RAZORPAY_WEBHOOK_SECRET`.

## Mobile app

```bash
cd mobile
flutter pub get
flutter run                                                        # emulator -> http://10.0.2.2:8000
flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000/api/v1   # real phone on the same Wi-Fi
flutter build apk --release --dart-define=API_BASE_URL=https://<domain>/api/v1
flutter analyze && flutter test
```

Customers: nearby deals (radius, category, sort, search), reserve or order, pay online, pickup code,
favourites, reviews, addresses, notification settings, support.
Merchants (same app, after "अपनी दुकान जोड़ें"): shop setup with GPS and documents, products with photos,
deals (create / publish / pause / stock / duplicate), reservations and orders with code check, stock,
plans, promotions, reviews, sales and commission.

### Test on a real phone (today, no server needed)

1. Install `MicroBargain.apk` (on the Desktop) on an Android phone on the **same Wi-Fi** as this PC.
2. Start the backend in WSL (see "Option W" above) with `runserver 0.0.0.0:8000 --noreload` and the Celery worker.
3. Let the phone reach WSL. In PowerShell **as Administrator**, once per Windows start:
   ```powershell
   $ip = (wsl -d Ubuntu -- hostname -I).Trim().Split(" ")[0]
   netsh interface portproxy add v4tov4 listenport=8000 listenaddress=0.0.0.0 connectport=8000 connectaddress=$ip
   New-NetFirewallRule -DisplayName "Micro Bargain API 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
   ```
   (The firewall rule is needed only the first time.)
4. Log in with any number; the OTP is printed in the runserver window. Admin: `http://localhost:8000/admin/`.

The APK was built for `http://10.249.104.91:8000/api/v1` (this PC's Wi-Fi address). If the address changes,
rebuild with the new one: `flutter build apk --release --dart-define=API_BASE_URL=http://<ip>:8000/api/v1`.

### Play Store release

1. `bash scripts/make_upload_key.sh` once, then back up `mobile/android/upload-keystore.jks` and its password.
2. `flutter build appbundle --release --dart-define=API_BASE_URL=https://api.<domain>/api/v1`
3. Store listing: icon `mobile/store/play_store_icon_512.png`; privacy policy URL `https://api.<domain>/legal/privacy/`.
   Account deletion: in the app under Profile → अकाउंट डिलीट करें (Play Console asks for this).

Before release, remove `android:usesCleartextTraffic="true"` from `AndroidManifest.xml` (only needed for the
`http://` development server) and set up signing for the Play Store.

## Deploy (one VPS, e.g. 2 vCPU / 4 GB Ubuntu)

**Free demo, no card:** Render (`render.yaml` Blueprint). Guide in Hindi: [deploy/RENDER_FREE_SETUP.md](deploy/RENDER_FREE_SETUP.md).

**Free server (needs a Visa/Mastercard for verification):** Oracle Cloud Always Free. Step-by-step guide in Hindi: [deploy/ORACLE_FREE_SETUP.md](deploy/ORACLE_FREE_SETUP.md).
After creating the server, one command from this PC deploys everything:
`bash deploy/deploy_from_pc.sh <server-ip> <ssh-key-file>` (uses `<ip>.sslip.io` with HTTPS if you have no domain).
Until MSG91 / Razorpay / Firebase are approved it runs as a test server (`ALLOW_TEST_BACKENDS=True`).

Manual setup on any VPS:

```bash
# DNS: point api.<your-domain> to the server's IP first.
git clone <repo> /opt/micro_bargain && cd /opt/micro_bargain
cp backend/.env.example backend/.env
#   DJANGO_SECRET_KEY=<long random>   DJANGO_DEBUG=False   DJANGO_ALLOWED_HOSTS=api.<your-domain>
#   CSRF_TRUSTED_ORIGINS=https://api.<your-domain>   POSTGRES_PASSWORD=<strong>
#   SMS / push / payment settings from the table above
DOMAIN=api.<your-domain> docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser
crontab -e   # 30 2 * * * /opt/micro_bargain/scripts/backup_db.sh >> /var/log/mb_backup.log 2>&1
```

Caddy obtains the HTTPS certificate automatically. Migrations and `collectstatic` run on every start.

## Conventions

- Business logic goes in each app's `services.py`; views stay thin.
- Every API error uses `{"error": {"code", "message", "details"}}`; lists are `{count, next, previous, results}`.
- Querysets are scoped to the owner, so another user's object id returns 404.
- Stock changes use `transaction.atomic()` + `select_for_update()`, backed by database check constraints.
- Money-related admin actions go through services and are written to the audit log.
