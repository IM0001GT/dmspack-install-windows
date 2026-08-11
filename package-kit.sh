#!/usr/bin/env bash
# Package the Windows DML installer kit (no .dmlpack payloads).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="${DMLPACK_WINDOWS_VERSION:-1.1.0}"
NAME="evejs-dmlpack-windows-v${VERSION}"
DIST="${REPO_ROOT}/dist"
STAGE="${DIST}/.stage-${NAME}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}/dmlpack-windows/launchers" "${DIST}"

cp -a \
  "${SCRIPT_DIR}/Install-DmlPack.portable.ps1" \
  "${SCRIPT_DIR}/dmlpack.py" \
  "${SCRIPT_DIR}/README.md" \
  "${SCRIPT_DIR}/GUIDE.md" \
  "${SCRIPT_DIR}/NOTICE.md" \
  "${SCRIPT_DIR}/package-kit.sh" \
  "${STAGE}/dmlpack-windows/"

cp -a "${SCRIPT_DIR}/launchers/." "${STAGE}/dmlpack-windows/launchers/"

cat > "${STAGE}/dmlpack-windows/INSTALL.txt" <<'EOF'
DML Pack installer for Windows
==============================

1. Install Docker Desktop (Linux containers) and Python 3.
2. Place this folder next to your .dmlpack files.
3. Right-click Install-DmlPack.portable.ps1 → Run with PowerShell
   or:  Set-ExecutionPolicy -Scope Process Bypass; .\Install-DmlPack.portable.ps1

See GUIDE.md. Never publish .dmlpack archives you do not own rights to share.
EOF

tar -C "${STAGE}" -czf "${DIST}/${NAME}.tar.gz" dmlpack-windows
(
  cd "${STAGE}"
  python3 - <<PY
import pathlib, zipfile
stage = pathlib.Path("${STAGE}")
out = pathlib.Path("${DIST}/${NAME}.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    root = stage / "dmlpack-windows"
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
