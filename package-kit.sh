#!/usr/bin/env bash
# Package the Windows DML installer kit (no .dmlpack payloads).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="${DMLPACK_WINDOWS_VERSION:-1.1.4}"
NAME="dmspack-install-windows-v${VERSION}"
DIST="${REPO_ROOT}/dist"
STAGE="${DIST}/.stage-${NAME}"

# PowerShell 5.1 mangles UTF-8 without BOM; keep launcher bodies ASCII-only so
# even a stripped BOM cannot reintroduce the â€" parse failure.
python3 - "$SCRIPT_DIR" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
bad = []
for p in sorted((root / "launchers").glob("*.ps1")):
    data = p.read_bytes()
    body = data[3:] if data.startswith(b"\xef\xbb\xbf") else data
    if any(b > 127 for b in body):
        bad.append(p.name)
if bad:
    raise SystemExit(
        "launcher scripts must be ASCII-only (no em-dashes etc.): " + ", ".join(bad)
    )
print("launcher ASCII check OK")
PY

rm -rf "${STAGE}"
mkdir -p "${STAGE}/dmspack-install-windows/launchers" "${DIST}"

cp -a \
  "${SCRIPT_DIR}/Install-DmsPack.portable.ps1" \
  "${SCRIPT_DIR}/dmlpack.py" \
  "${SCRIPT_DIR}/README.md" \
  "${SCRIPT_DIR}/GUIDE.md" \
  "${SCRIPT_DIR}/NOTICE.md" \
  "${SCRIPT_DIR}/package-kit.sh" \
  "${STAGE}/dmspack-install-windows/"

cp -a "${SCRIPT_DIR}/launchers/." "${STAGE}/dmspack-install-windows/launchers/"

cat > "${STAGE}/dmspack-install-windows/INSTALL.txt" <<'EOF'
DMS Pack installer for Windows (dmspack-install-windows)
==============================

1. Install Docker Desktop (Linux containers) and Python 3.
2. Place this folder next to your .dmlpack files.
3. Right-click Install-DmsPack.portable.ps1 -> Run with PowerShell
   or:  Set-ExecutionPolicy -Scope Process Bypass; .\Install-DmsPack.portable.ps1

See GUIDE.md. Never publish .dmlpack archives you do not own rights to share.
EOF

tar -C "${STAGE}" -czf "${DIST}/${NAME}.tar.gz" dmspack-install-windows
(
  cd "${STAGE}"
  python3 - <<PY
import pathlib, zipfile
stage = pathlib.Path("${STAGE}")
out = pathlib.Path("${DIST}/${NAME}.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    root = stage / "dmspack-install-windows"
    for path in root.rglob("*"):
        if path.is_file():
            zf.write(path, path.relative_to(stage).as_posix())
print(out)
PY
)
(
  cd "${DIST}"
  sha256sum "${NAME}.tar.gz" > "${NAME}.tar.gz.sha256"
  sha256sum "${NAME}.zip" > "${NAME}.zip.sha256"
)
rm -rf "${STAGE}"
echo "Wrote ${DIST}/${NAME}.tar.gz and .zip"
