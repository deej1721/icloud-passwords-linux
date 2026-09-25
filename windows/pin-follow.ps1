# Stream new lines of pin.log to stdout (run over SSH by the Linux
# notifier). Get-Content -Wait missed the relay's writes, so poll the file
# ourselves; the relay truncates it on restart, so restart from 0 when it shrinks.
$path = "$PSScriptRoot\pin.log"
$pos = if (Test-Path $path) { (Get-Item $path).Length } else { 0 }
$out = [Console]::Out
while ($true) {
    if (Test-Path $path) {
        $f = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            if ($f.Length -lt $pos) { $pos = 0 }
            if ($f.Length -gt $pos) {
                $f.Position = $pos
                $r = [IO.StreamReader]::new($f)
                $text = $r.ReadToEnd(); $pos = $f.Length
                foreach ($l in $text -split "`r?`n") { if ($l) { $out.WriteLine($l) } }
                $out.Flush()
            }
        } finally { $f.Dispose() }
    }
    Start-Sleep -Milliseconds 500
}
