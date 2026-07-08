# iOS Metal HUD Wireless Launcher

Launch any iOS app with the **Metal performance HUD** — wirelessly, no Xcode, no jailbreak.

```
FPS  |  GPU %  |  Memory  |  Draw Calls  |  Metal Resources
─────────────────────────────────────────────────────────────
 60  |   45%   |  2.7 GB  |    2,341     |     387
```

Works on **Linux**, **macOS**, and **Windows** (WSL2).

---

## How It Works

Apple's Metal HUD (`MTL_HUD_ENABLED=1`) is a built-in GPU debug overlay. Normally only available through Xcode. This tool uses [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) to enable it on any app over WiFi.

No app code is modified. No memory is patched. No cheating — it's Apple's own debug tool.

---

## Prerequisites

| | Linux | macOS | Windows |
|--|-------|-------|---------|
| **Python** | 3.13+ | 3.13+ | 3.13+ |
| **pipx** | `sudo apt install pipx` | `brew install pipx` | `pip install pipx` |
| **usbmuxd** | `sudo apt install usbmuxd` | Bundled | iTunes provides it |
| **pymobiledevice3** | `pipx install pymobiledevice3` | same | same |

---

## Installation

### 1. Install Python 3.13+

**Linux (Ubuntu/Debian):**
```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install python3.13 python3.13-venv python3.13-dev -y
```

**macOS:**
```bash
brew install python@3.13
```

**Windows:**
Download from [python.org](https://python.org) — check "Add to PATH" during install.

### 2. Install pymobiledevice3

```bash
pipx install --python python3.13 pymobiledevice3
```

Verify:
```bash
pymobiledevice3 version
# → 9.x.x
```

### 3. Linux only — install usbmuxd

```bash
sudo apt install usbmuxd -y
sudo systemctl restart usbmuxd
```

macOS has it built-in. Windows needs iTunes (provides the usbmux driver).

---

## First-Time Setup (Pairing)

Do this once with a **USB cable**.

### Connect & pair

1. Plug iPhone into computer via USB
2. Unlock iPhone — tap **Trust This Computer**
3. Run:

```bash
pymobiledevice3 lockdown pair
```

If it fails with `BadDevError`, use `idevicepair` instead:

```bash
# Linux
sudo apt install libimobiledevice-utils -y

# macOS
brew install libimobiledevice

idevicepair unpair
idevicepair pair

# Copy the pair record for pymobiledevice3
mkdir -p ~/.pymobiledevice3
cp /var/lib/lockdown/*.plist ~/.pymobiledevice3/ 2>/dev/null
cp /var/db/lockdown/*.plist ~/.pymobiledevice3/ 2>/dev/null
```

### Enable WiFi connections

```bash
pymobiledevice3 lockdown wifi-connections --state on
```

### ⚠️ Important iPhone setting

**Settings → WiFi → tap (i) → Private Wi-Fi Address → OFF**

iOS rotates private MACs by default, which breaks device discovery.

---

## Usage

### Wireless (WiFi — same network)

```bash
./hud_launcher.sh
```

Select an app. The script will:
1. Create a RemotePairing TCP tunnel over WiFi
2. Launch the app with `MTL_HUD_ENABLED=1`
3. Metal HUD overlays on your iPhone screen

### Manual wireless

```bash
# Terminal 1: Create tunnel
sudo pymobiledevice3 remote start-tunnel -t wifi --protocol tcp --udid <UDID>

# Terminal 2: Launch app
pymobiledevice3 developer dvt launch com.tencent.ig \
  --env MTL_HUD_ENABLED=1 \
  --rsd <RSD_ADDRESS> <RSD_PORT>
```

### Wired (USB)

```bash
pymobiledevice3 developer dvt launch com.tencent.ig \
  --env MTL_HUD_ENABLED=1 --userspace
```

---

## The Script

### `hud_launcher.sh`

```bash
#!/bin/bash

PMD_PATH="$HOME/.local/bin/pymobiledevice3"
[ ! -f "$PMD_PATH" ] && PMD_PATH="pymobiledevice3"

# ── Set your device UDID here ──
# Find it with: pymobiledevice3 usbmux list
UDID="<your-device-uuid>"

clear
echo "========== iOS Metal HUD Launcher =========="
echo "1) Clash of Clans"
echo "2) PUBG Mobile"
echo "3) Exit"
read -p "Choice [1-3]: " choice

case $choice in
    1) BUNDLE="com.supercell.magic" ;;
    2) BUNDLE="com.tencent.ig" ;;
    3) exit 0 ;;
    *) echo "Invalid"; exit 1 ;;
esac

echo "Starting tunnel..."
sudo "$PMD_PATH" remote start-tunnel -t wifi --protocol tcp \
  --udid "$UDID" > /tmp/tunnel_out.txt 2>&1 &
TUNNEL_PID=$!

sleep 8
RSD_ADDR=$(grep "RSD Address:" /tmp/tunnel_out.txt | awk '{print $NF}')
RSD_PORT=$(grep "RSD Port:" /tmp/tunnel_out.txt | awk '{print $NF}')

"$PMD_PATH" developer dvt launch "$BUNDLE" --env MTL_HUD_ENABLED=1 \
  --rsd "$RSD_ADDR" "$RSD_PORT" 2>&1 | grep -v "LSSupportsGameMode"

kill $TUNNEL_PID 2>/dev/null
```

### Adding apps

Edit the `case` block with bundle IDs:

| App | Bundle ID |
|-----|-----------|
| Clash of Clans | `com.supercell.magic` |
| PUBG Mobile | `com.tencent.ig` |
| Call of Duty Mobile | `com.activision.callofduty.shooter` |
| Genshin Impact | `com.miHoYo.GenshinImpact` |
| Roblox | `com.roblox.Roblox` |
| Brawl Stars | `com.supercell.brawlstars` |

Find any app's bundle ID:
```bash
pymobiledevice3 apps list | grep -i "name"
```

---

## Finding Your UDID

```bash
pymobiledevice3 usbmux list
```

Look for `UniqueDeviceID`. Replace it in the script.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `BadDevError` during pair | Reinstall usbmuxd: `sudo apt install --reinstall usbmuxd` |
| Tunnel needs root | `sudo` is required for TUN/TAP device creation |
| `NO_CIPHERS_AVAILABLE` | Install Python 3.13+ (needed for PSK ciphers) |
| `QuicProtocolNotSupportedError` | Use `--protocol tcp` flag |
| Bonjour shows no device | Disable Private Wi-Fi Address on iPhone |
| `Device is not connected` | Verify iPhone and computer are on same WiFi subnet |
| Pairing fails over network | Pair over USB first, then copy the record |

---

## FAQ

**Is this considered cheating?**
No. It enables Apple's built-in debug overlay — no game code is modified or inspected.

**Does it work with any app?**
Any app that uses Metal for rendering. Some apps may explicitly disable the HUD.

**Will it get me banned?**
It's the same mechanism Xcode and Instruments use. No game data is touched. As with any third-party tool, use at your own risk.

**Can I use this without a computer?**
No. You need a Linux/macOS/Windows machine to run pymobiledevice3.

**Does it work over cellular?**
Only if both devices are on the same Tailscale mesh network.
