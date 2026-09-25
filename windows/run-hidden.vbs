' Start the relay without a console window (it would otherwise show
' up on the Linux desktop as a WinApps RemoteApp window).
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""C:\icloud-relay\icloud-relay.ps1""", 0, False
