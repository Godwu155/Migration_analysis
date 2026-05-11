from __future__ import annotations

import shutil
import tempfile
import zipfile
from pathlib import Path

PPTX = Path("D:/migration_project/presentation_work/output/curlew_migration_report.pptx")

with tempfile.NamedTemporaryFile(delete=False, suffix=".pptx") as tmp:
    tmp_path = Path(tmp.name)

with zipfile.ZipFile(PPTX, "r") as zin, zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        if item.is_dir():
            continue
        data = zin.read(item.filename)
        zout.writestr(item.filename, data)

shutil.move(tmp_path, PPTX)
print(f"Normalized PPTX zip entries: {PPTX}")
