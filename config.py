# Configuration for OpenVPN WebPanel (auto CCD)
SECRET_KEY = 'change_this_secret_now'
ADMIN_USER = 'admin'
ADMIN_PASS = 'admin'
# OpenVPN details for generated .ovpn template (not used for hook operations)
OVPN_SERVER_ADDRESS = 'your.openvpn.server'
# CCD / IP pool configuration: base network and starting last octet
# Example: if your OpenVPN network is 10.8.0.0/24 and server uses .1, start at .2
CCD_NETWORK_PREFIX = '10.8.0.'
CCD_START_OCTET = 2
CCD_END_OCTET = 250
# Interface where tc should be applied (tun0 or tun1)
TC_IFACE = 'tun0'
