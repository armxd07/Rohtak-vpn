#!/usr/bin/env bash
# ============================================================
#  Rohtak VPN - WireGuard Server Setup Script
#  Supported: Ubuntu 20.04 / 22.04 / 24.04 (Debian 11/12 bhi chalega)
#
#  Usage:
#    sudo bash wireguard-server.sh <SERVER_PUBLIC_IP>
#    (IP na do to script khud pooch lega)
#
#  Ye script kya karta hai:
#    1. WireGuard + qrencode install karta hai
#    2. Server + client keys generate karta hai
#    3. /etc/wireguard/wg0.conf banata hai (NAT + IP forwarding ke saath)
#    4. Client config file + QR code banata hai (phone me import ke liye)
#    5. WireGuard service ko enable + start karta hai
#
#  Client ke saare internet traffic is VPS se bahar jayega,
#  isliye phone ka public IP = VPS ka IP hoga (India/Delhi NCR region).
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Rohtak VPN - WireGuard Server Setup      ${NC}"
echo -e "${CYAN}============================================${NC}"

# ---------- 0. Root check ----------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Root ke saath chalao: sudo bash $0${NC}" >&2
    exit 1
fi

# ---------- 1. Server IP ----------
SERVER_PUB_IP="${1:-}"
if [[ -z "$SERVER_PUB_IP" ]]; then
    echo -n "VPS ka public IP daalo (e.g. 103.25.x.x): "
    read -r SERVER_PUB_IP
fi
if [[ -z "$SERVER_PUB_IP" ]]; then
    echo -e "${RED}[ERROR] Public IP required hai.${NC}" >&2
    exit 1
fi

WG_IFACE="wg0"
WG_PORT="51820"
SERVER_VPN_IP="10.66.66.1/24"
CLIENT_VPN_IP="10.66.66.2/32"
CLIENT_NAME="rohtak-client1"
CLIENT_DIR="/root/rohtak-vpn"
WG_DIR="/etc/wireguard"

# ---------- 2. Packages ----------
echo -e "${YELLOW}[*] Packages install ho rahe hain (wireguard, qrencode, iptables)...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard qrencode iptables

# ---------- 3. IP forwarding ----------
echo -e "${YELLOW}[*] IP forwarding enable kar rahe hain...${NC}"
if ! sysctl -n net.ipv4.ip_forward | grep -q '^1$'; then
    sed -i '/^#\?net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
fi

# ---------- 4. Default network interface ----------
NET_IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -z "$NET_IFACE" ]]; then
    echo -e "${RED}[ERROR] Default network interface nahi mila.${NC}" >&2
    exit 1
fi
echo -e "${YELLOW}[*] Default interface: ${NET_IFACE}${NC}"

# ---------- 5. Keys generate ----------
echo -e "${YELLOW}[*] Server + client keys generate ho rahe hain...${NC}"
mkdir -p "$WG_DIR" "$CLIENT_DIR"
cd "$WG_DIR"
umask 077

if [[ ! -f server.key ]]; then
    wg genkey | tee server.key | wg pubkey > server.pub
fi
wg genkey | tee "${CLIENT_NAME}.key" | wg pubkey > "${CLIENT_NAME}.pub"

# ---------- 6. Server config ----------
echo -e "${YELLOW}[*] ${WG_DIR}/${WG_IFACE}.conf likh rahe hain...${NC}"
cat > "${WG_DIR}/${WG_IFACE}.conf" <<EOF
[Interface]
Address = ${SERVER_VPN_IP}
ListenPort = ${WG_PORT}
PrivateKey = $(cat server.key)

PostUp = iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE; iptables -A FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_IFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${NET_IFACE} -j MASQUERADE; iptables -D FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_IFACE} -j ACCEPT

[Peer]
PublicKey = $(cat "${CLIENT_NAME}.pub")
AllowedIPs = 10.66.66.2/32
EOF

# ---------- 7. Client config ----------
echo -e "${YELLOW}[*] Client config likh rahe hain...${NC}"
cat > "${CLIENT_DIR}/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = $(cat "${CLIENT_NAME}.key")
Address = ${CLIENT_VPN_IP}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $(cat server.pub)
Endpoint = ${SERVER_PUB_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "${CLIENT_DIR}/${CLIENT_NAME}.conf"

# ---------- 8. Firewall (ufw) ----------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo -e "${YELLOW}[*] UFW active hai - UDP ${WG_PORT} allow kar rahe hain...${NC}"
    ufw allow "${WG_PORT}/udp"
fi

# ---------- 9. Service start ----------
echo -e "${YELLOW}[*] WireGuard service start kar rahe hain...${NC}"
systemctl enable "wg-quick@${WG_IFACE}" >/dev/null 2>&1
systemctl restart "wg-quick@${WG_IFACE}"
sleep 1

if ! systemctl is-active --quiet "wg-quick@${WG_IFACE}"; then
    echo -e "${RED}[ERROR] WireGuard service start nahi hui. Log check karo:${NC}" >&2
    echo "journalctl -u wg-quick@${WG_IFACE} -n 20" >&2
    exit 1
fi

# ---------- 10. QR code ----------
qrencode -t PNG -o "${CLIENT_DIR}/${CLIENT_NAME}.png" < "${CLIENT_DIR}/${CLIENT_NAME}.conf" 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   SETUP COMPLETE!                          ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Client config file : ${CYAN}${CLIENT_DIR}/${CLIENT_NAME}.conf${NC}"
echo -e "Client QR (PNG)    : ${CYAN}${CLIENT_DIR}/${CLIENT_NAME}.png${NC}"
echo -e "Server status      : ${CYAN}wg show${NC}"
echo ""
echo -e "${YELLOW}Neeche QR code phone se scan karo (Rohtak VPN app me):${NC}"
echo ""
qrencode -t ansiutf8 < "${CLIENT_DIR}/${CLIENT_NAME}.conf"
echo ""
echo -e "${YELLOW}Backup rakhna: ${CLIENT_DIR}/${CLIENT_NAME}.conf${NC}"
echo -e "${YELLOW}Naya device add karne ke liye: sudo bash add-client.sh <naam>${NC}"
echo ""
