OpenVPN WebPanel clone (auto CCD) - bundle ready to upload

This bundle creates a web panel that can add users, automatically assign a fixed IP from a configured pool,
create the necessary client-config-dir (CCD) file in /etc/openvpn/ccd/<common_name> with ifconfig-push,
and update /etc/openvpn/bandwidth.conf and /etc/openvpn/quota.conf so OpenVPN hook scripts can apply tc and quota.

Usage summary:
1) Upload files to your GitHub repo (or copy files to server).
2) On the OpenVPN server run as root:
   bash <(curl -fsSL https://raw.githubusercontent.com/USERNAME/REPO/main/install.sh)
3) Access panel: http://SERVER_IP:8080 (default admin/admin) - change config.py secrets!
4) Add users in panel: it will assign IP, create CCD file, and update bandwidth/quota mappings.
5) Ensure server.conf has client-connect/disconnect hooked (installer attempts to add them).

Security:
- Change SECRET_KEY and ADMIN_PASS in /opt/openvpn_manager/config.py after install.
- Run panel only on internal network or behind auth & TLS.
