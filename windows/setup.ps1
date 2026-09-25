# Install the relay into C:\icloud-relay and run it at logon in
# the user's interactive session. Run over SSH by ../deploy.sh.
$ErrorActionPreference = 'Stop'
$dst  = 'C:\icloud-relay'
$user = "$env:COMPUTERNAME\$env:USERNAME"  # USERDOMAIN reads WORKGROUP under SSH
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Force "$PSScriptRoot\icloud-relay.ps1", "$PSScriptRoot\run-hidden.vbs", "$PSScriptRoot\test-helper.ps1", "$PSScriptRoot\pin-follow.ps1" $dst

$action    = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$dst\run-hidden.vbs`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'icloud-relay' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

# Restart so a re-run picks up script changes.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object CommandLine -like '*icloud-relay.ps1*' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-ScheduledTask -TaskName 'icloud-relay'
Start-Sleep -Seconds 5
if (Get-NetTCPConnection -LocalPort 47811 -State Listen -ErrorAction SilentlyContinue) { 'OK: relay listening on 127.0.0.1:47811' }
else { Write-Warning "relay not listening; see $dst\relay.log" }
