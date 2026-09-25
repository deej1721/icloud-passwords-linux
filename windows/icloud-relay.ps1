# Bridge Chromium on the Linux host to Apple's iCloud Passwords
# native-messaging helper. Listens on loopback only (the host reaches it with
# `ssh -W`), and per connection starts the helper and pipes raw stdio both ways.
# Must run in the user's interactive session (scheduled task) - the helper needs the
# logged-on user's iCloud/DPAPI context, which an SSH logon doesn't have.
$ErrorActionPreference = 'Stop'
$port   = 47811
$helper = "$env:LOCALAPPDATA\Microsoft\WindowsApps\iCloudPasswordsExtensionHelper.exe"  # App Execution Alias, survives Store updates
$origin = 'chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/'
$log    = "$PSScriptRoot\relay.log"

function Log($m) { Add-Content $log "$(Get-Date -Format s) $m" }

# Stream.CopyToAsync doesn't flush, and the helper's stdin is a buffered
# FileStream, so small native messages would sit in its 4 KB buffer forever.
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Threading.Tasks;
public static class Pump {
    public static string LogPath;  // set to log each message's cmd (never payloads)
    public static async Task Run(Stream src, Stream dst, string dir) {
        var buf = new byte[65536]; int n; var pending = new MemoryStream();
        while ((n = await src.ReadAsync(buf, 0, buf.Length)) > 0) {
            await dst.WriteAsync(buf, 0, n); await dst.FlushAsync();
            if (LogPath != null) { pending.Write(buf, 0, n); Trace(pending, dir); }
        }
    }
    static void Trace(MemoryStream ms, string dir) {
        var b = ms.ToArray(); int off = 0;
        while (b.Length - off >= 4) {
            int len = BitConverter.ToInt32(b, off);
            if (b.Length - off - 4 < len) break;
            var json = Encoding.UTF8.GetString(b, off + 4, len);
            var m = System.Text.RegularExpressions.Regex.Match(json, "\"cmd\"\\s*:\\s*(\\d+)");
            var q = System.Text.RegularExpressions.Regex.Match(json, "\"(QID|MSG|STATUS)\"\\s*:\\s*\"?([A-Za-z0-9]{1,8})");
            lock (typeof(Pump)) File.AppendAllText(LogPath, DateTime.Now.ToString("s") + " " + dir + " cmd=" + (m.Success ? m.Groups[1].Value : "?") + (q.Success ? " " + q.Groups[1].Value + "=" + q.Groups[2].Value : "") + " len=" + len + Environment.NewLine);
            off += 4 + len;
        }
        ms.SetLength(0); ms.Write(b, off, b.Length - off);
    }
}
'@
if (Test-Path "$PSScriptRoot\debug") { [Pump]::LogPath = $log }  # create C:\icloud-relay\debug to trace

# The helper shows the pairing code in its own dialog, positioned next to the
# taskbar. A WinApps RemoteApp session has no real taskbar, so the dialog stays
# hidden off-screen - but its text is still readable. Copy each new code to
# pin.log, which the Linux side tails to show a notification.
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class PinDialog {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    static readonly System.Text.RegularExpressions.Regex Code = new System.Text.RegularExpressions.Regex(@"^\d{3} ?\d{3}$");
    // Returns the code shown by any dialog (#32770) owned by one of pids, or null.
    public static string Find(HashSet<uint> pids) {
        string found = null;
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            var cls = new StringBuilder(64); GetClassName(h, cls, 64);
            if (!pids.Contains(pid) || cls.ToString() != "#32770") return true;
            EnumChildWindows(h, (c, l2) => {
                var t = new StringBuilder(64); GetWindowText(c, t, 64);
                if (Code.IsMatch(t.ToString().Trim())) { found = t.ToString().Trim(); return false; }
                return true;
            }, IntPtr.Zero);
            return found == null;
        }, IntPtr.Zero);
        return found;
    }
}
'@
$pinLog = "$PSScriptRoot\pin.log"
Set-Content $pinLog $null   # codes are single-use; don't keep old ones around
$lastPin = $null

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
$listener.Start()
Log "listening on 127.0.0.1:$port"

$sessions = [Collections.Generic.List[object]]::new()
$accept = $listener.AcceptTcpClientAsync()
while ($true) {
    if ($accept.Wait(1000)) {
        $client = $accept.Result
        $accept = $listener.AcceptTcpClientAsync()
        try {
            $psi = [Diagnostics.ProcessStartInfo]::new($helper, "$origin --parent-window=0")
            $psi.UseShellExecute = $false
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.CreateNoWindow = $true
            $proc = [Diagnostics.Process]::Start($psi)
            $net  = $client.GetStream()
            $sessions.Add([pscustomobject]@{
                Client = $client; Proc = $proc
                Up     = [Pump]::Run($net, $proc.StandardInput.BaseStream, '>')    # Chromium -> helper
                Down   = [Pump]::Run($proc.StandardOutput.BaseStream, $net, '<')  # helper -> Chromium
            })
            Log "session start pid=$($proc.Id)"
        } catch {
            Log "spawn failed: $_"
            $client.Close()
        }
    }
    # Tear down sessions where either side has gone away.
    foreach ($s in @($sessions)) {
        if ($s.Up.IsCompleted -or $s.Down.IsCompleted -or $s.Proc.HasExited) {
            try { if (-not $s.Proc.HasExited) { $s.Proc.Kill() } } catch {}
            $s.Client.Close()
            $sessions.Remove($s) | Out-Null
            Log "session end pid=$($s.Proc.Id)"
        }
    }
    if ($sessions.Count) {
        $pids = [Collections.Generic.HashSet[uint32]]::new()
        foreach ($s in $sessions) { [void]$pids.Add([uint32]$s.Proc.Id) }
        $pin = [PinDialog]::Find($pids)
        if ($pin -and $pin -ne $lastPin) { Add-Content $pinLog "$(Get-Date -Format s) $pin"; Log "pairing code shown" }
        $lastPin = $pin
    }
}
