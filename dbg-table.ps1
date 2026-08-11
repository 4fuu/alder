$dir = Join-Path $env:TEMP 'aster-dbg'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Set-Location 'C:\Users\4fu\Desktop\Project\Tool\aster\cgen'
$env:GOFLAGS=''
# generate table.c via a tiny go test helper is overkill; reuse the golden generator by running the test in update mode is not available; write a small generator:
