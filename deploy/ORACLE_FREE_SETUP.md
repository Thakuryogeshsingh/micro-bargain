# Oracle Cloud Free par backend live karna

Kul samay: account ke liye ~30 minute (aapka kaam), uske baad setup ~20 minute (script karegi).

## 1. Account banayein (aap)
1. https://www.oracle.com/cloud/free/ → **Start for free**.
2. Country: India. Home region: **India West (Mumbai)** ya **India South (Hyderabad)**.
   Region baad mein badla nahi ja sakta.
3. Email, mobile OTP aur card verification karein. Card se sirf verification hota hai; Always Free mein ₹0 bill aata hai.

## 2. Server banayein (aap)
1. Menu → **Compute → Instances → Create instance**.
2. Name: `micro-bargain`.
3. Image: **Canonical Ubuntu 24.04**.
4. Shape → **Ampere (ARM) → VM.Standard.A1.Flex**: 2 OCPU, 12 GB RAM. Ye "Always Free" ke andar hai.
   Agar "Out of capacity" aaye, to thodi der baad dobara try karein ya **VM.Standard.E2.1.Micro** (AMD) chunein.
5. **Add SSH keys → Generate a key pair** → **Save private key** dabakar file Desktop par save karein.
6. **Create** dabayein. 2–3 minute mein **Public IP address** dikhega. Use note kar lein.

## 3. Ports kholein (aap)
1. Instance page → **Virtual cloud network** link → **Security Lists** → **Default Security List**.
2. **Add Ingress Rules** → Source CIDR `0.0.0.0/0`, IP Protocol TCP, Destination port `80,443` → Save.

## 4. Deploy (Claude / ek command)
PC par WSL mein, project folder se:

```bash
bash deploy/deploy_from_pc.sh <PUBLIC-IP> "/mnt/c/Users/User_PC/Desktop/<private-key-file>.key"
```

Ye script ye sab karegi:
- Docker install karegi
- Ports kholegi
- Naye random passwords banayegi
- Backend, database, Redis, Celery aur HTTPS chalayegi
- Roz ka backup set karegi

Sab ho jaane par ye address dikhega: `https://<ip-with-dashes>.sslip.io`.

## 5. Uske baad
- **Admin login banayein:**
  `ssh -i <key> ubuntu@<ip>`, phir
  `cd /opt/micro_bargain && sudo docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser`
- **Is server ke liye APK:**
  `flutter build apk --release --dart-define=API_BASE_URL=https://<ip-with-dashes>.sslip.io/api/v1`
- **Test mode:** OTP SMS se nahi aata. Use aise dekhein:
  `sudo docker compose -f docker-compose.prod.yml logs -f web | grep "SMS to"`
  Payment bhi "test payment" se hota hai.
- **MSG91 / Razorpay / Firebase approve hone par:**
  1. `backend/.env` mein keys daalein.
  2. `ALLOW_TEST_BACKENDS=False` karein.
  3. `bash deploy/setup_server.sh` dobara chalayein.
