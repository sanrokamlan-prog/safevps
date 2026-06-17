#!/usr/bin/env bash
# Harden a Ubuntu/Debian server with UFW mail egress blocks and Fail2Ban SSH protection.
# Usage:
#   sudo bash setup_server_security.sh
# Optional environment variables:
#   SSH_PORT=22              SSH port to protect/allow/limit
#   UDP_RANGE=10000:10010    UDP port range to allow
#   ASSUME_YES=1             Skip interactive confirmation

set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
UDP_RANGE="${UDP_RANGE:-10000:10010}"
ASSUME_YES="${ASSUME_YES:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Please run as root, for example: sudo bash $0" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: This script currently supports Debian/Ubuntu systems with apt-get." >&2
  exit 1
fi

# Best-effort detection of the current SSH client's IP so Fail2Ban will not ban you.
MYIP=""
if [[ -n "${SSH_CLIENT:-}" ]]; then
  MYIP="${SSH_CLIENT%% *}"
elif [[ -n "${SSH_CONNECTION:-}" ]]; then
  MYIP="${SSH_CONNECTION%% *}"
fi

if [[ -z "${MYIP}" ]]; then
  echo "WARNING: Could not detect your SSH client IP. Fail2Ban ignoreip will include only localhost." >&2
fi

cat <<INFO
This script will:
  - Install/ensure ufw and fail2ban are present
  - Rate-limit inbound SSH on TCP port ${SSH_PORT}
  - Reject outbound mail ports: TCP 25, 465, 587
  - Allow UDP ${UDP_RANGE}
  - Enable UFW
  - Configure Fail2Ban sshd jail with permanent bans after 3 failures in 60 seconds
  - Add your current SSH client IP to ignoreip: ${MYIP:-not detected}
INFO

if [[ "${ASSUME_YES}" != "1" ]]; then
  read -r -p "Continue? Type YES to proceed: " CONFIRM
  if [[ "${CONFIRM}" != "YES" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "==> Updating package lists and installing dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw fail2ban

echo "==> Configuring UFW..."
# Make sure SSH remains reachable before enabling the firewall.
ufw allow "${SSH_PORT}/tcp"
ufw limit "${SSH_PORT}/tcp"

# Block outbound mail ports to prevent this server from sending mail directly.
ufw reject out 25/tcp
ufw reject out 465/tcp
ufw reject out 587/tcp

# Allow UDP range requested by the user.
ufw allow "${UDP_RANGE}/udp"

# Enable/reload firewall non-interactively.
ufw --force enable
ufw reload

echo "==> UFW status:"
ufw status verbose

echo "==> Configuring Fail2Ban..."
IGNORE_IPS="127.0.0.1/8 ::1"
if [[ -n "${MYIP}" ]]; then
  IGNORE_IPS="${IGNORE_IPS} ${MYIP}"
fi

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = ${IGNORE_IPS}
bantime = -1
findtime = 60
maxretry = 3

[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

sleep 3

echo "==> Fail2Ban status:"
fail2ban-client status
fail2ban-client status sshd

echo "==> Done."
