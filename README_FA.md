![SRV Helper - Server Control Center](assets/srv-helper-banner.png)

# SRV Helper | نسخه 1.0.0

**توسعه‌دهنده: AmirTN9**  
مرکز مدیریت SSL، DNS، میرور، Paqet و ابزارهای نگهداری VPS با رابط تعاملی فینگلیش.

- GitHub: https://github.com/AmirTN9/srvhelper
- دستور اجرا: `sudo srv-helper`
- زبان تمام پیام‌های محیط ترمینال: فینگلیش و ASCII
- سیستم‌عامل‌های هدف: Ubuntu و Debian مبتنی بر systemd

## امکانات اصلی

### 1. مدیریت SSL

- حالت دستی برای یک دامنه.
- حالت SAN برای گرفتن یک گواهی مشترک برای ۲ تا ۲۵ دامنه.
- حالت Batch برای گرفتن گواهی مستقل و پشت‌سرهم برای حداکثر ۵۰ دامنه.
- اعتبارسنجی HTTP-01 به روش Standalone یا Webroot.
- انتخاب مسیر بعد از صدور: مسیر پیش‌فرض پاسارگارد، مسیر Root یا مسیر دلخواه.
- ساخت پوشه جدا برای هر گواهی، مدیریت دسترسی کلید خصوصی، تمدید خودکار Certbot و Deploy Hook.

### 2. هوشمندسازی خودکار سرور

این بخش کشور سرور را از طریق IP عمومی تشخیص می‌دهد و امکان انتخاب دستی منطقه را نیز دارد؛ سپس:

1. DNSهای ایرانی، اپراتورها، زیرساخت/TIC و DNSهای بین‌المللی را بررسی می‌کند.
2. DNSها را با چند دامنه آزمایش کرده و بر اساس تعداد پاسخ موفق و زمان پاسخ مرتب می‌کند.
3. میرورهای منطقه‌ای Ubuntu/Debian را با بررسی فایل Release و زمان پاسخ مقایسه می‌کند.
4. میرور منتخب را با Backup اعمال می‌کند و در صورت شکست `apt-get update` تنظیم قبلی را برمی‌گرداند.
5. اگر کرنل فعلی BBR را پشتیبانی کند، آن را فعال می‌کند.
6. در پایان گزارش فینگلیش از کارهای انجام‌شده، ناموفق یا ردشده نمایش می‌دهد.

این عملیات فقط `apt-get update` اجرا می‌کند و به‌صورت خودکار `apt-get upgrade` یا نصب کرنل جدید انجام نمی‌دهد. تشخیص منطقه با سرویس `ipinfo.io` انجام می‌شود و در صورت خطا می‌توان منطقه را دستی انتخاب کرد.

### 3. DNS Finder و DNS Manager

- DNSهای ایرانی: شکن، رادار، 403، الکترو، بگذر، شاتل، شلتر، بشکن، پیشگامان، آسیاتک، هاست ایران و زیرساخت/TIC مخابرات.
- DNSهای خارجی: Cloudflare، Google، Quad9، OpenDNS، AdGuard، ControlD و Yandex.
- قبل از پیشنهاد DNS برای اعمال، هر آدرس به‌صورت واقعی تست می‌شود.
- تنظیم DNS فقط از طریق `systemd-resolved` انجام می‌شود و Backup/Restore دارد.
- DNSهای Private مانند رادار و 403 ممکن است فقط داخل شبکه بعضی اپراتورها یا دیتاسنترهای ایران قابل استفاده باشند.

### 4. مدیریت Mirror

- دسته‌بندی ایران، اروپا و آمریکا.
- پشتیبانی از ساختارهای APT در Ubuntu و Debian.
- تست فایل Release هر توزیع و مرتب‌سازی بر اساس زمان پاسخ.
- عدم تغییر مخازن امنیتی و مخازن شخص ثالث.
- Backup خودکار و Rollback در صورت شکست آپدیت فهرست بسته‌ها.

رتبه‌بندی بر اساس در دسترس بودن Release و زمان پاسخ است؛ این آزمایش معادل تست سرعت دانلود طولانی‌مدت نیست و وضعیت هر میرور در زمان اجرا بررسی می‌شود.

### 5. اتصال به Paqet Manager بهزاد

- دریافت نسخه رسمی `Paqet-Tunnel-Manager` از مخزن بهزاد.
- نمایش SHA256 فایل دانلودشده و درخواست تأیید جداگانه قبل از اجرا.
- داشبورد مدیریت سرویس‌های نصب‌شده Paqet: وضعیت، Start، Stop، Restart و Log. برای DNS Finder داخل منیجر رسمی، گزینه ۷ و سپس زیرگزینه ۲ را انتخاب کنید. رابط خود منیجر رسمی مستقل است و متن‌های آن تحت کنترل پروژه اصلی باقی می‌ماند.
- DNS Finder و Mirror Finder داخلی SRV Helper نیز مستقل از اسکریپت اصلی Paqet قابل استفاده‌اند.

### 6. قابلیت‌های SysHelper و NetOptix

- داشبورد سیستم: CPU، RAM، Disk، Uptime، Load، پورت‌ها، Route و وضعیت شبکه.
- مدیریت IPv6 و Ping با تنظیمات پایدار و امکان Reset.
- مدیریت TCP Congestion: BBR، Hybla در صورت پشتیبانی کرنل و Cubic.
- ساخت، مشاهده و حذف Swap اختصاصی SRV Helper.
- ساخت ZRAM پایدار با سرویس systemd.
- Path MTU Finder به‌صورت Read-only و بدون تغییر خودکار MTU کارت شبکه.
- نصب و مدیریت Fail2ban برای SSH.
- نصب ClamAV و اسکن فقط گزارشی؛ فایل آلوده به‌صورت خودکار حذف نمی‌شود.
- نصب اختیاری Cockpit بدون باز کردن خودکار پورت 9090 در فایروال.
- افزودن پورت دوم SSH با حفظ پورت قبلی تا زمان تست اتصال جدید.

