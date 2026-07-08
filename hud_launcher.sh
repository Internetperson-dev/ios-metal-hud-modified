#!/bin/bash
#
# iOS Metal HUD Wireless Launcher
# Dependencies: Python 3.13+, pymobiledevice3
# 
# Usage: ./hud_launcher.sh
# Both machines must be on the same WiFi network.

PMD_PATH="$HOME/.local/bin/pymobiledevice3"
[ ! -f "$PMD_PATH" ] && PMD_PATH="pymobiledevice3"

# ── Configuration ──
# Replace with your device's UDID from `pymobiledevice3 usbmux list`
UDID="<YOUR_DEVICE_UDID>"

# ── App Menu ──
clear
echo "=============================================="
echo "       iOS Metal HUD Game Launcher           "
echo "=============================================="
echo ""
echo "  1) Clash of Clans"
echo "  2) PUBG Mobile"
echo "  3) Exit"
echo ""
read -p "  Select an option [1-3]: " choice

case $choice in
    1) BUNDLE="com.supercell.magic" ;;
    2) BUNDLE="com.tencent.ig" ;;
    3) exit 0 ;;
    *) echo "  Invalid choice."; exit 1 ;;
esac

# ── Establish WiFi Tunnel ──
echo ""
echo "  Creating RemotePairing tunnel..."
sudo "$PMD_PATH" remote start-tunnel -t wifi --protocol tcp \
  --udid "$UDID" > /tmp/tunnel_out.txt 2>&1 &
TUNNEL_PID=$!

sleep 8
RSD_ADDR=$(grep "RSD Address:" /tmp/tunnel_out.txt | awk '{print $NF}')
RSD_PORT=$(grep "RSD Port:" /tmp/tunnel_out.txt | awk '{print $NF}')

if [ -z "$RSD_ADDR" ] || [ -z "$RSD_PORT" ]; then
    echo "  Error: Tunnel failed to establish. Check /tmp/tunnel_out.txt"
    kill $TUNNEL_PID 2>/dev/null
    exit 1
fi

echo "  Tunnel established: $RSD_ADDR:$RSD_PORT"

# ── Launch with Metal HUD ──
echo "  Launching $BUNDLE with Metal HUD..."
"$PMD_PATH" developer dvt launch "$BUNDLE" --env MTL_HUD_ENABLED=1 \
  --rsd "$RSD_ADDR" "$RSD_PORT" 2>&1 | grep -v "LSSupportsGameMode"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "  ✓ App launched successfully!"
else
    echo ""
    echo "  ✗ Launch failed. Verify device is unlocked."
fi

# ── Cleanup ──
kill $TUNNEL_PID 2>/dev/null
exit 0
