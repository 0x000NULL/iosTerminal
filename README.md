# iosTerminal

A personal, **iPhone-only** SSH + Mosh terminal for driving **tmux + coding agents + long-lived
shells** on a remote machine reached over **Tailscale**, with an on-screen modifier key bar
(Ctrl, Alt, Esc, Tab, Shift+Tab, arrows).

## Status

| Milestone | State |
|---|---|
| Xcode project (XcodeGen + SwiftTerm 1.5.0), builds on simulator | ✅ |
| `Transport` protocol + on-device demo shell (`LocalEchoTransport`) | ✅ |
| On-screen key bar (sticky Ctrl/Alt, Esc, Tab, ⇧Tab, arrows, ⏎/Ctrl-J, ^C, ^B) | ✅ verified (UI + unit tests) |
| Key→byte mappings (arrows incl. DECCKM, Ctrl+arrow, Shift+Tab) | ✅ XCTest |
| libssh2 1.11 SSH transport (interactive PTY, ed25519/RSA/password/Tailscale-SSH) | ✅ verified end-to-end vs real OpenSSH (ed25519 + RSA) + on real device |
| **Runs on device** (SSH + tmux + coding agents), rendering clean | ✅ verified on iPhone (iOS 26) |
| Profiles (SwiftData) + Keychain + host-key TOFU prompt | ✅ |
| Reconnect (NWPathMonitor + foreground; tmux reattach) | ✅ |
| Secure-Enclave P-256: keygen + OpenSSH pubkey export | ✅ (foundation; SE *auth* sign-callback is device-only TODO) |
| Mosh: spike → bootstrap (`mosh-server` exec + `MOSH CONNECT` parse) → orchestration | ✅ wired & parser-tested; `mosh_main` behind `MOSH_ENABLED` (add framework on device) |

### v0.2 — daily-driver improvements (audit-driven)
- **Reliability**: TCP + libssh2 keepalive (dead-link → fast auto-reconnect, not a frozen "Connected"),
  bounded connect/handshake timeout, errno-specific errors, auto-retry with backoff gated on connectivity.
- **Touch UX**: paste key, font size (A-/A+ keys, pinch, setting), more keys (PgUp/PgDn/Home/End/Del,
  `^D ^L ^R ^Z`, shell punctuation), a tmux chord menu, key haptics, scroll-to-bottom, hide-keyboard.
- **Security**: host-key-changed alert defaults to **Reject** + shows both fingerprints; **Face ID
  app-lock** (setting, default on) + app-switcher privacy cover; known_hosts written encrypted.
- **Power**: scrollback search; terminal-bell → local **notification** when backgrounded (babysit long
  coding agents runs); per-profile mosh `--predict` + custom startup command. A `SettingsView` (gear).
- **Perf**: dropped a redundant per-feed full redraw; gate the scroll-offset redraw to real movement.

### Device rendering note
SwiftTerm's iOS CoreText renderer sets `nativeBackgroundColor = .clear` in `setupOptions()`, so its
`draw()` background fill is a transparent no-op — on a real device the reused layer backing store is
never cleared and glyphs accumulate (ghosting/overlap/smear); it's invisible in the Simulator (fresh
backing per captured frame). `AppTerminalView` fixes this by marking the view opaque and restoring an
opaque `nativeBackgroundColor`. See `Sources/Terminal/AppTerminalView.swift`.

## Build & run

`Vendor/` (the GPL mosh xcframework) is gitignored, so after a fresh clone fetch it first
(personal builds only — do not redistribute the resulting binary):

```sh
brew install xcodegen                 # one-time
./scripts/fetch-mosh.sh               # downloads + checksums Vendor/mosh.xcframework (GPL)
xcodegen generate
xcodebuild -project iosTerminal.xcodeproj -scheme iosTerminal \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build -clonedSourcePackagesDirPath .spm \
  CODE_SIGNING_ALLOWED=NO build        # or: test
```

Open `iosTerminal.xcodeproj` in Xcode, set your Team, and run on device.
Requires the Metal toolchain component: `xcodebuild -downloadComponent MetalToolchain`.

## Architecture

One `TerminalView` (SwiftTerm, MIT), a swappable `Transport` (SSH / Mosh / demo), and tmux
as the server-side durability layer. See `~/docs/plans/session-plan.md`
for the full design and `docs/SERVER_SETUP.md` for the remote host setup.

- **Inbound** bytes → `terminalView.feed(byteArray:)` (background-thread-safe).
- **Outbound** bytes → `TerminalViewDelegate.send` → transport's **serial write queue**
  (never blocks the main thread).
- Durability: iOS suspends sockets in the background, so the app reconnects on foreground;
  tmux (and mosh's roaming) preserve the session.

## ⚠️ Licensing / personal-use guardrail

This app is built for **single-user, single-device, personal use** and is intended to link
GPL-3.0 components (mosh, and code/artifacts derived from Blink Shell) for the Mosh transport.
GPL-3.0 obligations trigger on **distribution**, not private use. Therefore:

- **Do not** redistribute the built binary, publish it on the App Store, or share it via
  TestFlight / ad-hoc to anyone else.
- **Do not** commit the integrated GPL binaries to a public repository.
- Keep the original app code (UI, key bar, profiles, Keychain) modular and free of GPL
  imports where avoidable, so an MIT-only, SSH-only build remains possible.

SwiftTerm is MIT and is fine to redistribute with attribution.
