#!/bin/bash
set -euo pipefail
IFACE="tun0"
LOG_TAG="openvpn-quota"
CN="${common_name:-unknown}"
IP="${ifconfig_pool_remote_ip:-}"
LAST_OCTET=$(echo "$IP" | awk -F. '{print $4}'); CLASSID="1:${LAST_OCTET}"
tc filter del dev "$IFACE" protocol ip parent 1: prio 1 u32 match ip src ${IP}/32 2>/dev/null || true
tc filter del dev "$IFACE" protocol ip parent 1: prio 2 u32 match ip dst ${IP}/32 2>/dev/null || true
tc class del dev "$IFACE" parent 1: classid ${CLASSID} 2>/dev/null || true
QUOTA_CHAIN="OPENVPN_QUOTA"
if iptables -nL "$QUOTA_CHAIN" >/dev/null 2>&1; then iptables -S "$QUOTA_CHAIN" | grep " -s ${IP}/32" | while read -r line; do rule="${line/-A/-D}"; iptables $rule || true; done; fi
logger -t $LOG_TAG "Removed limits for ${CN} (${IP})"
exit 0
