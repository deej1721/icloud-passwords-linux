#!/usr/bin/env bash
# Install the Linux side: shim, config, native-messaging manifests, and a
# patched unpacked copy of the iCloud Passwords extension.
# Usage: ./install.sh <ssh-host-alias-of-windows-vm>
set -euo pipefail
host=${1:?usage: ./install.sh <ssh host alias of the Windows VM>}
here=$(cd "$(dirname "$0")" && pwd)
bin="$HOME/.local/bin"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/icloud-pw"
ext="$HOME/.local/share/icloud-pw/extension"

install -Dm755 "$here/linux/icloud-pw-shim" "$bin/icloud-pw-shim"
install -Dm755 "$here/linux/icloud-pw-pin-notify" "$bin/icloud-pw-pin-notify"
mkdir -p "$conf"
printf 'ICLOUD_PW_SSH_HOST=%s\nICLOUD_PW_PORT=47811\n' "$host" > "$conf/env"

# Pairing codes -> desktop notification + clipboard (needed for WinApps
# RemoteApp sessions, where the code dialog is never shown).
install -Dm644 "$here/linux/icloud-pw-pin.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/icloud-pw-pin.service"
systemctl --user daemon-reload
systemctl --user enable --now icloud-pw-pin.service

# Register the native host for every Chromium-family browser config that exists.
for d in chromium google-chrome google-chrome-beta BraveSoftware/Brave-Browser vivaldi; do
    [ -d "$HOME/.config/$d" ] || continue
    mkdir -p "$HOME/.config/$d/NativeMessagingHosts"
    cat > "$HOME/.config/$d/NativeMessagingHosts/com.apple.passwordmanager.json" <<JSON
{
  "name": "com.apple.passwordmanager",
  "description": "iCloud Passwords helper, relayed to a Windows VM",
  "path": "$bin/icloud-pw-shim",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"]
}
JSON
    echo "registered native host for ~/.config/$d"
done

python3 "$here/linux/patch-extension.py" "$ext"
ln -sfn "$ext" "$HOME/icloud-pw-extension"   # non-hidden path for the Load unpacked picker
echo "Load unpacked in chrome://extensions: ~/icloud-pw-extension"
