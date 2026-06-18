#!/usr/bin/env bash
# Common Ubuntu/Debian server firewall + Fail2Ban setup.
#
# Usage:
#   sudo bash setup_server_security.sh
#
# Optional environment variables:
#   SSH_PORT=22                         SSH port to keep open and rate-limit
#   TCP_PORTS="80 443"                  Extra inbound TCP ports to allow
#   UDP_PORTS="10000:10010"             Extra inbound UDP ports/ranges to allow
#   BLOCK_MAIL_OUT=1                    Block outbound mail ports 25/465/587
#   RESET_UFW=0                         Set to 1 to reset existing UFW rules first
#   ASSUME_YES=1                        Skip interactive confirmation
#
# Examples:
#   sudo bash setup_server_security.sh
#   sudo TCP_PORTS="80 443 8096 8920" bash setup_server_security.sh
#   sudo SSH_PORT=2222 UDP_PORTS="10000:10010 51820" bash setup_server_security.sh
#   sudo RESET_UFW=1 ASSUME_YES=1 bash setup_server_security.sh

set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
TCP_PORTS="${TCP_PORTS:-80 443}"
UDP_PORTS="${UDP_PORTS:-10000:10010}"
BLOCK_MAIL_OUT="${BLOCK_MAIL_OUT:-1}"
RESET_UFW="${RESET_UFW:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "错误：请用 root 执行，例如：sudo bash $0" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "错误：这个脚本适用于 Debian/Ubuntu 系统。" >&2
  exit 1
fi

# 尽量获取当前 SSH 登录 IP，避免 Fail2Ban 把自己封掉。
MYIP=""
if [[ -n "${SSH_CLIENT:-}" ]]; then
  MYIP="${SSH_CLIENT%% *}"
elif [[ -n "${SSH_CONNECTION:-}" ]]; then
  MYIP="${SSH_CONNECTION%% *}"
fi

if [[ -z "${MYIP}" ]]; then
  echo "警告：没有检测到当前 SSH 客户端 IP，Fail2Ban 白名单只会加入本机地址。" >&2
fi

cat <<INFO
即将执行以下配置：
  - 安装/更新 ufw 和 fail2ban
  - UFW 默认策略：拒绝入站，允许出站
  - 放行并限速 SSH TCP ${SSH_PORT}
  - 放行常规 TCP 端口：${TCP_PORTS}
  - 放行 UDP 端口/范围：${UDP_PORTS}
  - 封禁出站邮件端口 TCP 25/465/587：${BLOCK_MAIL_OUT}
  - 重置现有 UFW 规则：${RESET_UFW}
  - 启用 UFW
  - 配置 Fail2Ban sshd：60 秒内失败 3 次永久封禁
  - Fail2Ban 白名单 IP：127.0.0.1/8 ::1 ${MYIP:-未检测到}
INFO

if [[ "${ASSUME_YES}" != "1" ]]; then
  read -r -p "确认继续请输入 YES：" CONFIRM
  if [[ "${CONFIRM}" != "YES" ]]; then
    echo "已取消。"
    exit 0
  fi
fi

echo "==> 更新软件源并安装依赖..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw fail2ban

echo "==> 配置 UFW..."

if [[ "${RESET_UFW}" == "1" ]]; then
  ufw --force reset
fi

# 常规服务器策略：默认拒绝入站，默认允许出站。
ufw default deny incoming
ufw default allow outgoing

# 先放行 SSH，再启用防火墙，避免远程服务器失联。
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw limit "${SSH_PORT}/tcp" comment "SSH rate limit"

# 放行常用 TCP 服务，例如 80/443。可通过 TCP_PORTS 环境变量追加或覆盖。
for PORT in ${TCP_PORTS}; do
  if [[ -n "${PORT}" ]]; then
    ufw allow "${PORT}/tcp"
  fi
done

# 放行 UDP 服务，例如 10000:10010。可通过 UDP_PORTS 环境变量追加或覆盖。
for PORT in ${UDP_PORTS}; do
  if [[ -n "${PORT}" ]]; then
    ufw allow "${PORT}/udp"
  fi
done

# 禁止服务器直连发信，防止被滥用为垃圾邮件源。
if [[ "${BLOCK_MAIL_OUT}" == "1" ]]; then
  ufw reject out 25/tcp
  ufw reject out 465/tcp
  ufw reject out 587/tcp
fi

ufw --force enable
ufw reload

echo "==> 当前 UFW 状态："
ufw status verbose

echo "==> 配置 Fail2Ban..."
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

echo "==> Fail2Ban 状态："
fail2ban-client status
fail2ban-client status sshd

echo "==> 完成。"
