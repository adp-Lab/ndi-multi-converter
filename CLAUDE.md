# CLAUDE.md — ndi-multi-converter

## What this is
Shell script (`setup.sh`) that creates 3 additional signed copies of NDI Scan Converter (NewTek/Vizrt) on macOS, each broadcasting a distinct NDI source name, so up to 4 window captures can run simultaneously from one Mac. Full details in README.md — this file is for AI-session context, not user docs.

## Tech stack
- Bash + Python 3 (inline, for binary patching) + OpenSSL 3 (Homebrew) + macOS `codesign`/`security`/`tccutil`
- No build step, no dependencies to install beyond Homebrew OpenSSL
- Deployment: none — this is a local setup script users run on their own Mac, not a hosted service

## Compatibility
- macOS 14 Sonoma (MacBook Pro M1): fully working
- macOS 15.7.5 Sequoia (Mac Mini, arm64): confirmed working 2026-07-29, 4 simultaneous instances verified in OBS
- Intel Mac / macOS 13 or earlier: untested

## Key decisions / constraints discovered
- **`setup.sh` must run in a GUI (Aqua) session — not over plain SSH.** The certificate-import step (`security import` into the login keychain) requires a GUI-bound session; a bare `ssh host command` session (launchd session type `Background`) fails with `User interaction is not allowed`, even when the same user is logged in at the console. Run via Screen Sharing or physically at the machine.
- Self-signed cert is per-machine and lives in that Mac's Keychain — not transferable. Re-run `setup.sh` fresh on each new machine.
- Binary patch targets two fixed byte offsets (36434, 130642) in the universal binary for the "Scan Converter" string (14 bytes, replaced with an equal-length name) — the script self-verifies the expected bytes before patching, so it fails loudly rather than corrupting the binary if NewTek ships a different build.
- `NDICommon.framework` has a non-standard flat layout (not symlinks) in the original app — must be fixed before `codesign --deep` will sign cleanly.
- Do not attempt to multiply NDI Video Monitor alongside multiple Scan Converter instances — CVDisplayLink conflict can crash WindowServer (untested since the signing fix; flagged as a backlog item, not resolved).

## Do not touch
- The original `/Applications/NDI Scan Converter.app` is never modified by the script — only copies.
- Don't hardcode a machine-specific Keychain cert name or path — the script auto-detects/creates `NDI Local Signing` per machine.

## Related
- Before any change to `setup.sh`'s signing/patching logic, invoke the `check-docs` skill if touching unfamiliar macOS codesign/entitlements behavior — this is exactly the kind of "verify against installed source, not memory" case CLAUDE.md's global policy calls out.
