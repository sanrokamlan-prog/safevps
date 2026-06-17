# Server Security Setup

Ubuntu/Debian 服务器基础安全加固脚本，用于配置 UFW 防火墙和 Fail2Ban SSH 防护。

## 功能

- 安装/确保 `ufw` 和 `fail2ban` 已安装
- 允许并限速 SSH TCP 端口，默认 `22`
- 阻止服务器直接对外发送邮件：TCP `25`、`465`、`587`
- 允许指定 UDP 端口范围，默认 `10000:10010`
- 启用 UFW 防火墙
- 配置 Fail2Ban 的 `sshd` jail
- 60 秒内 SSH 登录失败 3 次后永久封禁
- 自动把当前 SSH 客户端 IP 加入 Fail2Ban `ignoreip`，降低误封自己的风险

## 使用方法

在 Ubuntu/Debian 服务器上执行：

```bash
wget https://raw.githubusercontent.com/sanrokamlan-prog/safevps/main/setup_server_security.sh
sudo bash setup_server_security.sh
```

如果你想直接一行执行：

```bash
wget -O setup_server_security.sh https://raw.githubusercontent.com/sanrokamlan-prog/safevps/main/setup_server_security.sh && sudo bash setup_server_security.sh
```

> 上传到 GitHub 后，请把上面 URL 中的 `YOUR_GITHUB_USERNAME` 替换为你的 GitHub 用户名。

## 可选参数

可以通过环境变量修改默认配置：

```bash
sudo SSH_PORT=2222 UDP_RANGE=10000:20000 bash setup_server_security.sh
```

可用变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SSH_PORT` | `22` | 要保护、允许并限速的 SSH 端口 |
| `UDP_RANGE` | `10000:10010` | 要允许的 UDP 端口范围 |
| `ASSUME_YES` | `0` | 设置为 `1` 时跳过交互确认 |

跳过确认示例：

```bash
sudo ASSUME_YES=1 bash setup_server_security.sh
```

自定义 SSH 端口并跳过确认：

```bash
sudo SSH_PORT=2222 ASSUME_YES=1 bash setup_server_security.sh
```

## 注意事项

执行前请确认：

1. 你当前 SSH 使用的端口和 `SSH_PORT` 一致。
2. 如果服务器已有 UFW 或 Fail2Ban 配置，建议先备份。
3. `bantime = -1` 表示 Fail2Ban 永久封禁暴力破解 IP。
4. 如果脚本无法识别你的当前 SSH 客户端 IP，Fail2Ban 的白名单只会包含本机地址。

## 查看状态

查看 UFW 状态：

```bash
sudo ufw status verbose
```

查看 Fail2Ban 状态：

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

## 解除 Fail2Ban 封禁

如果需要解除某个 IP 的封禁：

```bash
sudo fail2ban-client set sshd unbanip 1.2.3.4
```
