<!DOCTYPE html>
<html lang="fa">
<head>
<meta charset="UTF-8">
#آموزش گرفتن گواهی SSL برای پاسارگارد#
</head>
<body dir="rtl">

<h1>🚀 آموزش گرفتن گواهی SSL برای پاسارگارد</h1>

<p>سلام! 👋</p>
<p>این آموزش به شما کمک می‌کند تا به سادگی <strong>گواهی SSL</strong> برای دامنه‌های خود دریافت کرده و آن‌ها را در <strong>پاسارگارد</strong> ذخیره کنید. با این روش، اتصال سرور شما امن و معتبر خواهد بود و نیاز به انجام مراحل پیچیده دستی نخواهید داشت.</p>
<p>این آموزش مخصوص افرادی است که می‌خواهند با <strong>یک اسکریپت آماده</strong>، گواهی SSL دریافت کرده و روی سرور Pasarguard نصب کنند.</p>

<hr>

<h2>📝 مرحله ۱: ساخت فایل اسکریپت</h2>
<p>یک فایل اسکریپت با نام <code>get_cert.sh</code> بسازید:</p>
<pre><code>nano get_cert.sh</code></pre>

<hr>

<h2>📝 مرحله ۲: محتویات اسکریپت</h2>
<p>محتویات زیر را داخل فایل <code>get_cert.sh</code> پیست کنید.</p>
<blockquote>
<p><strong>توجه:</strong> قبل از ذخیره، در خط پنجم <code>YOURDOMAIN.COM</code> را با دامنه واقعی خود جایگزین کنید.</p>
</blockquote>

<pre><code>#!/bin/bash

# ====== Tanzimat ======
DOMAIN="YOURDOMAIN.COM"
DEST_DIR="/var/lib/pasarguard/certs/$DOMAIN"

# ====== Barrasi va Nasb Certbot ======
if ! command -v certbot > /dev/null; then
    echo "[INFO] Certbot nasb nist, dar hal nasb..."
    sudo apt update
    sudo apt install snapd -y
    sudo snap install core; sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
else
    echo "[INFO] Certbot nasb ast."
fi

# ====== Sakht Masir Nahayi ======
sudo mkdir -p "$DEST_DIR"

# ====== Gereftan Gavahi SSL ======
echo "[INFO] dar hal gereftan gavahi SSL baraye $DOMAIN ..."
sudo certbot certonly \
  --standalone \
  --agree-tos \
  --register-unsafely-without-email \
  -d "$DOMAIN" \
  --cert-path "$DEST_DIR/cert.pem" \
  --key-path "$DEST_DIR/privkey.pem" \
  --fullchain-path "$DEST_DIR/fullchain.pem" \
  --chain-path "$DEST_DIR/chain.pem" \
  --preferred-challenges http \
  --non-interactive

echo "[INFO] amaliat tamam shod. fayl-haye gavahi dar masir $DEST_DIR gharar darand."
</code></pre>

<hr>

<h2>⚙️ مرحله ۳: دادن دسترسی اجرایی به اسکریپت</h2>
<pre><code>chmod +x get_cert.sh</code></pre>

<hr>

<h2>🚀 مرحله ۴: اجرای اسکریپت برای گرفتن گواهی SSL</h2>
<pre><code>sudo ./get_cert.sh</code></pre>

<hr>

<h2>💡 نکته مهم: انتقال دستی گواهی</h2>
<p>اگر از قبل گواهی SSL گرفته‌اید و فقط می‌خواهید آن را به مسیر Pasarguard منتقل کنید:</p>

<pre><code>sudo mkdir -p /var/lib/pasarguard/certs/YOURDOMAIN.COM
sudo cp /etc/letsencrypt/live/YOURDOMAIN.COM/fullchain.pem /var/lib/pasarguard/certs/YOURDOMAIN.COM/
sudo cp /etc/letsencrypt/live/YOURDOMAIN.COM/privkey.pem /var/lib/pasarguard/certs/YOURDOMAIN.COM/</code></pre>

<hr>

<h2>📌 آدرس فایل‌های گواهی در Pasarguard</h2>
<p>پس از دریافت یا انتقال گواهی، فایل‌ها در مسیر زیر قرار دارند:</p>
<pre><code>⭐ Private key: /var/lib/pasarguard/certs/YOURDOMAIN.COM/privkey.pem
⭐ Full chain: /var/lib/pasarguard/certs/YOURDOMAIN.COM/fullchain.pem</code></pre>


</body>
</html>
