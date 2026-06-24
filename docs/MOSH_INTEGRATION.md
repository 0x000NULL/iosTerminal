# M0 Mosh spike — result & integration recipe

**Verdict: GO.** Driving mosh standalone into our SwiftTerm app is low-risk. We do **not**
reimplement mosh's State Synchronization Protocol, crypto, or protobuf. We reuse Blink's
prebuilt `mosh.xcframework` (the `--enable-ios-controller` build of `blinksh/mosh`) and call
its single C entry point, bridging its stdin/stdout `FILE*`s to SwiftTerm with POSIX pipes.

GPL-3.0 is fine here: personal, non-distributed, single-device use (see README guardrail).

## What's actually shipped

- `blinksh/mosh-apple` builds `blinksh/mosh` @ SHA `3640d36678dc415ba24f03d7f6fb20a0dac1fa6b`
  (version `1.4.0+blink-18.4.5`) with:
  `./configure --disable-server --disable-client --enable-ios-controller --host=<arch>-apple-darwin`
  → static libs (`libmoshcrypto/network/protos/statesync/terminal/iosclient/util.a`) → `libmosh.a`
  → **`mosh.xcframework`** (arm64 device + arm64/x86_64 simulator).
- The Package.swift does **not** declare it as a binaryTarget (only `Protobuf_C_`), but the
  xcframework is published as a **release asset**:
  `https://github.com/blinksh/mosh-apple/releases/download/v1.4.0+blink-18.4.5/mosh.xcframework.zip`
- It depends on **Protobuf_C_ 3.21.1** (`blinksh/protobuf-apple`) and ncurses/terminfo.

## The one entry point (`src/frontend/moshiosbridge.h`)

```c
int mosh_main(
    FILE *f_in, FILE *f_out, struct winsize *window_size,
    void (*state_callback)(const void *, const void *, size_t),
    void *state_callback_context,
    const char *ip, const char *port, const char *key, const char *predict_mode,
    const char *encoded_state_buffer, size_t encoded_state_size, const char *predict_overwrite);
```

- `f_in`  — mosh **reads keystrokes** from here. We write the terminal's outbound bytes to it.
- `f_out` — mosh **writes rendered terminal output** here. We read it and `feed()` SwiftTerm.
- `window_size` — pointer to a live `struct winsize`; mosh re-reads it on **SIGWINCH**.
- `state_callback(ctx, buffer, size)` — mosh hands us encoded session state to persist for
  resume/roam. Keep the latest blob **in memory** (it is the session secret material).
- `ip/port/key` — from the SSH bootstrap (`MOSH CONNECT <port> <key>`; ip = tailnet `100.x`).
- `predict_mode` — `"adaptive"` (default) | `"always"` | `"never"`.
- **`mosh_main` blocks** for the entire session → run it on a dedicated pthread.

Confirmed from Blink's two call sites (`Sessions/MoshSession.m:296`, `Blink/Commands/mosh/mosh.swift:264`).
Resize is `update *window_size; pthread_kill(moshThreadId, SIGWINCH)` (`MoshSession.m:585`).

## Recipe (maps onto our `Transport` protocol)

1. **Add the framework (personal build only — keep out of the committed repo):**
   - `mosh.xcframework` (release `v1.4.0+blink-18.4.5`) + `Protobuf_C_.xcframework` (3.21.1).
   - A module map exposing `moshiosbridge.h` as a C module (e.g. `CMosh`).
   - Bundle terminfo so `TERM=xterm-256color` resolves (set `TERMINFO`/`PATH_LOCALE`).
   - OpenSSL: mosh uses its in-tree AES-OCB; protobuf is the real external dep. (Our libssh2
     already links OpenSSL 1.1.1w — keep one OpenSSL across the binary if mosh needs it.)
2. **Bridge with pipes** (`MoshTransport`, scaffolded behind `#if MOSH_ENABLED`):
   - `pipe(inFds)`  → `f_in = fdopen(inFds[0], "r")`; `send(bytes)` writes to `inFds[1]`.
   - `pipe(outFds)` → `f_out = fdopen(outFds[1], "w")`; a reader thread reads `outFds[0]` →
     `onReceive` → `terminalView.feed(byteArray:)` (background-safe).
   - `struct winsize` initialized from the terminal; `resize()` updates it + `pthread_kill(tid, SIGWINCH)`.
   - `mosh_main(...)` on a dedicated pthread (capture its `tid`).
   - `state_callback` (a `@convention(c)` function; context via `state_callback_context`) stores
     the latest encoded state for foreground roam/resume.
   - `disconnect()` closes the pipes so `mosh_main` returns; join the thread.
3. **Bootstrap (shared with the SSH transport):** SSH-exec
   `mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -l LC_ALL=en_US.UTF-8 [-p <port>] -- tmux new -A -s main`,
   parse `MOSH CONNECT <port> <key>` from stdout, then start `MoshTransport(ip:port:key:)`.

## Remaining unknowns (verify on device)

- **terminfo bundling**: get `xterm-256color` resolving inside the sandbox (broken keys/colors otherwise).
- **protobuf/openssl link**: confirm `mosh.xcframework` + `Protobuf_C_.xcframework` link clean
  under Xcode 26 alongside libssh2's OpenSSL 1.1.1w (no duplicate-symbol clash).
- **`state_callback` cadence** and exactly what to persist for an instant foreground roam.
- Needs the SSH bootstrap (task #4) to supply ip/port/key, plus a device + signing.

## Decision

Proceed with the **prebuilt `mosh.xcframework` + pipe-bridge** path (option (b) "legacy
ios-controller C path" from the plan — but it is the *current* shipping engine, not deprecated:
Blink's newer `mosh.swift` calls the same `mosh_main`). Do **not** modernize `build-mosh` from
source unless the prebuilt framework fails to link under Xcode 26.
