from __future__ import annotations

import shutil
import sys
import tempfile
import zipfile
from pathlib import Path


PROJECT = Path("D:/migration_project")
PPTX = PROJECT / "presentation_work" / "output" / "curlew_migration_report.pptx"

MEDIA = [
    PROJECT / "output" / "figures" / "08_state_tracks.png",
    PROJECT / "output" / "figures" / "08_state_tracks.png",
    PROJECT / "output" / "figures" / "10b_log_duration_histogram.png",
    PROJECT / "output" / "figures" / "10b_duration_boxplot.png",
    PROJECT / "output" / "figures" / "10b_ndvi_vs_log_duration.png",
    PROJECT / "output" / "figures" / "10b_wind_vs_log_duration.png",
    PROJECT / "output" / "figures" / "10_optimal_stopping_pred_obs.png",
    PROJECT / "output" / "figures" / "11_climate_scenario_projection.png",
    PROJECT / "output" / "figures" / "12_scvi_ranking_bar.png",
    PROJECT / "output" / "figures" / "12_scvi_stopover_map.png",
]


def media_entry_name(index: int) -> str:
    if index == 0:
        return "ppt/media/image.png"
    return f"ppt/media/image{index + 1}.png"


def main() -> int:
    if not PPTX.exists():
        print(f"Missing PPTX: {PPTX}", file=sys.stderr)
        return 1

    for source in MEDIA:
        if not source.exists() or source.stat().st_size == 0:
            print(f"Missing or empty image source: {source}", file=sys.stderr)
            return 1

    replacements = {media_entry_name(i): MEDIA[i].read_bytes() for i in range(len(MEDIA))}
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pptx") as tmp:
        tmp_path = Path(tmp.name)

    with zipfile.ZipFile(PPTX, "r") as zin, zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        seen = set()
        for item in zin.infolist():
            seen.add(item.filename)
            data = replacements.get(item.filename)
            if data is None:
                data = zin.read(item.filename)
            zout.writestr(item, data)

        for entry, data in replacements.items():
            if entry not in seen:
                zout.writestr(entry, data)

    shutil.move(tmp_path, PPTX)
    print(f"Patched {len(replacements)} media files in {PPTX}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
