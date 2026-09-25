# Talk to the helper directly (no relay) - send CmdHello, print the reply.
param([int]$TimeoutSec = 10)
$helper = "$env:LOCALAPPDATA\Microsoft\WindowsApps\iCloudPasswordsExtensionHelper.exe"
$psi = [Diagnostics.ProcessStartInfo]::new($helper, 'chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/ --parent-window=0')
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
$msg = [Text.Encoding]::UTF8.GetBytes('{"cmd":14}')
$p.StandardInput.BaseStream.Write([BitConverter]::GetBytes([int]$msg.Length), 0, 4)
$p.StandardInput.BaseStream.Write($msg, 0, $msg.Length); $p.StandardInput.BaseStream.Flush()
$buf = New-Object byte[] 65536
$t = $p.StandardOutput.BaseStream.ReadAsync($buf, 0, $buf.Length)
if ($t.Wait($TimeoutSec * 1000) -and $t.Result -gt 0) {
    $n = [BitConverter]::ToInt32($buf, 0); "session $([Diagnostics.Process]::GetCurrentProcess().SessionId) REPLY ($n bytes): " + [Text.Encoding]::UTF8.GetString($buf, 4, [Math]::Min($n, $t.Result - 4))
} else { "session $([Diagnostics.Process]::GetCurrentProcess().SessionId) no reply in ${TimeoutSec}s; exited=$($p.HasExited) code=$(if($p.HasExited){$p.ExitCode})" }
$e = $p.StandardError.ReadToEndAsync(); if (-not $p.HasExited) { $p.Kill() }; if ($e.Wait(2000) -and $e.Result) { "stderr: $($e.Result)" }
