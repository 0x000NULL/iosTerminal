# Server setup (mosh + SSH + tmux over Tailscale)

The iOS app is only a client. Durability of your coding agents / long-lived shells lives
**server-side in tmux**; mosh just makes reconnecting instant. Do this once on the remote
machine you reach over Tailscale.

## 1. Install mosh, OpenSSH, tmux

```sh
sudo apt update && sudo apt install -y mosh openssh-server tmux   # Debian/Ubuntu
# Fedora: sudo dnf install -y mosh openssh-server tmux
# Arch:   sudo pacman -S mosh openssh tmux
```

Confirm `mosh-server` is reachable on a **non-interactive** SSH `PATH` (the app runs it via
an SSH exec, not a login shell):

```sh
ssh you@host 'which mosh-server'      # must print a path
```

## 2. Generate a UTF-8 locale (mosh aborts without one)

```sh
sudo locale-gen en_US.UTF-8 && sudo update-locale
```

So a **non-interactive** exec sees locale + PATH, set them where every shell reads them
(not just interactive rc files). For zsh, `/etc/zshenv`; otherwise `/etc/environment`:

```sh
# /etc/zshenv  (or /etc/environment without the 'export')
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
```

## 3. Authorize the app's key

Add the app's public key (ed25519, RSA, or the in-app Secure-Enclave P-256 key) to
`~/.ssh/authorized_keys`. Modern OpenSSH (9.x) accepts RSA only via `rsa-sha2-256/512`,
which the app's libssh2 1.11 supports and `sshd` enables by default. If you locked down
`PubkeyAcceptedAlgorithms`, make sure it still includes `rsa-sha2-*`.

## 4. Open mosh's UDP ports **on the tailnet**

Tailscale (WireGuard) carries mosh's UDP to your `100.x` address — no public
port-forwarding. Just allow the range on the tailscale interface / ACLs:

```sh
# ufw example — allow mosh UDP only over the tailnet interface
sudo ufw allow in on tailscale0 to any port 60000:61000 proto udp
```

(If you use Tailscale ACLs, permit `udp:60000-61000` between your devices.)

## 5. Use real OpenSSH for the bootstrap (not Tailscale SSH)

Mosh bootstraps by running `mosh-server` over an SSH **PTY exec**. Tailscale's built-in SSH
historically broke that (tailscale/tailscale#4919; fixed in client 1.28+, but still finicky).
**Run normal `sshd`** on the tailnet and connect to the `100.x` IP. If you must use Tailscale
SSH, the app can fall back to `mosh --no-ssh-pty`.

Connect by **raw `100.x` IP** in the app's profile (MagicDNS `*.ts.net` names resolve
fine once the tunnel is up, but raw IP is the robust default).

## 6. tmux config (`~/.tmux.conf`)

```tmux
set -g  history-limit 50000     # mosh has no scrollback — tmux holds it
set -s  extended-keys on        # CSI-u / modifyOtherKeys for richer key combos
set -g  mouse on                # optional: touch scroll / pane select
```

## 7. How the app connects

1. SSH to the `100.x` host, authenticate with your key.
2. Run the mosh bootstrap as an SSH exec, with tmux as the session's foreground process:

   ```sh
   mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -l LC_ALL=en_US.UTF-8 -- tmux new -A -s main
   ```

3. Parse `MOSH CONNECT <udp-port> <base64-key>` from stdout, close SSH, speak mosh's SSP
   over UDP to that port using `MOSH_KEY`.
4. Run **coding agents inside tmux** (`tmux new -A -s main` reattaches the same session), so
   it survives the app being killed — reattach with the same command on relaunch.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `mosh-server needs a UTF-8 native locale` | Step 2 — `locale-gen en_US.UTF-8`, set in `/etc/zshenv`. |
| Bootstrap parse fails / garbage before `MOSH CONNECT` | An rc file prints on non-interactive shells. Guard banners with `[[ $- == *i* ]] || return`. |
| `Nothing received from server on UDP port 600xx` | UDP not allowed on `tailscale0` (step 4), or you're not on the tailnet. |
| RSA auth `no mutual signature algorithm` | Old server `PubkeyAcceptedAlgorithms`; add `rsa-sha2-256,rsa-sha2-512`. |
| Connection refused / no route | Tailscale tunnel is down — open the Tailscale app and enable the VPN. |
