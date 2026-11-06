"""Deploy the validated candidate to the explicitly authorized single-player save.

Does not start the game, change sandbox settings, initialize Git, or publish.
Run only while the game is closed; the calling PowerShell checks processes.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
USER = Path(r"C:\Users\15792\Zomboid")
MOD = ROOT / "mods/SuQingFreshnessFridge"
TARGET = USER / "mods/SuQingFreshnessFridge"
SAVE = USER / "Saves/Sandbox/2026-10-09_18-19-22"
MODS_FILE = SAVE / "mods.txt"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def manifest(folder):
    return {p.relative_to(folder).as_posix(): sha(p) for p in sorted(folder.rglob("*")) if p.is_file()}

def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

parser = argparse.ArgumentParser()
parser.add_argument("task", type=Path)
args = parser.parse_args()
task = args.task.resolve(strict=True)
assert task.parent == GAME / "CodexAssets/SuQingFreshnessFridge_20261105"
assert (USER / "latestSave.ini").read_text(encoding="utf-8-sig").splitlines() == [SAVE.name, "Sandbox"]
assert not TARGET.exists(), "Refuse to overwrite an existing personal installation"
assert not (task / "deployment.json").exists(), "This deployment was already recorded"
baseline = json.loads((task / "validation/offline_validation.json").read_text(encoding="utf-8"))
assert baseline["result"] == "PASS"
current = manifest(MOD)
validated = baseline["source_manifest"]
changed = sorted(k for k in set(current) | set(validated) if current.get(k) != validated.get(k))
assert changed == ["42/icon.png"], "Only the independently generated icon may change after validation: " + str(changed)
assert sha(MOD / "42/poster.png") == sha(ROOT / "art/cover-candidates_20261105/B_夜间工坊.png")
for size in (64, 128, 256):
    with Image.open(ROOT / f"art/icon-exports/icon-{size}.png") as icon:
        icon.load()
        assert icon.format == "PNG" and icon.size == (size, size)
assert sha(MOD / "42/icon.png") == sha(ROOT / "art/icon-exports/icon-128.png")
write_json(task / "icon-final-validation.json", {
    "result": "PASS", "changes_since_full_offline_validation": changed,
    "unchanged_runtime_code_and_building_assets": True,
    "dedicated_icon_source": str(ROOT / "art/icon-source.png"),
    "dedicated_icon_sha256": sha(ROOT / "art/icon-source.png"),
    "runtime_icon_size": [128, 128], "preview_sizes": [64, 128, 256],
    "visual_acceptance": "64px and 128px previews inspected: fridge, rewind clock and apple remain distinct; no title or scene clutter.",
    "generation_record": str(ROOT / "art/icon-generation.json"),
    "final_source_manifest": current,
})

spec = importlib.util.spec_from_file_location("freshness_release", ROOT / "tools/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
protected_before = release.protected()
validated_protection = json.loads((task / "validation/protected_after.json").read_text(encoding="utf-8"))["files"]
assert protected_before == validated_protection, "Protected profile files changed since validation; recheck before deployment"
before = MODS_FILE.read_bytes()
assert b"SuQingFreshnessFridge" not in before
block = re.search(rb"(?ms)(^mods[ \t]*\r?\n\{[ \t]*\r?\n.*?)(^\})", before)
assert block, "Unrecognized save mods.txt grammar"
newline = b"\r\n" if b"\r\n" in before else b"\n"
addition = b"    mod = SuQingFreshnessFridge," + newline
after = before[:block.end(1)] + addition + before[block.end(1):]
id_pattern = rb"(?m)^[ \t]*mod[ \t]*=[ \t]*([^,\r\n]+),"
before_ids = re.findall(id_pattern, before)
after_ids = re.findall(id_pattern, after)
assert after_ids == before_ids + [b"SuQingFreshnessFridge"]
assert after[:block.end(1)] + after[block.end(1) + len(addition):] == before

backup_dir = task / "config-backup"
backup_dir.mkdir()
backup = backup_dir / "save-mods.txt.before"
shutil.copy2(MODS_FILE, backup)
assert backup.read_bytes() == before
write_json(backup_dir / "receipt.json", {
    "scope": "Exact save mod-list configuration only; not a complete world backup",
    "source": str(MODS_FILE), "backup": str(backup), "sha256": sha(backup),
    "bytes": len(before), "verified": True,
})
frozen = task / "frozen/mods/SuQingFreshnessFridge"
shutil.copytree(MOD, frozen)
assert manifest(frozen) == current
shutil.copytree(frozen, TARGET)
assert manifest(TARGET) == current
assert MODS_FILE.read_bytes() == before, "Save mod list changed while copying"
with tempfile.NamedTemporaryFile(dir=SAVE, prefix=".suqing-fridge-", suffix=".tmp", delete=False) as output:
    output.write(after)
    output.flush()
    os.fsync(output.fileno())
    temporary = Path(output.name)
os.replace(temporary, MODS_FILE)
assert MODS_FILE.read_bytes() == after
protected_after = release.protected()
profile_changes = sorted(k for k in protected_before if protected_before[k] != protected_after[k])
assert profile_changes == [str(MODS_FILE)]
previous_frozen = GAME / "CodexAssets/SuQingFreshnessFridge_20261105/release/mods/SuQingFreshnessFridge"
previous_manifest = manifest(previous_frozen)
release_changes = sorted(k for k in set(current) | set(previous_manifest) if current.get(k) != previous_manifest.get(k))
report = {
    "checkedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
    "result": "PASS", "version": "0.1.0-rc.1", "mod_id": "SuQingFreshnessFridge",
    "source": str(MOD), "frozen_candidate": str(frozen), "installed": str(TARGET),
    "enabled_save": str(SAVE), "mod_list": str(MODS_FILE),
    "original_mod_count": len(before_ids), "new_mod_count": len(after_ids),
    "original_order_preserved": True, "added_only": ["SuQingFreshnessFridge"],
    "default_mod_list_unchanged": True, "sandbox_bin_unchanged": True,
    "protected_file_changes": profile_changes, "runtime_files_verified": len(current),
    "original_mod_list_backup": str(backup), "world_backup_created": False,
    "changes_from_original_frozen_candidate": release_changes,
    "final_source_manifest": current,
    "full_offline_validation": str(task / "validation/offline_validation.json"),
    "post_icon_validation": str(task / "icon-final-validation.json"),
    "game_started": False, "in_game_tested": False, "git_changed": False,
    "workshop_published": False, "workshop_originals_modified": False,
}
write_json(task / "deployment.json", report)
print(json.dumps({k: report[k] for k in ["result", "enabled_save", "installed", "original_mod_count", "new_mod_count", "runtime_files_verified", "original_order_preserved"]}, ensure_ascii=False))
