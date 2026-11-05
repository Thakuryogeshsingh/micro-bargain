# Render par free demo server (bina card ke)

Kul samay ~20 minute. Pehli build mein 10–15 minute aur lagte hain.

## 1. Code GitHub par daalein (aap, 5 minute)
1. https://github.com par account banayein ya login karein.
2. **New repository** → naam `micro-bargain` → **Private** chunein → *Add README* tick **mat** karein → Create.
3. PC par project folder mein ye chalayein (Git Bash ya VS Code terminal):
   ```bash
   cd "C:/Users/User_PC/Desktop/Local Vendors"
   git remote add origin https://github.com/<aapka-username>/micro-bargain.git
   git push -u origin main
   ```
   Pehli baar browser mein GitHub login ki window khulegi, use allow kar dein.
   `backend/.env` jaise password wali files `.gitignore` ki wajah se nahi jaati.

## 2. Render par deploy (aap, 10 minute)
1. https://render.com → **Get Started** → **GitHub se sign up** karein. Card nahi lagta.
2. Dashboard → **New +** → **Blueprint** → apni `micro-bargain` repository chunein (GitHub access allow karein).
3. Render `render.yaml` padh kar teen cheezein banayega:
   - web server
   - PostGIS database
   - Redis
4. `DJANGO_SUPERUSER_PHONE` maangega. Apna 10 ankon ka mobile number daalein. Ye admin login hoga.
5. **Apply** dabayein. Pehli build mein 10–15 minute lagenge.
6. Build ho jaane par **micro-bargain-api** service ke upar URL dikhega, jaise `https://micro-bargain-api.onrender.com`.
   **Ye URL mujhe bhej dein.**

## 3. Uske baad (Claude)
- Is URL ke saath naya APK banega.
- **Admin:** `https://<url>/admin/` par login karein.
  - Phone: wahi number jo upar daala tha.
  - Password: Render → micro-bargain-api → **Environment** → `DJANGO_SUPERUSER_PASSWORD`.
  - Yahin se dukaanon ko approve karna hai.
- **OTP:** test mode mein SMS nahi jaata. Render → micro-bargain-api → **Logs** mein `SMS to 98xxxxxxxx: 123456` dikhega.

## Free plan ki seemayein
- 15 minute koi use na kare to server so jaata hai. Pehli request mein ~1 minute lagta hai, app itni der wait karti hai.
- Free database lagbhag **30 din** baad expire hota hai. Render pehle email karta hai. Asli pilot se pehle sasta VPS ya paid plan lein.
- Har redeploy ya restart par **upload ki gayi photos chali jaati hain**. Demo ke liye theek hai.
- Code badalne par sirf `git push` karein, Render apne aap naya version chala dega.
