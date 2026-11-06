param([string]$PythonExe = 'E:\code\python\python.exe')
$ErrorActionPreference = 'Stop'
& $PythonExe (Join-Path $PSScriptRoot 'capacity_validate.py')
if ($LASTEXITCODE -ne 0) { throw 'Capacity regression failed.' }
