# ndi-multi-converter

Run up to 4 independent NDI Scan Converter instances on a single Mac, each capturing a different window and broadcasting a distinct NDI source name on the network.

---

## What this does

NDI Scan Converter is a free tool by NewTek/Vizrt that broadcasts a Mac's screen or a single window as an NDI source. By default it only runs as one instance — so only one window at a time.

This setup script creates three additional signed copies of the app with unique NDI source names. All four can run simultaneously and appear as distinct sources in any NDI receiver (OBS, vMix, Resolume, mimoLive, NDI Monitor, etc.).

**On the network they appear as:**
```
HOSTNAME (Scan Converter)      ← original app, unchanged
HOSTNAME (Scan Convert 2)
HOSTNAME (Scan Convert 3)
HOSTNAME (Scan Convert 4)
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS 14 Sonoma or later | See compatibility below |
| [NDI Tools](https://ndi.video/tools/) | Free download from ndi.video — install before running setup |
| [Homebrew](https://brew.sh) | Package manager for macOS |
| OpenSSL 3 (via Homebrew) | `brew install openssl` |

The script cannot use macOS's built-in LibreSSL — it is not compatible with the certificate creation step.

---

## Setup

```bash
# 1. Clone this repo
git clone git@github.com:adp-Lab/ndi-multi-converter.git
cd ndi-multi-converter

# 2. Make the script executable
chmod +x setup.sh

# 3. Run it
./setup.sh
```

The script will:
- Create a local code-signing certificate (`NDI Local Signing`) in your Keychain
- Create copies 2, 3, and 4 in `/Applications`
- Sign each with that certificate
- Reset Screen Recording permissions so macOS prompts cleanly on first launch

**After setup:** Open each app once from `/Applications` and grant Screen Recording when asked. macOS will not ask again after that.

---

## Usage

Open any combination from `/Applications`:

```
NDI Scan Converter.app      (original — unchanged)
NDI Scan Convert 2.app
NDI Scan Convert 3.app
NDI Scan Convert 4.app
```

In each app: select the window you want to capture. The app immediately starts broadcasting that window as an NDI source. On your receiving machine, all four appear as separate sources.

No special configuration needed on the receiving end — standard NDI source discovery works as usual.

---

## Tested

| Configuration | Result |
|---|---|
| MacBook Pro M1 / macOS 14.8.4 Sonoma | ✅ Fully working |
| 4 simultaneous instances capturing different windows | ✅ Stable |
| Receiving in OBS (obs-ndi / DistroAV) | ✅ |
| Receiving in mimoLive | ✅ |
| Permission persists across app restarts | ✅ |
| Permission persists across full reboot | ✅ |
| macOS 15 Sequoia | ⚠️ Untested — same architecture, likely works |
| macOS 13 Ventura or earlier | ⚠️ Untested |
| Intel Mac | ⚠️ Untested (universal binary, may work) |

---

## App naming

In the **Cmd+Tab switcher**, each instance shows its correct name (`NDI Scan Convert 2`, `3`, `4`). In the **menu bar**, all instances display as "NDI Scan Converter" when running in the background — the active one shows its number. This is cosmetic and does not affect NDI functionality or source naming on the network.

## Known limitations

**Occluded windows go black**
If a captured window is completely covered by other windows, the stream freezes or goes black. This is a macOS window capture limitation — the OS does not composite hidden window contents. Workaround: keep captured windows on a separate Space or use a virtual display.

**Screen Recording permission per app**
Each of the three new apps must be granted Screen Recording permission once on first launch. macOS handles each app as a separate identity. After the first grant, the permission is permanent.

**Self-signed certificate is machine-local**
The signing certificate created by setup.sh lives in your Mac's Keychain. It is not transferable. If you set this up on another machine, run setup.sh there too — it will create a fresh certificate automatically.

**No Video Monitor instances**
NDI Video Monitor uses CVDisplayLink (high-priority display sync) which conflicts with multiple Scan Converter instances and can cause a WindowServer crash. Do not run more than one Video Monitor instance at the same time as multiple Scan Converters. This tool only multiplies Scan Converter (the sending side).

**Not tested after macOS updates**
After a major macOS update, Screen Recording permissions may need to be re-granted. This is standard macOS behaviour for apps with modified signatures.

---

## How it works

NDI Scan Converter has its source name (`Scan Converter`) hardcoded in the binary at two positions. The setup script:

1. Copies the original app three times
2. Edits the binary in-place at those two positions (same byte length — no padding needed)
3. Assigns a new bundle identifier to each copy so macOS treats them as distinct apps
4. Creates a self-signed code-signing certificate and signs each copy with Hardened Runtime + the original app's entitlements
5. This gives each copy a stable TCC identity, so Screen Recording permission persists across launches

The original app is never modified.

---

## Re-running setup

Running `./setup.sh` again is safe — it recreates the copies from the original and re-signs them. Existing copies in `/Applications` are replaced. The certificate is reused if it already exists.

---

## Disclaimer

This script modifies locally installed copies of NDI Scan Converter (a free tool by NewTek/Vizrt) for personal use on your own machine. The original app is not modified. Modified binaries are not distributed. Use at your own risk and in accordance with NewTek's terms of service.

This project is not affiliated with or endorsed by NewTek or Vizrt.
