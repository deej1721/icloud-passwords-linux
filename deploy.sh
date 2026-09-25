#!/usr/bin/env bash
# Copy the relay into the Windows VM and (re)register its logon task.
# Usage: ./deploy.sh <ssh-host-alias-of-windows-vm>
set -euo pipefail
host=${1:?usage: ./deploy.sh <ssh host alias of the Windows VM>}
src="$(cd "$(dirname "$0")" && pwd)/windows"
ssh -o LogLevel=ERROR "$host" 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force C:\icloud-relay\setup | Out-Null"'
scp -q -o LogLevel=ERROR "$src"/{icloud-relay.ps1,run-hidden.vbs,setup.ps1,test-helper.ps1,pin-follow.ps1} "$host:C:/icloud-relay/setup/"
ssh -o LogLevel=ERROR "$host" 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\icloud-relay\setup\setup.ps1'
