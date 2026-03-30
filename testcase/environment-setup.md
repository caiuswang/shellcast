# Environment Setup Guide

## Overview

ShellCast connects from your iPhone/iPad to your laptop/server using **Tailscale** for networking and optionally **Mosh** for resilient connections. Here's what needs to be set up on each device.

---

## Your Laptop/Server (Remote Host)

### 1. Tailscale (Required)

Tailscale creates a private network so your phone can reach your laptop from anywhere.

**Install:**
```bash
# macOS
brew install --cask tailscale

# Ubuntu/Debian
curl -fsSL https://tailscale.com/install.sh | sh

# Fedora
sudo dnf install tailscale
```

**Setup:**
1. Run `tailscale up` and sign in
2. Note your Tailscale IP: `tailscale ip -4` (e.g. `100.x.y.z`)
3. Ensure SSH is enabled on your machine

### 2. SSH (Required)

SSH must be accessible on your laptop.

**macOS:** System Settings > General > Sharing > Remote Login (enable)

**Linux:** Usually enabled by default. If not:
```bash
sudo systemctl enable --now sshd
```

### 3. tmux (Recommended)

tmux lets you keep terminal sessions running even when disconnected.

```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux

# Fedora
sudo dnf install tmux
```

### 4. Mosh (Optional)

Mosh makes your connection survive WiFi switches, cellular handoffs, and phone sleep. Without it, ShellCast uses SSH which drops on network changes.

```bash
# macOS
brew install mosh

# Ubuntu/Debian
sudo apt install mosh

# Fedora
sudo dnf install mosh
```

**Verify:** `which mosh-server` should return a path.

**Firewall:** Mosh uses UDP ports 60000-61000. If you have a firewall, open these ports. Tailscale's network typically bypasses local firewalls so this is usually not needed.

---

## Your iPhone/iPad

### 1. Tailscale App (Required)

Install the [Tailscale iOS app](https://apps.apple.com/app/tailscale/id1470499037) from the App Store and sign in with the same account as your laptop.

**Verify:** In the Tailscale app, you should see your laptop listed with its `100.x.y.z` IP.

### 2. ShellCast App

Install ShellCast and create a connection:
- **Host:** Your laptop's Tailscale IP (e.g. `100.64.1.2`)
- **Port:** 22
- **Username:** Your laptop username
- **Auth:** Password, Key File, or Tailscale (if using Tailscale SSH)
- **Connection Type:**
  - **SSH** — standard, works everywhere
  - **Mosh** — resilient, requires mosh-server on remote host
  - **Auto** — tries Mosh first, falls back to SSH

---

## Connection Types Explained

| Type | Requires on Server | Network Resilience | Best For |
|------|-------------------|-------------------|----------|
| SSH | SSH server | None — drops on network change | Quick access, stable WiFi |
| Mosh | SSH + mosh-server | Survives WiFi/cellular switches, sleep | Mobile use, unreliable networks |
| Auto | SSH (+ mosh-server optional) | Mosh if available, else SSH | Set and forget |

---

## Quick Verification

From your phone, with Tailscale active on both devices:

1. Open ShellCast
2. Add a connection with your laptop's Tailscale IP
3. Tap to connect
4. You should see your tmux sessions (if tmux is installed)
5. Select a session or connect without tmux
6. You're in a terminal on your laptop

---

## Troubleshooting

**Can't connect at all:**
- Is Tailscale running on both devices? Check the Tailscale app.
- Can you ping the Tailscale IP? (Use another terminal app to test)
- Is SSH enabled on your laptop?

**Mosh fails but SSH works:**
- Is `mosh-server` installed? Run `which mosh-server` on your laptop.
- Switch to "Auto" or "SSH" connection type as a workaround.

**Connection drops when switching WiFi/cellular:**
- This is expected with SSH. Use Mosh or Auto connection type.
- tmux preserves your session server-side regardless — just reconnect.

**"Authentication failed":**
- Check username and password
- For Tailscale SSH: select "Tailscale" auth method (no password needed)
- For key auth: import your private key file in the connection settings