## آموزش دانلود، استخراج و نصب

### روش اول: دانلود مستقیم ZIP از GitHub

```bash
sudo apt update
sudo apt install -y curl wget unzip ca-certificates
wget -O srvhelper-main.zip https://github.com/Amirtn9/srvhelper/archive/refs/heads/main.zip
unzip srvhelper-main.zip
cd srvhelper-main
sudo bash install.sh
sudo srv-helper
```

### روش دوم: کلون با Git

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Amirtn9/srvhelper.git
cd srvhelper
sudo bash install.sh
sudo srv-helper
```

### روش سوم: انتقال دستی فایل ZIP به سرور

فایل `SRV-Helper-v1.0.0.zip` را با SCP، SFTP یا فایل‌منیجر هاست به VPS منتقل کنید و سپس:

```bash
sudo apt update
sudo apt install -y unzip
unzip SRV-Helper-v1.0.0.zip
cd SRV-Helper
sudo bash install.sh
sudo srv-helper
```

نصب‌کننده برنامه را در مسیر `/opt/srv-helper` قرار می‌دهد و دستور `srv-helper` را در `/usr/local/bin` می‌سازد.

### اجرای مستقیم بدون نصب

```bash
sudo bash srv-helper.sh
```

## راهنمای منو

- برای برگشت از هر مرحله، عبارت `back` را وارد کنید.
- برای خروج از برنامه، عبارت `exit` را وارد کنید.
- تمام پیام‌های تعاملی به فینگلیش نوشته شده‌اند.

## نکات ایمنی مهم

- قبل از استفاده روی سرور اصلی، ابتدا روی VPS آزمایشی تست کنید.
- تغییر DNS فقط زمانی انجام می‌شود که `systemd-resolved` فعال باشد؛ فایل `/etc/resolv.conf` مستقیماً بازنویسی نمی‌شود.
- DNSهای Private ایران ممکن است خارج از شبکه مربوطه پاسخ ندهند؛ DNS Finder فقط آدرس‌های پاسخ‌گو را پیشنهاد می‌کند.
- تغییر Mirror با Backup انجام می‌شود و مخازن امنیتی دست‌نخورده باقی می‌مانند.
- فعال‌سازی BBR یا Hybla به پشتیبانی کرنل بستگی دارد و SRV Helper کرنل جدید نصب نمی‌کند.
- قابلیت SSH Port فقط یک پورت دوم اضافه می‌کند و پورت قبلی را باز نگه می‌دارد. ابتدا با پورت جدید اتصال بگیرید و بعداً پورت قبلی را دستی حذف کنید.
- اسکریپت رسمی Paqet و نصب‌کننده‌های خارجی کد شخص ثالث هستند؛ قبل از اجرا با دسترسی Root، سورس را بررسی کنید. SHA256 فقط هویت فایل دانلودشده را مشخص می‌کند و امضای ناشر نیست.
- ابزارهای بلاک گسترده ISP، رنج خصوصی، تورنت و سایت‌های SpeedTest و نصب MikroTik از آرشیو NetOptix به‌صورت خودکار منتقل نشده‌اند؛ این عملیات می‌توانند SSH، Docker، Route داخلی یا ترافیک سرور را قطع کنند. اجرای آن‌ها نیازمند بررسی قوانین و مسیر بازیابی خارج از باند است.
- ClamAV فقط گزارش می‌دهد و فایلی را خودکار حذف نمی‌کند.
- نصب Cockpit به‌صورت خودکار پورت 9090 را در فایروال باز نمی‌کند.

## تست‌ها

```bash
bash tests/test.sh
bash srv-helper.sh --version
```

تست‌های داخل پروژه آفلاین و ایستا هستند. صدور واقعی گواهی، تغییر DNS/Mirror، نصب پکیج‌ها، تغییر فایروال و اجرای تونل Paqet باید روی VPS آزمایشی بررسی شوند.

## منابع و قدردانی

- [Pasarguard SSL Helper](https://github.com/Amirtn9/Pasarguard-SSL-Helper) — مسیر و روند اولیه SSL.
- [SysHelper](https://github.com/MeXenon/syshelper) — ایده داشبورد سیستم و مدیریت شبکه؛ لایسنس MIT در `docs/UPSTREAM-SYSHELPER-LICENSE` نگهداری شده است.
- [NetOptix](https://github.com/MrAminiDev/NetOptix) — ایده قابلیت‌های BBR، Hybla، Swap، ZRAM، MTU، Fail2ban، ClamAV و نگهداری شبکه. کد NetOptix در این نسخه کپی نشده و فایل ZIP ارسالی شامل فایل License نبود.
- [Paqet Tunnel Manager](https://github.com/behzadea12/Paqet-Tunnel-Manager) — منیجر رسمی Paqet و مرجع روند DNS/Mirror.
- [IranDNSFinder](https://github.com/alinezamifar/IranDNSFinder) — مرجع DNSهای ایرانی و ایده تست Resolver.
- [DetectUbuntuMirror](https://github.com/alinezamifar/DetectUbuntuMirror) — مرجع انتخاب میرور منطقه‌ای.
- [Certbot](https://certbot.eff.org/) — صدور و تمدید گواهی ACME.

## License

این پروژه تحت مجوز MIT منتشر می‌شود. فایل [`LICENSE`](LICENSE) را ببینید.
