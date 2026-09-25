#!/usr/bin/env python3
"""Download the iCloud Passwords extension from the Chrome Web Store and patch
it to run on Linux, writing an unpacked copy to load via chrome://extensions.

The extension refuses to call its native host unless the user agent says
Windows or macOS (checkForValidOS). The patch makes that check pass. The
manifest's "key" is kept, so the extension ID - which the native-messaging
manifest's allowed_origins depends on - stays the same.
"""
import base64, hashlib, io, json, re, shutil, sys, urllib.request, zipfile
from pathlib import Path

EXT_ID = "pejdijmoenmkgeppbflobdenhhabjlaj"
CRX_URL = ("https://clients2.google.com/service/update2/crx?response=redirect"
           "&prodversion=999.0&acceptformat=crx2,crx3"
           f"&x=id%3D{EXT_ID}%26uc")

def main(dest: Path) -> None:
    crx = urllib.request.urlopen(CRX_URL).read()
    zip_start = crx.find(b"PK\x03\x04")          # skip the CRX header
    if zip_start < 0:
        sys.exit("download is not a CRX")
    if dest.exists():
        shutil.rmtree(dest)
    zipfile.ZipFile(io.BytesIO(crx[zip_start:])).extractall(dest)
    shutil.rmtree(dest / "_metadata", ignore_errors=True)  # unpacked loads reject it

    bg = dest / "background.js"
    src = bg.read_text()
    patched, n = re.subn(r"function checkForValidOS\(\)\{",
                         "function checkForValidOS(){return!0;", src, count=1)
    if n != 1:
        sys.exit("checkForValidOS() not found - the extension changed; patch needs updating")
    bg.write_text(patched)

    mf_path = dest / "manifest.json"
    mf = json.loads(mf_path.read_text())
    mf.pop("update_url", None)                     # the Web Store must not replace it
    mf["version_name"] = mf["version"] + " (linux patch)"
    mf_path.write_text(json.dumps(mf, indent=2))

    key = base64.b64decode(mf["key"])
    ext_id = "".join(chr(ord("a") + int(c, 16)) for c in hashlib.sha256(key).hexdigest()[:32])
    if ext_id != EXT_ID:
        sys.exit(f"unexpected extension ID {ext_id}")
    print(f"patched iCloud Passwords {mf['version']} -> {dest} (ID {ext_id})")

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else
              Path.home() / ".local/share/icloud-pw/extension").expanduser())
