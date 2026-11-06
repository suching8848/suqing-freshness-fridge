param(
    [string]$GameRoot = 'D:\steam\steamapps\common\ProjectZomboid',
    [string]$JdkBin = 'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$luaRoot = Join-Path $projectRoot 'mods\SuQingFreshnessFridge\42\media\lua'
$scriptsRoot = Join-Path $projectRoot 'mods\SuQingFreshnessFridge\42\media\scripts'
$testRoot = Join-Path $projectRoot 'tests'
$taskHome = Join-Path $testRoot 'building_java_home'
$classPath = $PSScriptRoot + ';' + (Join-Path $GameRoot 'projectzomboid.jar')
$javaExe = Join-Path $GameRoot 'jre64\bin\java.exe'
$javacExe = Join-Path $JdkBin 'javac.exe'
$sources = @(
    (Join-Path $PSScriptRoot 'building_NativeAudit.java'),
    (Join-Path $PSScriptRoot 'building_KahluaRunner.java')
)
Push-Location -LiteralPath $GameRoot
try {
& $javacExe -encoding UTF-8 @sources
if ($LASTEXITCODE -ne 0) { throw 'Building audit compilation failed.' }
$nativeOutput = & $javaExe "-Duser.home=$taskHome" -cp $classPath building_NativeAudit $scriptsRoot
if ($LASTEXITCODE -ne 0) { throw 'Native building script audit failed.' }
$luaFiles = @(
    (Join-Path $testRoot 'building_setup.lua'),
    (Join-Path $GameRoot 'media\lua\shared\Moveables\ISMoveableSpriteProps.lua'),
    (Join-Path $GameRoot 'media\lua\server\BuildingObjects\ISBuildIsoEntity.lua'),
    (Join-Path $GameRoot 'media\lua\client\BuildingObjects\TimedActions\ISBuildAction.lua'),
    (Join-Path $luaRoot 'shared\SuQingFreshnessFridge\Building.lua'),
    (Join-Path $luaRoot 'client\SuQingFreshnessFridge_Building.lua'),
    (Join-Path $testRoot 'building_regression.lua')
)
$luaOutput = & $javaExe "-Duser.home=$taskHome" -cp $classPath building_KahluaRunner @luaFiles
if ($LASTEXITCODE -ne 0) { throw 'Kahlua building regression failed.' }
$record = [ordered]@{
    checkedAt = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
    scope = 'Offline native script component parsing plus Lua mocks; no game process started or operated.'
    native = @($nativeOutput)
    kahlua = @($luaOutput)
    coverage = @(
        'Dedicated native build category and four sprite facings',
        'Exact physical material counts and disjoint digital/classic watch families',
        'Native torch fuel use, retained screwdriver/mask, no skill gate',
        'Idempotent fridge initialization preserves contents and ModData',
        'Actual vanilla movable save/restore and nonempty-container pickup restriction',
        'Actual vanilla build cancellation, invalid placement, failed payment and successful creation control flow'
    )
    limits = @(
        'Inventory payment implementation is mocked; the production recipe uses native BuildLogic.',
        'Item Icon key is grammar-checked but omitted from native Item.Load to avoid GL texture initialization.',
        'In-game menu appearance, textures, full save/reload and real pickup/place need user acceptance.'
    )
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testRoot 'building_validation.json') -Encoding UTF8
$nativeOutput
$luaOutput
}
finally {
    Pop-Location
}
