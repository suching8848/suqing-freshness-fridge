"""Reproduce runtime checks without starting Project Zomboid or loading any save."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"D:\steam\steamapps\common\ProjectZomboid")
JDK = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin")
JAVA = GAME / "jre64/bin/java.exe"
TESTS = ROOT / "tests"
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-only", action="store_true")
    parser.add_argument("--output", type=Path, default=TESTS,
                        help="Directory for reports, logs, helper classes and isolated profiles")
    parser.add_argument("--lunchbox-repo", type=Path,
                        help="Also run the shared-lock integration and native serializer probes")
    parser.add_argument("--livewire-upstream", type=Path, action="append", default=[],
                        help="Test an unmodified Live Wire release directory containing mod.info and media")
    args = parser.parse_args()
    if args.native_only and (args.lunchbox_repo or args.livewire_upstream):
        parser.error("--lunchbox-repo and --livewire-upstream require the full suite")
    output = args.output.resolve()
    logs = output / "runtime_validation"
    classes = output / "runtime_classes"
    logs.mkdir(parents=True, exist_ok=True)
    classes.mkdir(exist_ok=True)

    def run(name, command, home=None):
        env = os.environ.copy()
        if home is not None:
            home.mkdir(exist_ok=True)
            env["USERPROFILE"] = str(home)
            env["APPDATA"] = str(home / "AppData" / "Roaming")
            env["LOCALAPPDATA"] = str(home / "AppData" / "Local")
        process = subprocess.run([str(part) for part in command], cwd=GAME, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        text = process.stdout.decode("utf-8", errors="replace")
        log = logs / (name + ".log")
        log.write_text(text, encoding="utf-8")
        if process.returncode:
            raise AssertionError(name + " failed; see " + str(log) + "\n" + text[-3000:])
        return text

    jar = GAME / "projectzomboid.jar"
    classpath = os.pathsep.join(map(str, (classes, jar, GAME / "*")))

    def java(name, runner, *files):
        home = output / ("runtime_" + name + "_home")
        return run(name, [JAVA, "-XX:-UsePerfData", "--enable-native-access=ALL-UNNAMED",
                          "-Duser.home=" + str(home), "-cp", classpath, runner, *files], home)

    run("native_audit", [sys.executable, ROOT / "tools/runtime_native_audit.py", "--output", output])
    run("compile", [JDK / "javac.exe", "-encoding", "UTF-8", "-d", classes,
                    TESTS / "runtime_KahluaAudit.java", TESTS / "runtime_NativeShieldProbe.java",
                    ROOT / "tools/ReleaseLuaCompile.java"])
    lua = ROOT / "mods/SuQingFreshnessFridge/42/media/lua"
    core = lua / "shared/SuQingFreshnessFridge/Core.lua"
    batch = lua / "shared/SuQingFreshnessFridge/Batch.lua"
    runtime = lua / "client/SuQingFreshnessFridge_Runtime.lua"
    lock = lua / "client/SuQingFreshnessFridge_Lock.lua"
    ui = lua / "client/SuQingFreshnessFridge_UI.lua"
    native_files = []
    if not args.native_only:
        native_files = [TESTS / "runtime_native_core_bootstrap.lua", core, TESTS / "runtime_native_core_cases.lua",
                        TESTS / "runtime_native_capacity_bootstrap.lua", lua / "shared/SuQingFreshnessFridge/Capacity.lua",
                        TESTS / "runtime_native_capacity_cases.lua"]
    native = java("native_shield", "runtime_NativeShieldProbe", *native_files)
    match = re.search(r"NATIVE_SHIELD passes=(\d+) assertions=(\d+).* PASS", native)
    if not match:
        raise AssertionError("native shield summary is missing")
    result = {
        "result": "PASS",
        "native_control_flow_checks": len(json.loads((output / "runtime_native_audit.json").read_text(encoding="utf-8"))["checks"]),
        "native_guard_passes": int(match.group(1)),
        "native_guard_assertions": int(match.group(2)),
        "game_started": False,
        "world_created": False,
        "in_game_tested": False,
        "game_jar_sha256": hashlib.sha256(jar.read_bytes()).hexdigest(),
        "source_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in (core, batch, runtime, lock, ui)},
    }
    if not args.native_only:
        display = re.search(r"NATIVE_DISPLAY_GUARD cases=(\d+) assertions=(\d+) native_updates=(\d+) failures=0", native)
        if not display:
            raise AssertionError("native Food display and replacement guard regression summary is missing")
        result["native_display_cases"] = int(display.group(1))
        result["native_display_assertions"] = int(display.group(2))
        result["native_display_rot_updates"] = int(display.group(3))
        precision = re.search(r"NATIVE_CORE_PRECISION cases=(\d+) passes=(\d+) assertions=(\d+) failures=0", native)
        if not precision:
            raise AssertionError("native Food precision regression summary is missing")
        result["native_precision_cases"] = int(precision.group(1))
        result["native_precision_passes"] = int(precision.group(2))
        result["native_precision_assertions"] = int(precision.group(3))
        capacity = re.search(r"NATIVE_CAPACITY_BRIDGE cases=(\d+) assertions=(\d+) failures=0", native)
        if not capacity:
            raise AssertionError("native capacity bridge regression summary is missing")
        result["native_capacity_cases"] = int(capacity.group(1))
        result["native_capacity_assertions"] = int(capacity.group(2))
        lua_files = sorted(lua.rglob("*.lua"))
        java("lua_compile", "ReleaseLuaCompile", *lua_files)
        result["lua_compiled"] = len(lua_files)
        bootstrap = TESTS / "runtime_mock_bootstrap.lua"
        model = java("kahlua_runtime", "runtime_KahluaAudit", bootstrap, core, batch, runtime,
                     TESTS / "runtime_batch_cases.lua")
        totals = re.search(r"RUNTIME_FRIDGE_BATCH cases=(\d+) assertions=(\d+) failures=0", model)
        if not totals:
            raise AssertionError("runtime model summary is missing")
        result["runtime_model_cases"] = int(totals.group(1))
        result["runtime_model_assertions"] = int(totals.group(2))
        lock_log = java("kahlua_lock", "runtime_KahluaAudit", bootstrap, core, batch, lock, ui,
                        TESTS / "runtime_batch_lock_cases.lua")
        lock_checks = re.search(r"FRIDGE_BATCH_LOCK checks=(\d+) shared=false PASS", lock_log)
        if not lock_checks:
            raise AssertionError("standalone lock summary is missing")
        result["lock_assertions"] = int(lock_checks.group(1))
        if args.livewire_upstream:
            result["livewire"] = {}
        for upstream in args.livewire_upstream:
            upstream = upstream.resolve()
            info = (upstream / "mod.info").read_text(encoding="utf-8-sig")
            version_match = re.search(r"(?m)^modversion=(1\.7\.2|2\.0\.[0123]|2\.1\.[01234568]|2\.2\.0)\s*$", info)
            if not version_match:
                raise AssertionError(f"Unsupported Live Wire test input: {upstream}")
            version = version_match.group(1)
            shared = upstream / "media/lua/shared/LiveWire"
            server = upstream / "media/lua/server/LiveWire"
            modules = ["LW_Core", "LW_Compat", "LW_SquareScan", "LW_ServiceSync"]
            if version != "1.7.2":
                modules.extend(("LW_Extension", "LW_Coverage", "LW_EventBus", "LW_ApplianceFamilies"))
            if version in ("2.1.0", "2.1.1", "2.1.2", "2.1.3", "2.1.4", "2.1.5", "2.1.6", "2.1.8", "2.2.0"):
                modules.append("LW_Consumers")
            modules.extend(("LW_Anchor", "LW_Appliances"))
            wire_log = java(f"livewire_{version}", "runtime_KahluaAudit",
                            bootstrap, TESTS / "runtime_livewire_fixture.lua",
                            *(shared / f"{name}.lua" for name in modules),
                            server / "LW_FridgeCatchup.lua", server / "LW_ChunkSync.lua",
                            core, batch, runtime, TESTS / "runtime_livewire_cases.lua")
            wire_checks = re.search(r"RUNTIME_FRIDGE_LIVEWIRE version=([0-9.]+) assertions=(\d+) PASS", wire_log)
            if not wire_checks:
                raise AssertionError(f"Live Wire {version} summary is missing")
            expected_runtime = "2.0.0" if version == "2.0.1" else version
            if wire_checks.group(1) != expected_runtime:
                raise AssertionError(f"Unexpected Live Wire runtime for package {version}: {wire_checks.group(1)}")
            result["livewire"][version] = {
                "lua_version": wire_checks.group(1),
                "assertions": int(wire_checks.group(2)),
            }
        if args.lunchbox_repo:
            lunchbox = args.lunchbox_repo.resolve()
            other = lunchbox / "mods/SuQingFreshnessLunchbox/42/media/lua"
            shared_log = java("combined", "runtime_KahluaAudit", bootstrap, core, batch, lock, runtime,
                              other / "shared/SuQingFreshnessLunchbox/Core.lua",
                              other / "shared/SuQingFreshnessLunchbox/Batch.lua",
                              other / "client/SuQingFreshnessLunchbox_Lock.lua",
                              other / "client/SuQingFreshnessLunchbox_Runtime.lua",
                              TESTS / "runtime_batch_combined_cases.lua")
            shared = re.search(r"RUNTIME_FRIDGE_LUNCHBOX_BATCH assertions=(\d+) PASS", shared_log)
            if not shared:
                raise AssertionError("shared fridge/lunchbox runtime summary is missing")
            result["combined_assertions"] = int(shared.group(1))
            run("compile_serializer", [JDK / "javac.exe", "-encoding", "UTF-8", "-d", classes,
                                       lunchbox / "tools/runtime_NativeProbe.java"])
            serialized_log = java("native_batch", "runtime_NativeProbe",
                                  lunchbox / "tests/runtime_native_bootstrap.lua", core, batch,
                                  TESTS / "runtime_batch_native_cases.lua")
            serialized = re.search(r"RUNTIME_FRIDGE_BATCH_NATIVE cases=(\d+) assertions=(\d+) PASS", serialized_log)
            if not serialized:
                raise AssertionError("native batch serialization summary is missing")
            result["native_batch_cases"] = int(serialized.group(1))
            result["native_batch_assertions"] = int(serialized.group(2))
    (output / "runtime_validation_report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
