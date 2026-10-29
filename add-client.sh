#!/usr/bin/env bash
# ============================================================
#  Rohtak VPN - Naya Client Add Karne Ka Script
#
#  Usage:
#    sudo bash add-client.sh <client-naam>
#    (e.g. sudo bash add-client.sh client2)
#
#  Pehle wireguard-server.sh chala chuke hone chahiye.
#  Ye script:
#    1. Naye keys generate karta hai
#    2. Server ke wg0.conf me naya [Peer] add karta hai
#    3. WireGuard ko bina restart ke sync karta hai
#    4. Naya client config + QR code banata hai
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Root ke saath chalao: sudo bash $0${NC}" >&2
    exit 1
fi

CLIENT_NAME="${1:-}"
if [[ -z "$CLIENT_NAME" ]]; then
    echo -n "Client ka naam daalo (e.g. client2 / mera-phone): "
    read -r CLIENT_NAME
fi
if [[ -z "$CLIENT_NAME" ]]; then
    echo -e "${RED}[ERROR] Client naam required hai.${NC}" >&2
    exit 1
fi
# Config parse safe naam (sirf alphanumeric, dash, underscore)
CLIENT_NAME=$(echo "$CLIENT_NAME" | tr -cd '[:alnum:]_-')

WG_IFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENT_DIR="/root/rohtak-vpn"
WG_CONF="${WG_DIR}/${WG_IFACE}.conf"
SERVER_CONF_FILE="${WG_DIR}/${WG_IFACE}.conf"

# ---------- Checks ----------
if [[ ! -f "$WG_CONF" ]]; then
    echo -e "${RED}[ERROR] ${WG_CONF} nahi mila. Pehle wireguard-server.sh chalao.${NC}" >&2
    exit 1
fi
if [[ ! -f "${WG_DIR}/server.pub" ]]; then
    echo -e "${RED}[ERROR] ${WG_DIR}/server.pub nahi mila. Pehle wireguard-server.sh chalao.${NC}" >&2
    exit 1
fi

# Endpoint purane client conf se utha lo
OLD_CONF=$(ls -t "${CLIENT_DIR}"/*.conf 2>/dev/null | head -n 1 || true)
if [[ -n "$OLD_CONF" ]]; then
    ENDPOINT=$(grep -m1 'Endpoint' "$OLD_CONF" | awk '{print $3}')
else
    echo -n "VPS ka public IP:port daalo (e.g. 103.x.x.x:51820): "
    read -r ENDPOINT
fi
if [[ -z "${ENDPOINT:-}" ]]; then
    echo -e "${RED}[ERROR] Endpoint nahi mila.${NC}" >&2
    exit 1
fi

# ---------- Next free IP ----------
USED_IPS=$(grep -oE '10\.66\.66\.[0-9]+' "$WG_CONF" | sort -u | awk -F. '{print $4}' | sort -n)
NEXT_IP=2
for ip in $USED_IPS; do
    if [[ "$ip" -eq "$NEXT_IP" ]]; then
        NEXT_IP=$((NEXT_IP + 1))
    fi
done
if [[ "$NEXT_IP" -gt 254 ]]; then
    echo -e "${RED}[ERROR] IP space full ho gaya (max 253 clients).${NC}" >&2
    exit 1
fi
CLIENT_VPN_IP="10.66.66.${NEXT_IP}/32"

# ---------- Keys ----------
cd "$WG_DIR"
umask 077
wg genkey | tee "${CLIENT_NAME}.key" | wg pubkey > "${CLIENT_NAME}.pub"

# ---------- Server conf me peer add ----------
echo -e "${YELLOW}[*] Server conf me naya peer add kar rahe hain (IP: ${CLIENT_VPN_IP})...${NC}"
cat >> "$WG_CONF" <<EOF

[Peer]
PublicKey = $(cat "${CLIENT_NAME}.pub")
AllowedIPs = ${CLIENT_VPN_IP}
EOF

# Bina restart ke live sync
wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")

# ---------- Client conf ----------
mkdir -p "$CLIENT_DIR"
cat > "${CLIENT_DIR}/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = $(cat "${CLIENT_NAME}.key")
Address = ${CLIENT_VPN_IP}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $(cat "${WG_DIR}/server.pub")
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "${CLIENT_DIR}/${CLIENT_NAME}.conf"

qrencode -t PNG -o "${CLIENT_DIR}/${CLIENT_NAME}.png" < "${CLIENT_DIR}/${CLIENT_NAME}.conf" 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   CLIENT READY: ${CLIENT_NAME} (10.66.66.${NEXT_IP})   ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Config file : ${CYAN}${CLIENT_DIR}/${CLIENT_NAME}.conf${NC}"
echo -e "QR (PNG)    : ${CYAN}${CLIENT_DIR}/${CLIENT_NAME}.png${NC}"
echo ""
echo -e "${YELLOW}QR code scan karo Rohtak VPN app me:${NC}"
echo ""
qrencode -t ansiutf8 < "${CLIENT_DIR}/${CLIENT_NAME}.conf"
echo ""
