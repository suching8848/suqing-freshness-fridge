"""Isolated capacity-refresh regressions; existing component hosts, no game/World."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,os,re,subprocess

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r'D:\steam\steamapps\common\ProjectZomboid')
JAVAC=Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
TESTS=ROOT/'tests';TOOLS=ROOT/'tools';LUA=ROOT/'mods/SuQingFreshnessFridge/42/media/lua'
def digest(p):
    if not p.exists():return None
    s=p.stat();return {'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'mtime_ns':s.st_mtime_ns,'bytes':s.st_size}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args()
    out=a.output or GAME/'CodexAssets/FreshnessFridgeCapacityFix_20261107_0617/tests'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True,exist_ok=False);classes=out/'classes';classes.mkdir();home=out/'isolated_home';home.mkdir();temp=home/'Temp';temp.mkdir()
    env=dict(os.environ);env.update(USERPROFILE=str(home),APPDATA=str(home/'AppData/Roaming'),LOCALAPPDATA=str(home/'AppData/Local'),TEMP=str(temp),TMP=str(temp))
    env['JAVA_TOOL_OPTIONS']='-Xms32m -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC'
    java=GAME/'jre64/bin/java.exe';cp=os.pathsep.join(map(str,[classes,GAME,GAME/'projectzomboid.jar',GAME/'*']))
    core=LUA/'shared/SuQingFreshnessFridge/Core.lua';capacity=LUA/'shared/SuQingFreshnessFridge/Capacity.lua';building=LUA/'shared/SuQingFreshnessFridge/Building.lua';runtime=LUA/'client/SuQingFreshnessFridge_Runtime.lua'
    sources=[TESTS/'runtime_NativeShieldProbe.java',TESTS/'capacity_refresh_NativeProbe.java',TESTS/'runtime_KahluaAudit.java',TOOLS/'building_KahluaRunner.java',TOOLS/'building_NativeAudit.java',TOOLS/'ReleaseLuaCompile.java']
    inputs=[*sources,*sorted(LUA.rglob('*.lua')),*[p for p in TESTS.glob('*.lua')],TESTS/'runtime_native_trait_table.json',GAME/'projectzomboid.jar']
    before={str(f):digest(f) for f in inputs}
    profile=Path(r'C:\Users\15792\Zomboid')
    protected=[profile/f for f in ['console.txt','options.ini','latestSave.ini','pzopt/options.ini','mods/default.txt','Saves/Sandbox/2026-10-09_18-19-22/mods.txt','Saves/Sandbox/2026-10-09_18-19-22/map_sand.bin','mods/SuQingFreshnessFridge/42/media/lua/shared/SuQingFreshnessFridge/Core.lua','mods/SuQingFreshnessFridge/42/media/lua/shared/SuQingFreshnessFridge/Capacity.lua','mods/SuQingFreshnessFridge/42/media/lua/client/SuQingFreshnessFridge_Runtime.lua']]
    protected+=[GAME/'ProjectZomboid64.json',GAME/'projectzomboid.jar']
    protected_before={str(f):digest(f) for f in protected}
    report={'result':'FAIL','game_started':False,'world_created':False,'world_loaded':False,'production_modified':False,'java_patch_created':False,'output':str(out),'input_before':before,'protected_before':protected_before,'results':{}}
    def run(label,cmd):
        x=subprocess.run(list(map(str,cmd)),cwd=GAME,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
        log=x.stdout+x.stderr;(out/(label+'.log')).write_text(log,encoding='utf-8')
        if x.returncode:raise RuntimeError(label+' failed:\n'+log[-9000:])
        return log
    def jrun(label,host,*files):return run(label,[java,'--enable-native-access=ALL-UNNAMED','-Duser.home='+str(home),'-Djava.io.tmpdir='+str(temp),'-cp',cp,host,*files])
    def summary(log,pattern):
        m=re.search(pattern,log)
        if not m:raise RuntimeError('Missing completion summary: '+pattern)
        return [int(v) for v in m.groups()]
    try:
        run('compile_component_hosts',[JAVAC,'-encoding','UTF-8','-d',classes,*sources])
        compiled=jrun('compile_all_lua','ReleaseLuaCompile',*sorted(LUA.rglob('*.lua')))
        log=jrun('capacity_refresh_native','capacity_refresh_NativeProbe',TESTS/'runtime_native_core_bootstrap.lua',core,TESTS/'runtime_native_capacity_bootstrap.lua',capacity,building,TESTS/'capacity_refresh_native_setup.lua',runtime,TESTS/'capacity_refresh_native_cases.lua')
        n=summary(log,r'CAPACITY_REFRESH_NATIVE cases=(\d+) assertions=(\d+) stable_writes=1 mixed_writes=1 failures=0')
        report['results']['targeted_native']={'cases':n[0],'assertions':n[1],'stable_10000_writes':1,'mixed_10000_pairs_writes':1,'real_itemcontainer':True,'raw_field_readonly_oracle':True}
        if a.full:
            log=jrun('existing_runtime_model','runtime_KahluaAudit',TESTS/'runtime_mock_bootstrap.lua',core,runtime,TESTS/'runtime_mock_cases.lua')
            n=summary(log,r'RUNTIME_MODEL cases=(\d+) assertions=(\d+) failures=0');report['results']['existing_runtime_model']={'cases':n[0],'assertions':n[1]}
            log=jrun('existing_native_core_capacity','runtime_NativeShieldProbe',TESTS/'runtime_native_core_bootstrap.lua',core,TESTS/'runtime_native_core_cases.lua',TESTS/'runtime_native_capacity_bootstrap.lua',capacity,TESTS/'runtime_native_capacity_cases.lua')
            for key,pattern in [('native_shield',r'NATIVE_SHIELD passes=(\d+) assertions=(\d+)'),('native_precision',r'NATIVE_CORE_PRECISION cases=(\d+) passes=(\d+) assertions=(\d+) failures=0'),('native_display',r'NATIVE_DISPLAY_GUARD cases=(\d+) assertions=(\d+) native_updates=(\d+) failures=0'),('native_capacity',r'NATIVE_CAPACITY_BRIDGE cases=(\d+) assertions=(\d+) failures=0')]:report['results'][key]={'counts':summary(log,pattern)}
            pane=GAME/'media/lua/client/ISUI/ISInventoryPane.lua';pane_source=pane.read_text(encoding='utf-8-sig')
            signatures=['ISInventoryPane:canPutIn()','DraggedItems:update()','ISInventoryPane:transferItemsByWeight(items, container)','ISInventoryPane:transferAll()']
            functions=[]
            for sig in signatures:
                m=re.search(r'^function '+re.escape(sig)+r'[^\n]*\n.*?^end\s*$',pane_source,re.M|re.S)
                if not m:raise RuntimeError('Missing unchanged vanilla function '+sig)
                functions.append(m[0])
            extracted=out/'vanilla_capacity_ui.lua';extracted.write_text('\n\n'.join(functions),encoding='utf-8')
            values=json.loads((TESTS/'runtime_native_trait_table.json').read_text(encoding='utf-8-sig'))
            if isinstance(values,dict):values=next(v for v in values.values() if isinstance(v,list))
            assert len(values)==951
            oracle=out/'capacity_oracle.lua';oracle.write_text('CAPACITY_TRAIT_ORACLE={\n'+',\n'.join('{'+','.join(map(str,row))+'}' for row in values)+'\n}\n',encoding='utf-8')
            log=jrun('existing_capacity_ui_model','building_KahluaRunner',TESTS/'capacity_setup.lua',core,GAME/'media/lua/client/TimedActions/ISInventoryTransferAction.lua',GAME/'media/lua/shared/TimedActions/ISInventoryTransferUtil.lua',GAME/'media/lua/shared/TimedActions/ISTransferAction.lua',extracted,oracle,capacity,TESTS/'capacity_regression.lua')
            report['results']['capacity_ui_model']={'assertions':summary(log,r'CAPACITY_LUA assertions=(\d+) failures=0')[0]}
            log=jrun('existing_building_model','building_KahluaRunner',TESTS/'building_setup.lua',GAME/'media/lua/shared/Moveables/ISMoveableSpriteProps.lua',GAME/'media/lua/server/BuildingObjects/ISBuildIsoEntity.lua',GAME/'media/lua/client/BuildingObjects/TimedActions/ISBuildAction.lua',building,LUA/'client/SuQingFreshnessFridge_Building.lua',TESTS/'building_regression.lua')
            report['results']['building_model']={'completed':True}
            log=jrun('existing_native_building','building_NativeAudit',ROOT/'mods/SuQingFreshnessFridge/42/media/scripts')
            report['results']['native_building']={'completed':True}
        report['source_version']=re.search(r'C.version\s*=\s*"([^\"]+)"',core.read_text(encoding='utf-8'))[1]
        report['limits']=['Actual native ItemContainer and read-only raw field oracle; character/queue/Events/loaded status are controlled. No World/Cell/save/UI/gameplay.', 'Opaque physical writes80/300 are not polled. Overlay stays configured; create/load/save force a physical rewrite.', 'This is setter-call counting and correctness, not FPS/timing measurement. Legacy release/publication scripts are not invoked.']
        report['result']='PASS'
    except Exception as e:report['error']=str(e);raise
    finally:
        report['input_after']={str(f):digest(f) for f in inputs};report['inputs_unchanged']=before==report['input_after']
        report['protected_after']={str(f):digest(f) for f in protected};report['protected_unchanged']=protected_before==report['protected_after']
        if not report['inputs_unchanged'] or not report['protected_unchanged']:report['result']='FAIL'
        report['time']=datetime.now(timezone.utc).isoformat();(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({k:v for k,v in report.items() if not k.startswith('input_') and not k.startswith('protected_')},ensure_ascii=False))
    if report['result']!='PASS':raise RuntimeError('Protected or source state changed during validation')
if __name__=='__main__':main()
