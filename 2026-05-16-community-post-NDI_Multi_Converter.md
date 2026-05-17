# Running 4 NDI Scan Converters simultaneously on one Mac — a deep dive

**TL;DR:** I built a setup script that creates 4 independent NDI Scan Converter instances on a Mac, each capturing a different window and appearing as a distinct source in OBS, mimoLive, or any NDI receiver. It's free, open source, and (after a long journey) actually works.

→ **[github.com/adp-Lab/ndi-multi-converter](https://github.com/adp-Lab/ndi-multi-converter)**

---

## The problem

NDI Scan Converter is a fantastic free tool — but it only runs as one instance. If you want to send multiple independent window captures as separate NDI sources from one Mac, you're stuck. The obvious workaround is an OBS middleman on the sending machine, but that costs real resources and adds a layer of complexity.

What I actually wanted: open 4 windows on a Mac, have each one appear as a clean, independent NDI source on the network. No OBS on the sender. Just Scan Converter doing what it does, times four.

---

## What we tried (and what didn't work)

### Attempt 1: Copy the app, change the bundle ID, ad-hoc re-sign

Copy the app three times, edit the `CFBundleIdentifier` in `Info.plist`, re-sign with `codesign --sign -` (ad-hoc). 

**Result: instant logout / WindowServer crash on macOS 14 Sonoma.**

Root cause: ad-hoc re-signed apps requesting Screen Recording on Sonoma caused `tccd` and WindowServer to crash hard. Confirmed via crash logs. Dead end.

### Attempt 2: AppleScript wrapper to launch extra instances

Tiny wrapper apps that fire `open -n -a "NDI Scan Converter"` — no binary modification, just launch another instance.

**Result: stable for 2 instances, crashes with 3+.**

Root cause: NDI Video Monitor uses CVDisplayLink (high-priority display sync). Multiple Scan Converter instances + Video Monitor = WindowServer deadlock after ~40 seconds. Confirmed via spinning process logs.

Key finding: **2× Scan Converter + 1× Video Monitor = stable**. The crash is specifically Video Monitor's fault, not Scan Converter's.

### Attempt 3: Binary edit the NDI source name + ad-hoc re-sign

NDI Scan Converter has its source name (`Scan Converter`) hardcoded in the binary at two positions. Replaced with `Scan Convert 2` (same byte length, clean swap). Changed bundle ID. Ad-hoc re-signed.

**Partial success:** NDI Video Monitor on the receiving side showed two distinct sources — `Scan Converter` and `Scan Convert 2`. The binary edit worked.

**But:** Screen Recording permission prompted on every single launch. And without stable permission, the app could only capture the desktop wallpaper — not actual windows.

Root cause: ad-hoc signing on macOS 14 Sonoma does not create a stable TCC identity. The code signing requirement stored in TCC's database doesn't reliably match the running process on subsequent launches. macOS treats it as a new/unknown binary every time.

---

## What actually works

The fix is replacing ad-hoc signing with a **self-signed local certificate**.

Ad-hoc signing uses a binary hash as its identity — fragile. A self-signed certificate creates a persistent identity in your Keychain that macOS can verify on every launch. TCC stores the permission against that certificate identity, not a hash. Result: permission granted once, persists forever.

The full solution:

1. Create a self-signed code signing certificate (`NDI Local Signing`) using OpenSSL + Keychain
2. Copy the original NDI Scan Converter app 3 times
3. Binary-edit the NDI source name string at both positions in the universal binary
4. Update the bundle identifier so macOS treats each copy as a distinct app
5. Fix a quirk in the framework bundle structure (the original has flat files where macOS expects symlinks — codesign requires the standard layout)
6. Sign each copy with the local cert + Hardened Runtime + the original app's entitlements
7. Grant Screen Recording once per app — it sticks

The script at [github.com/adp-Lab/ndi-multi-converter](https://github.com/adp-Lab/ndi-multi-converter) does all of this automatically.

---

## Results

Tested on **MacBook Pro M1 / macOS 14.8.4 Sonoma**:

- 4 simultaneous instances running — stable ✅
- Each capturing a different window (tested with 4 YouTube videos in Chrome) ✅
- All 4 appearing as distinct NDI sources in OBS (DistroAV plugin) ✅
- All 4 appearing as distinct NDI sources in mimoLive ✅
- All 4 sources visible and routable in NDI Router ✅
- All 4 sources visible in [Tractus Multiview](https://www.tractusevents.com/blog/multiviewer-for-ndi/) ✅
- MacBook on **WiFi** → remote Mac running OBS over LAN — works (tested with small-scale Chrome windows; bandwidth scales with window size/content) ✅
- Screen Recording permission persists across **full reboot** ✅
- **3 instances used in live production across two consecutive show days** ✅

**App switcher and menu bar:** Each instance shows its correct name (`NDI Scan Convert 2`, `3`, `4`) in both the Cmd+Tab app switcher and the menu bar. The setup script sets `CFBundleName` per copy, so macOS identifies each one correctly throughout the UI.

---

## Known limitations

**Covered windows go black.** If a captured window is completely hidden behind other windows, the stream freezes or goes black. This is a macOS window capture limitation — the OS doesn't render occluded window contents via the capture API. Workaround: keep captured windows on a separate Space, or use a secondary display.

**NDI Video Monitor multi-instance: not yet tackled.** During early testing (before the signing fix), running 2× Scan Converter + 2× Video Monitor caused a WindowServer crash — confirmed via crash logs as a CVDisplayLink deadlock inside Video Monitor. However, that test used unstable app instances and we haven't retested with the properly signed setup. Multi-instance Video Monitor is the logical next step and should be solvable with the same binary-edit + signing approach. Not blocking for the sending side, but worth exploring.

**Self-signed cert is per-machine.** The signing certificate lives in your local Keychain and can't be shared. Run the setup script on each machine.

**macOS 15 Sequoia: untested.** Same approach should work, but not verified yet. Will update the repo when confirmed.

---

## Requirements

- macOS 14 Sonoma (macOS 15 likely works)
- [NDI Tools](https://ndi.video/tools/) installed (free)
- [Homebrew](https://brew.sh) + `brew install openssl`

Then just:

```bash
git clone git@github.com:adp-Lab/ndi-multi-converter.git
cd ndi-multi-converter
chmod +x setup.sh
./setup.sh
```

---

Happy to hear if this works on other macOS versions or hardware. Especially curious about Sequoia.
