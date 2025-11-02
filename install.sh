#!/bin/bash
set -euo pipefail

# بررسی اینکه root هستیم
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

# مسیر پروژه و repo
PROJECT_DIR="/opt/openvpn_manager"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="openvpn_webpanel"
PORT=8080

echo "[INFO] Installing OpenVPN WebPanel Manager..."

# نصب پیش‌نیازها
apt update
apt install -y python3 python3-venv python3-pip rsync git

# حذف نسخه قبلی
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# کپی فایل‌ها از مسیر اسکریپت
cp -r "$SRC_DIR/"* "$PROJECT_DIR/"

# ساخت virtualenv
python3 -m venv "$PROJECT_DIR/venv"
"$PROJECT_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true

# نصب requirements
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    "$PROJECT_DIR/venv/bin/pip" install -r "$PROJECT_DIR/requirements.txt"
else
    "$PROJECT_DIR/venv/bin/pip" install flask flask_sqlalchemy python-dotenv gunicorn || true
fi

# ایجاد پوشه‌های لازم
mkdir -p /etc/openvpn/scripts
mkdir -p /etc/openvpn/ccd
mkdir -p /etc/openvpn/vpn_configs

# کپی hook scripts
cp -a "$PROJECT_DIR/scripts/"* /etc/openvpn/scripts/
chmod +x /etc/openvpn/scripts/*.sh

# کپی کانفیگ‌های نمونه اگر موجود نبودن
cp -n "$PROJECT_DIR/configs/bandwidth.conf" /etc/openvpn/bandwidth.conf || true
cp -n "$PROJECT_DIR/configs/quota.conf" /etc/openvpn/quota.conf || true
chmod 640 /etc/openvpn/bandwidth.conf /etc/openvpn/quota.conf

# ایجاد systemd service
cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=OpenVPN Web Panel (Flask + gunicorn)
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=${PROJECT_DIR}
Environment="PATH=${PROJECT_DIR}/venv/bin"
ExecStart=${PROJECT_DIR}/venv/bin/gunicorn --bind 0.0.0.0:${PORT} --workers 2 app:app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service

# اجازه دسترسی firewall
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp || true
fi

echo "[SUCCESS] Installation complete!"
echo "Panel running on port ${PORT}."
echo "Visit: http://$(hostname -I | awk '{print $1}'):${PORT} (default admin/admin)"
echo "Edit $PROJECT_DIR/config.py to change secrets and settings."
