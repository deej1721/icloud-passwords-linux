# icloud-passwords-linux

Use Apple's **iCloud Passwords** Chrome extension (autofill, saving passwords,
one-time codes) in Chromium on Linux, backed by iCloud for Windows running in
a local Windows VM.

Apple doesn't ship iCloud Passwords for Linux. The extension doesn't do any
crypto or syncing itself. It talks through Chrome
[native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
to `iCloudPasswordsExtensionHelper.exe`, which reads iCloud Keychain through a
signed-in iCloud for Windows. This project runs that real helper in a Windows
VM and forwards its stdio to Linux over SSH.

```
Chromium (Linux)
  └─ iCloud Passwords extension (patched copy, same ID)
       └─ connectNative("com.apple.passwordmanager")
            └─ NativeMessagingHosts/com.apple.passwordmanager.json
                 └─ icloud-pw-shim            ssh -W 127.0.0.1:47811 <vm>
                      ═══ SSH ═══►  icloud-relay.ps1   (loopback only; runs in the user's logged-in session)
                                        └─ starts iCloudPasswordsExtensionHelper.exe per connection, pipes stdio
                                             └─ iCloud for Windows → iCloud Keychain

Pairing code:  helper's hidden code dialog → relay reads it → C:\icloud-relay\pin.log
               → icloud-pw-pin-notify (ssh, pin-follow.ps1) → notify-send + wl-copy
```

Not affiliated with or endorsed by Apple. This repo contains no Apple code:
`patch-extension.py` downloads the extension from the Chrome Web Store and
patches it on your machine.

## Requirements

- A Chromium-based browser on Linux.
- A Windows 10/11 VM with a **TPM** (an emulated `tpm-crb` / swtpm is fine),
  which Windows Hello needs, and **OpenSSH Server** with key-based login from
  the host. A [WinApps](https://github.com/winapps-org/winapps) VM works well.
- The VM running whenever you want autofill, with your Windows user logged in.
  A disconnected RDP session is fine, but signing out stops the relay.

## Setup

### 1. Windows VM

1. Install **iCloud** from the Microsoft Store, e.g. over SSH:
   `winget install --id 9PKTQ5699M62 --source msstore --accept-package-agreements --accept-source-agreements`
2. **Check that Apple's sign-in server is trusted.** From the VM:
   `curl.exe -sI https://gsa.apple.com/`. If that fails with
   `SEC_E_UNTRUSTED_ROOT`, Windows is missing Apple Root CA, and iCloud sign-in
   will fail with a vague error. Fix it from an elevated PowerShell with
   `windows/install-apple-root-ca.ps1`, which downloads the root from apple.com
   and checks its SHA-256 before importing it.
3. Sign in to iCloud with your Apple ID.
4. **Set up a Windows Hello PIN from the VM's local console** (virt-manager /
   SPICE), not over RDP. Windows hides Hello setup in RDP sessions, and iCloud
   won't turn on Passwords without it. In the same console session, turn on
   **Passwords and Keychain** in iCloud.
5. Deploy the relay from the Linux host:
   ```sh
   ./deploy.sh <vm-ssh-alias>
   ```
   This copies the scripts to `C:\icloud-relay`, registers a scheduled task
   (`icloud-relay`) that starts it at logon in your interactive session, and
   starts it now.

### 2. Linux host

```sh
./install.sh <vm-ssh-alias>
```

This installs `~/.local/bin/icloud-pw-shim`, writes
`~/.config/icloud-pw/env`, enables the `icloud-pw-pin` user service (pairing
codes → desktop notification + clipboard; needs `notify-send`, optionally
`wl-copy`), registers the native host for every
Chromium-family browser it finds, and writes the patched extension to
`~/.local/share/icloud-pw/extension`. It also creates a non-hidden symlink,
`~/icloud-pw-extension`.

Then in the browser: open `chrome://extensions`, turn on **Developer mode**,
click **Load unpacked**, and choose `~/icloud-pw-extension`. Don't also
install the Web Store version, because both use the same ID.

### 3. Pair

Click the iCloud Passwords icon. A desktop notification shows the 6-digit
code, and the code is already on your clipboard. Paste it into the extension.

The helper normally shows the code in a small dialog next to the Windows
taskbar. In a WinApps **RemoteApp** session there's no real taskbar, so that
dialog is created hidden and off-screen. The relay reads the code from the
dialog anyway, and `icloud-pw-pin-notify` shows it on Linux.

In a RemoteApp session, Windows startup apps don't run. If pairing or
autofill fails and `iCloudCKKS` / `APSDaemon` aren't running, start iCloud in
the session, e.g. `winapps manual "%LOCALAPPDATA%\Microsoft\WindowsApps\iCloudHome-AppX.exe"`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Extension says the OS is unsupported | You loaded the Web Store version instead of the patched one. |
| iCloud sign-in fails | Apple Root CA is missing. See setup step 2. |
| "Windows Hello is not set up" / no PIN option | You're in an RDP session. Use the local console. |
| Code-entry popup appears but no notification | Check `C:\icloud-relay\pin.log`. If it has the code, the Linux side is at fault: `systemctl --user status icloud-pw-pin`, and check that your notification daemon runs on the Wayland session you're looking at. If it's empty, check that the relay runs in the same session as iCloud (`query user`). Keep a single session for your user: two sessions also break apps like Outlook. |
| Extension connects but nothing works | Run `C:\icloud-relay\test-helper.ps1` in your session. It should print capabilities. From an SSH session it prints `{"cmd":10}` (re-login needed), which is expected there. |
| No notifications at all (Hyprland with several instances) | The notification daemon (e.g. mako) from an older compositor instance still owns `org.freedesktop.Notifications`. Kill it and start it from the current session. |
| **Load unpacked** freezes the browser (Hyprland etc.) | `xdg-desktop-portal` is attached to a different/stale Wayland session, so the file picker opens where you can't see it. Run `systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal`. |

Relay log: `C:\icloud-relay\relay.log`. To trace message types (command
numbers only, never payloads), create an empty `C:\icloud-relay\debug` file and
redeploy.

Quick end-to-end test from Linux: send `{"cmd":14}` (CmdHello) through
`icloud-pw-shim`, framed as a 4-byte little-endian length followed by the JSON.
It should reply with a `capabilities` object.

## Notes

- **Extension updates:** the patched copy doesn't auto-update. Re-run
  `linux/patch-extension.py` to pick up a new version; it fails loudly if the
  code it patches has changed.
- **Security:** the relay listens only on `127.0.0.1` inside the VM. The only
  way to reach it is SSH with your key. Anyone who can use that key can reach
  your password helper, which still requires pairing with a code shown on the
  Windows desktop.
- **Why not run the helper straight from SSH?** A Windows SSH login with a key
  has no access to the user's DPAPI keys or desktop session, so the helper
  answers "re-login needed". It has to run inside the logged-in session.
- **Why a custom byte pump?** `Stream.CopyToAsync` into the helper's stdin
  never flushes (a buffered `FileStream`), so small native messages get stuck.
  The relay flushes after every chunk.

## License

MIT
