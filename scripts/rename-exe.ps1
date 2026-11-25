# Renames the Windows program to Tether.exe (safe to run many times).
# Changes ONLY: BINARY_NAME, FileDescription, InternalName, OriginalFilename, the window title.
# Does NOT touch CompanyName / ProductName: Windows builds the data folder from them, so pairing,
# settings and the log stay where they are.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cm = Join-Path $root 'windows\CMakeLists.txt'
$rc = Join-Path $root 'windows\runner\Runner.rc'
$mc = Join-Path $root 'windows\runner\main.cpp'
if (-not (Test-Path $cm)) { Write-Host 'windows\ folder not found. Run: flutter create --platforms=windows --project-name laptop_link .'; exit 1 }
(Get-Content $cm -Raw) -replace 'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "Tether")' | Set-Content $cm -NoNewline
$t = Get-Content $rc -Raw
$t = $t -replace '(VALUE "FileDescription",\s*)"[^"]*"', '$1"Tether"'
$t = $t -replace '(VALUE "InternalName",\s*)"[^"]*"', '$1"Tether"'
$t = $t -replace '(VALUE "OriginalFilename",\s*)"[^"]*"', '$1"Tether.exe"'
Set-Content $rc $t -NoNewline
if (Test-Path $mc) { (Get-Content $mc -Raw) -replace 'L"laptop_link"', 'L"Tether"' | Set-Content $mc -NoNewline }
Write-Host 'Done. The program is now build\windows\x64\runner\Release\Tether.exe'
