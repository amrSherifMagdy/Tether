# One-shot stop-hotkey check: prints {"down":true} when Ctrl+Alt+Shift+S are all held.
Add-Type @"
using System.Runtime.InteropServices;
public static class H { [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk); }
"@
$d = $true; foreach ($k in 0x11, 0x12, 0x10, 0x53) { if (([H]::GetAsyncKeyState($k) -band 0x8000) -eq 0) { $d = $false } }
Write-Output ('{"down":' + $d.ToString().ToLower() + '}')
