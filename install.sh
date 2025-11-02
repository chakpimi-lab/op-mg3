#!/bin/bash
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run as root"; exit 1; fi

PROJECT_DIR="/opt/openvpn_manager"
SRC_DIR="$(pwd)"
INSTALL_SCRIPTS_DIR="/etc/openvpn/scripts"
CCD_DIR="/etc/openvpn/ccd"
BANDWIDTH_CONF="/etc/openvpn/bandwidth.conf"
QUOTA_CONF="/etc/openvpn/quota.conf"
SERVICE_NAME="openvpn_webpanel"
PORT=8080

echo "[INFO] Installing to $PROJECT_DIR"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cp -r "$SRC_DIR/"* "$PROJECT_DIR/"
python3 -m venv "$PROJECT_DIR/venv" || true
"$PROJECT_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
  "$PROJECT_DIR/venv/bin/pip" install -r "$PROJECT_DIR/requirements.txt"
else
  "$PROJECT_DIR/venv/bin/pip" install flask flask_sqlalchemy python-dotenv gunicorn || true
fi

# create systemd service
cat >/etc/systemd/system/${SERVICE_NAME}.service <<'UNIT'
[Unit]
Description=OpenVPN Web Panel (auto CCD)
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/openvpn_manager
Environment="PATH=/opt/openvpn_manager/venv/bin"
ExecStart=/opt/openvpn_manager/venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 app:app
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service || true

# copy hook scripts
mkdir -p "$INSTALL_SCRIPTS_DIR"
cp -a "$PROJECT_DIR/scripts/"* "$INSTALL_SCRIPTS_DIR/" 2>/dev/null || true
chmod +x "$INSTALL_SCRIPTS_DIR/"*.sh 2>/dev/null || true

# ensure ccd dir exists
mkdir -p "$CCD_DIR"
chmod 750 "$CCD_DIR"

# ensure sample confs exist if not present
if [ ! -f "$BANDWIDTH_CONF" ]; then cp "$PROJECT_DIR/configs/bandwidth.conf" "$BANDWIDTH_CONF"; fi
if [ ! -f "$QUOTA_CONF" ]; then cp "$PROJECT_DIR/configs/quota.conf" "$QUOTA_CONF"; fi
chmod 640 "$BANDWIDTH_CONF" "$QUOTA_CONF" || true

# attempt to add hook lines to server.conf variants
SERVER_CONFS=(/etc/openvpn/server.conf /etc/openvpn/server/server.conf /etc/openvpn/openvpn.conf)
for sc in "${SERVER_CONFS[@]}"; do
  if [ -f "$sc" ]; then
    grep -q "^script-security" "$sc" || echo "script-security 3" >> "$sc"
    grep -q "tc-client-connect.sh" "$sc" || echo "client-connect /etc/openvpn/scripts/tc-client-connect.sh" >> "$sc"
    grep -q "tc-client-disconnect.sh" "$sc" || echo "client-disconnect /etc/openvpn/scripts/tc-client-disconnect.sh" >> "$sc"
    grep -q "^client-config-dir" "$sc" || echo "client-config-dir /etc/openvpn/ccd" >> "$sc"
    echo "[INFO] Updated $sc with hook lines"
    # restart openvpn service(s)
    systemctl restart openvpn@server || true
    systemctl restart openvpn || true
    break
  fi
done

echo "[SUCCESS] Installation complete. Panel running on port ${PORT}."
echo "Visit: http://$(hostname -I | awk '{print $1}'):${PORT} (default admin/admin)"
echo "Edit /opt/openvpn_manager/config.py to change secrets and settings."
