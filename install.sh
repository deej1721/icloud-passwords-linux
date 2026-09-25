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
mkdir -p "$conf"
printf 'ICLOUD_PW_SSH_HOST=%s\nICLOUD_PW_PORT=47811\n' "$host" > "$conf/env"

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
