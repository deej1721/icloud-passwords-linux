#Requires -RunAsAdministrator
# Add Apple Root CA to the machine trust store. iCloud sign-in talks to
# gsa.apple.com, whose chain ends at Apple's private root; if Windows' root
# auto-update doesn't supply it, sign-in fails with SEC_E_UNTRUSTED_ROOT.
# Check first:  curl.exe -sI https://gsa.apple.com/
$ErrorActionPreference = 'Stop'
$sha256 = 'B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024'
$f = Join-Path $env:TEMP 'AppleIncRootCertificate.cer'
Invoke-WebRequest -UseBasicParsing https://www.apple.com/appleca/AppleIncRootCertificate.cer -OutFile $f
$x = [Security.Cryptography.X509Certificates.X509Certificate2]::new($f)
if ($x.GetCertHashString('SHA256') -ne $sha256) { throw "fingerprint mismatch: $($x.GetCertHashString('SHA256'))" }
Import-Certificate -FilePath $f -CertStoreLocation Cert:\LocalMachine\Root | Select-Object Thumbprint, Subject
