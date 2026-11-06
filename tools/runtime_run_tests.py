"""Reproduce runtime checks without starting Project Zomboid or loading any save."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"D:\steam\steamapps\common\ProjectZomboid")
JDK = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin")
JAVA = GAME / "jre64/bin/java.exe"
TESTS = ROOT / "tests"
LOGS = TESTS / "runtime_validation"


def run(name, command):
    result = subprocess.run([str(part) for part in command], cwd=GAME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    (LOGS / (name + ".log")).write_text(output, encoding="utf-8")
    if result.returncode:
        raise AssertionError(name + " failed; see " + str(LOGS / (name + ".log")) + "\n" + output[-3000:])
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-only", action="store_true")
    args = parser.parse_args()
    LOGS.mkdir(exist_ok=True)
    run("native_audit", [sys.executable, ROOT / "tools/runtime_native_audit.py"])
    run("compile", [JDK / "javac.exe", "-encoding", "UTF-8", TESTS / "runtime_KahluaAudit.java", TESTS / "runtime_NativeShieldProbe.java"])
    classpath = str(TESTS) + ";" + str(GAME / "projectzomboid.jar")
    lua = ROOT / "mods/SuQingFreshnessFridge/42/media/lua"
    native_command = [JAVA, "-Duser.home=" + str(TESTS / "runtime_native_home"), "-cp", classpath, "runtime_NativeShieldProbe"]
    if not args.native_only:
        native_command.extend([TESTS / "runtime_native_core_bootstrap.lua", lua / "shared/SuQingFreshnessFridge/Core.lua", TESTS / "runtime_native_core_cases.lua",
                               TESTS / "runtime_native_capacity_bootstrap.lua", lua / "shared/SuQingFreshnessFridge/Capacity.lua", TESTS / "runtime_native_capacity_cases.lua"])
    native = run("native_shield", native_command)
    match = re.search(r"NATIVE_SHIELD passes=(\d+) assertions=(\d+).* PASS", native)
    if not match:
        raise AssertionError("native shield summary is missing")
    result = {
        "result": "PASS",
        "native_control_flow_checks": len(json.loads((TESTS / "runtime_native_audit.json").read_text(encoding="utf-8"))["checks"]),
        "native_guard_passes": int(match.group(1)),
        "native_guard_assertions": int(match.group(2)),
        "game_started": False,
        "world_created": False,
        "in_game_tested": False,
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
        files = [TESTS / "runtime_mock_bootstrap.lua", lua / "shared/SuQingFreshnessFridge/Core.lua", lua / "client/SuQingFreshnessFridge_Runtime.lua", TESTS / "runtime_mock_cases.lua"]
        missing = [str(path) for path in files if not path.exists()]
        if missing:
            raise AssertionError("required runtime test files are missing: " + ", ".join(missing))
        model = run("kahlua_runtime", [JAVA, "-Duser.home=" + str(TESTS / "runtime_model_home"), "-cp", classpath, "runtime_KahluaAudit", *files])
        totals = re.search(r"RUNTIME_MODEL cases=(\d+) assertions=(\d+) failures=0", model)
        if not totals:
            raise AssertionError("runtime model summary is missing")
        result["runtime_model_cases"] = int(totals.group(1))
        result["runtime_model_assertions"] = int(totals.group(2))
    (TESTS / "runtime_validation_report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
