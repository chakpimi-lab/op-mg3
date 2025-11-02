#!/bin/bash
# client-connect hook: set per-client tc class and iptables quota (same as earlier)
set -euo pipefail
IFACE="tun0"
CONF_DB="/etc/openvpn/bandwidth.conf"
QUOTA_DB="/etc/openvpn/quota.conf"
LOG_TAG="openvpn-quota"
CN="${common_name:-unknown}"
IP="${ifconfig_pool_remote_ip:-}"
DEFAULT_RATE_KBIT=1024
DEFAULT_QUOTA_BYTES=0
get_rate_kbit() { if [ -f "$CONF_DB" ]; then awk -v cn="$CN" '$1==cn{print $2; exit}' "$CONF_DB"; fi }
get_quota_bytes() { if [ -f "$QUOTA_DB" ]; then awk -v cn="$CN" '$1==cn{print $2; exit}' "$QUOTA_DB"; fi }
if [ -z "$IP" ]; then logger -t $LOG_TAG "No IP for $CN, skipping"; exit 0; fi
RATE_KBIT=$(get_rate_kbit); if [ -z "$RATE_KBIT" ]; then RATE_KBIT=$DEFAULT_RATE_KBIT; fi
QUOTA_BYTES=$(get_quota_bytes); if [ -z "$QUOTA_BYTES" ]; then QUOTA_BYTES=$DEFAULT_QUOTA_BYTES; fi
if ! tc qdisc show dev "$IFACE" | grep -q "htb"; then tc qdisc add dev "$IFACE" root handle 1: htb default 999; fi
LAST_OCTET=$(echo "$IP" | awk -F. '{print $4}'); if ! [[ "$LAST_OCTET" =~ ^[0-9]+$ ]]; then LAST_OCTET=$(( (RANDOM % 250) + 1 )); fi
CLASSID="1:${LAST_OCTET}"
tc class add dev "$IFACE" parent 1: classid ${CLASSID} htb rate ${RATE_KBIT}kbit ceil ${RATE_KBIT}kbit 2>/dev/null || true
tc filter add dev "$IFACE" protocol ip parent 1: prio 1 u32 match ip src ${IP}/32 flowid ${CLASSID} 2>/dev/null || true
tc filter add dev "$IFACE" protocol ip parent 1: prio 2 u32 match ip dst ${IP}/32 flowid ${CLASSID} 2>/dev/null || true
QUOTA_CHAIN="OPENVPN_QUOTA"; if ! iptables -nL "$QUOTA_CHAIN" >/dev/null 2>&1; then iptables -N "$QUOTA_CHAIN" || true; fi
iptables -C FORWARD -j "$QUOTA_CHAIN" >/dev/null 2>&1 || iptables -I FORWARD 1 -j "$QUOTA_CHAIN"
if [ "$QUOTA_BYTES" -gt 0 ]; then iptables -A "$QUOTA_CHAIN" -s ${IP}/32 -m quota --quota ${QUOTA_BYTES} -j RETURN 2>/dev/null || true; iptables -A "$QUOTA_CHAIN" -s ${IP}/32 -j DROP 2>/dev/null || true; logger -t $LOG_TAG "Applied quota ${QUOTA_BYTES} bytes for ${CN} (${IP}) and rate ${RATE_KBIT}kbit"; else logger -t $LOG_TAG "Applied rate ${RATE_KBIT}kbit for ${CN} (${IP}), no quota"; fi
exit 0
