"""Offline validation and a non-installing, verified candidate package."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r"D:\steam\steamapps\common\ProjectZomboid")
USER=Path(r"C:\Users\15792\Zomboid")
ARTIFACT=GAME/"CodexAssets/SuQingFreshnessFridge_20261105"
MOD=ROOT/"mods/SuQingFreshnessFridge"
VALIDATION=ARTIFACT/"validation"
JAVA=GAME/"jre64/bin/java.exe"
JDK=Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64/bin")
VERSION="0.1.0-rc.2"

def stamp(): return datetime.now(timezone(timedelta(hours=8))).isoformat()
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def protected():
    files=[USER/"LatestSave.ini",USER/"mods/default.txt",USER/"Saves/Sandbox/2026-10-09_18-19-22/mods.txt",
           USER/"Saves/Sandbox/2026-10-09_18-19-22/map_sand.bin",USER/"options.ini",USER/"pzopt/options.ini",
           GAME/"ProjectZomboid64.json",GAME/"projectzomboid.jar",GAME/"media/newtiledefinitions.tiles.txt",
           GAME/"media/scripts/generated/items/moveable.txt"]
    files.extend(USER/"mods/PZVoxelStudioViewpoint"/p for p in ["42.20.4/mod.info","common/media/voxel-studio/package-12.properties","common/media/voxel-studio/package-7.properties"])
    for relative in ["SuQingRefrigerationUpgrade_4221"]:
        folder=USER/"mods"/relative
        files.extend(p for p in folder.rglob("*") if p.is_file())
    return {str(p):sha(p) for p in sorted(set(files)) if p.exists()}

def capture():
    target=VALIDATION/"protected_before.json"
    if target.exists(): raise RuntimeError("Existing protection snapshot is immutable: "+str(target))
    save(target,{"checkedAt":stamp(),"scope":"Read-only file hashes, not a world backup", "files":protected()})
    print("PROTECTED_SNAPSHOT files="+str(len(json.loads(target.read_text(encoding="utf-8"))["files"])))

def run(label,command):
    # Kahlua's installed stdlib.lua is resolved relative to the game directory.
    result=subprocess.run([str(p) for p in command],cwd=GAME,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    text=result.stdout.decode("utf-8",errors="replace")
    (VALIDATION/(label+".log")).write_text(text,encoding="utf-8")
    if result.returncode: raise AssertionError(label+" failed; "+text[-3500:])
    return text

def validate():
    VALIDATION.mkdir(parents=True,exist_ok=True)
    source_manifest={str(p.relative_to(MOD)).replace("\\","/"):sha(p) for p in sorted(MOD.rglob("*")) if p.is_file()}
    checks=[]
    def check(condition,label):
        if not condition: raise AssertionError(label)
        checks.append(label)
    run("assets",[sys.executable,ROOT/"tools/assets_validate.py"])
    run("runtime",[sys.executable,ROOT/"tools/runtime_run_tests.py"])
    shell=Path(r"C:\Users\15792\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe")
    if not shell.exists(): shell=Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
    run("building",[shell,"-NoProfile","-ExecutionPolicy","Bypass","-File",ROOT/"tools/building_validate.ps1"])
    capacity_runner=ROOT/"tools/capacity_validate.py"
    check(capacity_runner.exists(),"capacity validation entry point exists")
    run("capacity",[sys.executable,capacity_runner])
    run("compile_helper",[JDK/"javac.exe","-encoding","UTF-8",ROOT/"tools/ReleaseLuaCompile.java"])
    lua_files=sorted(MOD.rglob("*.lua"))
    compiled=run("all_lua_compile",[JAVA,"-Duser.home="+str(VALIDATION/"compile_home"),"-cp",str(ROOT/"tools")+";"+str(GAME/"projectzomboid.jar"),"ReleaseLuaCompile",*lua_files])
    check("LUA_COMPILE files="+str(len(lua_files))+" PASS" in compiled,"all shipped Lua compiles with installed Kahlua")
    for category in ["IG_UI","Sandbox","Recipes","Tooltip","ItemName","Moveables"]:
        languages={lang:json.loads((MOD/f"42/media/lua/shared/Translate/{lang}/{category}.json").read_text(encoding="utf-8")) for lang in ["CN","CH","EN"]}
        check(set(languages["CN"])==set(languages["CH"])==set(languages["EN"]),category+" language keys match")
        for key,cn in languages["CN"].items():
            check(sorted(re.findall(r"%\d+",cn))==sorted(re.findall(r"%\d+",languages["EN"][key])),category+" placeholder parity "+key)
    sandbox=(MOD/"42/media/sandbox-options.txt").read_text(encoding="utf-8")
    capacity=sandbox.split("option SuQingFreshnessFridge.Capacity",1)[1].split("}",1)[0]
    check(all(re.search(r"\b"+key+r"\s*=\s*"+value+r"\b",capacity) for key,value in [("default","200"),("min","50"),("max","1000")]),"capacity sandbox is 200 default / 50–1000")
    metadata=(MOD/"42/mod.info").read_text(encoding="utf-8")
    check("id=SuQingFreshnessFridge" in metadata and "tiledef=suqing_freshness_fridge_01 7825" in metadata,"mod and tile definition identity")
    from PIL import Image
    for asset in ["poster.png","icon.png"]:
        with Image.open(MOD/"42"/asset) as im:
            check(im.format=="PNG" and min(im.size)>=128,"real PNG "+asset)
    reports={
        "runtime":json.loads((ROOT/"tests/runtime_validation_report.json").read_text(encoding="utf-8")),
        "building":json.loads((ROOT/"tests/building_validation.json").read_text(encoding="utf-8-sig")),
        "assets":json.loads((ROOT/"art/model/asset_validation.json").read_text(encoding="utf-8")),
        "capacity":json.loads((ROOT/"tests/capacity_validation.json").read_text(encoding="utf-8")),
    }
    check(reports["runtime"].get("result")=="PASS" and reports["assets"].get("result")=="PASS","component reports pass")
    check("failures=0" in reports["capacity"].get("output",""),"capacity transfer and trait oracle report passes")
    check(all("failures=0" in str(v) for v in reports["building"]["native"]+reports["building"]["kahlua"]),"building parser and transaction control-flow reports pass")
    check(not (USER/"mods/SuQingFreshnessFridge").exists(),"candidate is not installed in user mods")
    for file in [USER/"mods/default.txt",USER/"Saves/Sandbox/2026-10-09_18-19-22/mods.txt"]:
        check(not re.search(r"\bmod\s*=\s*SuQingFreshnessFridge\s*,",file.read_text(encoding="utf-8")),"candidate not enabled in "+str(file))
    before=json.loads((VALIDATION/"protected_before.json").read_text(encoding="utf-8"))["files"]
    after=protected()
    save(VALIDATION/"protected_after.json",{"checkedAt":stamp(),"files":after})
    check(before==after,"protected existing mods, active lists, sandbox and key configuration hashes unchanged")
    after_source={str(p.relative_to(MOD)).replace("\\","/"):sha(p) for p in sorted(MOD.rglob("*")) if p.is_file()}
    check(source_manifest==after_source,"shipped source and assets stayed unchanged throughout final validation")
    result={"version":VERSION,"checkedAt":stamp(),"result":"PASS","checks":checks,"lua_files":len(lua_files),"reports":reports,
        "installed":False,"enabled":False,"game_started":False,"world_created":False,"in_game_tested":False,
        "protected_file_count":len(before),"capacity":{"default":200,"min":50,"max":1000},"source_manifest":source_manifest,
        "limits":["SP Lua UI transfer bridge is scoped to this fridge; unrelated pure-Java mod paths retain their native cap.",
                  "No restoration credit for unloaded/offline or unverified power intervals.",
                  "Native-method, parser and mock checks do not replace gameplay or Viewpoint visual acceptance."]}
    save(VALIDATION/"offline_validation.json",result)
    print(json.dumps({"result":"PASS","lua_files":len(lua_files),"checks":len(checks),"protected_file_count":len(before),"installed":False},ensure_ascii=False))

def package():
    report=json.loads((VALIDATION/"offline_validation.json").read_text(encoding="utf-8"))
    if report["result"]!="PASS": raise RuntimeError("Validation must pass before packaging")
    current={str(p.relative_to(MOD)).replace("\\","/"):sha(p) for p in sorted(MOD.rglob("*")) if p.is_file()}
    if report["source_manifest"]!=current: raise RuntimeError("Runtime files changed after validation; rerun checks before freezing")
    folder=ARTIFACT/"release"
    folder.mkdir(exist_ok=True)
    frozen=folder/"mods/SuQingFreshnessFridge"
    if frozen.exists(): raise RuntimeError("Frozen release already exists; do not overwrite it")
    shutil.copytree(MOD,frozen)
    shutil.copy2(ARTIFACT/"集中验收清单.txt",folder/"集中验收清单.txt")
    shutil.copy2(ROOT/"README.md",folder/"使用说明.md")
    shutil.copy2(VALIDATION/"offline_validation.json",folder/"离线验证结果.json")
    manifest={str(p.relative_to(folder)).replace("\\","/"): {"bytes":p.stat().st_size,"sha256":sha(p)} for p in sorted(folder.rglob("*")) if p.is_file()}
    save(folder/"文件校验.json",manifest)
    archive=ARTIFACT/("蘇清的返鲜冰箱_v"+VERSION+"_未安装测试包.zip")
    if archive.exists(): raise RuntimeError("Release archive already exists")
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as out:
        for p in sorted(folder.rglob("*")):
            if p.is_file(): out.write(p,str(p.relative_to(folder)).replace("\\","/"))
    with zipfile.ZipFile(archive) as check:
        if check.testzip() is not None: raise AssertionError("Archive CRC readback failed")
        names={str(p.relative_to(folder)).replace("\\","/") for p in folder.rglob("*") if p.is_file()}
        if set(check.namelist())!=names: raise AssertionError("Archive members do not match frozen tree")
        for name in names:
            if hashlib.sha256(check.read(name)).hexdigest()!=sha(folder/name): raise AssertionError("Archive member mismatch "+name)
    receipt={"version":VERSION,"createdAt":stamp(),"archive":str(archive),"sha256":sha(archive),"bytes":archive.stat().st_size,
             "file_count":len(names),"verified_members":len(names),"source":str(ROOT),"installed":False,"enabled":False,"in_game_tested":False}
    save(ARTIFACT/"发行包校验回执.json",receipt)
    print(json.dumps(receipt,ensure_ascii=False))

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("command",choices=["capture","validate","package"])
    command=parser.parse_args().command
    VALIDATION.mkdir(parents=True,exist_ok=True)
    {"capture":capture,"validate":validate,"package":package}[command]()
