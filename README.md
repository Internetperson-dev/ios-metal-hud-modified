# iOS Metal HUD Wireless Launcher

Launch any iOS app with the **Metal performance HUD** — wirelessly, no Xcode, no jailbreak.

```
FPS  |  GPU %  |  Memory  |  Draw Calls  |  Metal Resources
─────────────────────────────────────────────────────────────
 60  |   45%   |  2.7 GB  |    2,341     |     387
```


---

## How It Works

Apple's Metal HUD (`MTL_HUD_ENABLED=1`) is a built-in GPU debug overlay. Normally only available through Xcode. This tool uses [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) to enable it on any app over WiFi.

No app code is modified. No memory is patched. No cheating — it's Apple's own debug tool.

This fork uses UV to deal with Python dependencies and is only tested on Linux.


git clone https://github.com/ios-metal-hud-modified ~/Projects/ios-metal-hud-modified
cd ~/Projects/ios-metal-hud-modified
chmod u+x hud_launcher.sh ; ./hud_launcher.sh


## FAQ

**Is this considered cheating?**
No. It enables Apple's built-in debug overlay — no game code is modified or inspected.

**Does it work with any app?**
Any app that uses Metal for rendering. Some apps may explicitly disable the HUD.

**Will it get me banned?**
It's the same mechanism Xcode and Instruments use. No game data is touched. As with any third-party tool, use at your own risk.

**Can I use this without a computer?**
No.

**Does it work over cellular?**
Only if both devices are on the same Tailscale mesh network.
