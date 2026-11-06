"""Offline Lua capacity/UI regression; no game process is launched."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import datetime

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
JAVAC = Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
JAVA = GAME / 'jre64/bin/java.exe'
TESTS = ROOT / 'tests'
LUA = ROOT / 'mods/SuQingFreshnessFridge/42/media/lua'

def extract_function(source: str, signature: str) -> str:
    match = re.search(r'^function ' + re.escape(signature) + r'[^\n]*\n.*?^end\s*$', source, re.M | re.S)
    if not match:
        raise RuntimeError('Missing vanilla function: ' + signature)
    return match.group(0)

def main():
    oracle = TESTS / 'runtime_native_trait_table.json'
    values = json.loads(oracle.read_text(encoding='utf-8-sig'))
    if isinstance(values, dict):
        values = next(value for value in values.values() if isinstance(value, list))
    if len(values) != 951:
        raise RuntimeError('Expected checked Java float32 oracle for all capacities 50–1000')
    oracle_lua = TESTS / 'capacity_oracle.lua'
    oracle_lua.write_text('CAPACITY_TRAIT_ORACLE={\n' + ',\n'.join('{' + ','.join(map(str,row)) + '}' for row in values) + '\n}\n', encoding='utf-8')
    pane_path = GAME / 'media/lua/client/ISUI/ISInventoryPane.lua'
    pane_source = pane_path.read_text(encoding='utf-8-sig')
    signatures = ['ISInventoryPane:canPutIn()', 'DraggedItems:update()', 'ISInventoryPane:transferItemsByWeight(items, container)', 'ISInventoryPane:transferAll()']
    extracted = TESTS / 'capacity_native_ui_extract.lua'
    extracted.write_text('-- Unmodified vanilla functions from ' + str(pane_path) + '\n-- SHA256 ' + hashlib.sha256(pane_path.read_bytes()).hexdigest() + '\n' + '\n\n'.join(extract_function(pane_source,sig) for sig in signatures), encoding='utf-8')
    runner = ROOT / 'tools/building_KahluaRunner.java'
    subprocess.run([str(JAVAC), '-encoding', 'UTF-8', str(runner)], check=True, cwd=GAME)
    paths = [TESTS/'capacity_setup.lua', LUA/'shared/SuQingFreshnessFridge/Core.lua',
             GAME/'media/lua/client/TimedActions/ISInventoryTransferAction.lua',
             GAME/'media/lua/shared/TimedActions/ISInventoryTransferUtil.lua',
             GAME/'media/lua/shared/TimedActions/ISTransferAction.lua',
             extracted, oracle_lua, LUA/'shared/SuQingFreshnessFridge/Capacity.lua', TESTS/'capacity_regression.lua']
    result = subprocess.run([str(JAVA), '-Duser.home=' + str(TESTS/'capacity_java_home'), '-cp', str(ROOT/'tools')+';'+str(GAME/'projectzomboid.jar'), 'building_KahluaRunner', *map(str,paths)], check=True, text=True, encoding='utf-8', capture_output=True, cwd=GAME)
    if not re.search(r'CAPACITY_LUA assertions=\d+ failures=0', result.stdout):
        raise RuntimeError('Capacity suite produced no completion receipt: '+result.stdout)
    print(result.stdout.strip())
    report = {'checkedAt': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
              'scope': 'Offline Kahlua mocks with unmodified vanilla UI, timed-action and transfer functions; all native trait float32 values 50–1000.',
              'output': result.stdout.strip(), 'oracleSource': str(oracle),
              'assertions': int(re.search(r'assertions=(\d+)', result.stdout).group(1)), 'failures': 0, 'passed': True,
              'oracleSha256': hashlib.sha256(oracle.read_bytes()).hexdigest(),
              'vanillaInventoryPaneSha256': hashlib.sha256(pane_path.read_bytes()).hexdigest(),
              'limits': ['No live UI or save exercised.', 'Pure Java external direct calls bypass Lua getter/method overlays.', 'Native object bridge verification is reported separately by runtime native tests.']}
    (TESTS/'capacity_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__ == '__main__':
    main()
