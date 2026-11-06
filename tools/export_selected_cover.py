"""Export the user's selected B cover without altering its artwork or original."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/cover-candidates_20261105"
MOD = ROOT / "mods/SuQingFreshnessFridge/42"
SOURCE = ART / "B_夜间工坊.png"
ICON_SOURCE = ROOT / "art/icon-source.png"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

with Image.open(SOURCE) as original:
    assert original.format == "PNG" and original.size == (1254, 1254)
with Image.open(ICON_SOURCE) as icon_original:
    assert icon_original.format == "PNG" and icon_original.width == icon_original.height
    exports = ROOT / "art/icon-exports"
    exports.mkdir(exist_ok=True)
    for size in (64, 128, 256):
        icon = icon_original.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        icon.save(exports / ("icon-" + str(size) + ".png"))
        if size == 128:
            icon.save(MOD / "icon.png")
shutil.copy2(SOURCE, MOD / "poster.png")
assert sha(SOURCE) == sha(MOD / "poster.png")
manifest_path = ART / "candidate-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest.update({
    "status": "selected",
    "selected": str(SOURCE),
    "selected_sha256": sha(SOURCE),
    "selection_evidence": "User chose B in chat 01a1ab48-f69a-7c71-af61-c48b69223c67 on 2026-11-05.",
    "exportedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
    "existing_poster_replaced": True,
    "poster": {"path": str(MOD / "poster.png"), "size": [1254, 1254], "sha256": sha(MOD / "poster.png")},
    "icon": {"path": str(MOD / "icon.png"), "size": [128, 128], "sha256": sha(MOD / "icon.png")},
    "original_art_preserved": str(ROOT / "art/cover-original.png"),
    "icon_source": str(ICON_SOURCE),
    "icon_source_sha256": sha(ICON_SOURCE),
    "processing": "Exact B poster copy. Icon independently generated for small-size recognition; icon exports come from the dedicated icon artwork, never the cover."
})
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Selected B poster and independently generated 128px icon exported; originals retained.")
