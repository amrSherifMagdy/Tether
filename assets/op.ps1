# One-shot input op. Started by the desktop app for ONE action, then exits.
# op.ps1 -Op click|move|scroll|type|key|info [-X n] [-Y n] [-Button left|right] [-Count n] [-Dy n] [-Keys "vk:ext,vk:ext"] [-TextFile path]
# Never evaluates received text. Prints one JSON line on success; errors go to stderr with exit code 1.
param([string]$Op, [int]$X = 0, [int]$Y = 0, [string]$Button = 'left', [int]$Count = 1, [int]$Dy = 0, [string]$Keys = '', [string]$TextFile = '')
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  public static void TypeChar(ushort ch) {
    INPUT[] a = new INPUT[2];
    a[0].type = 1; a[0].u.ki.wVk = 0; a[0].u.ki.wScan = ch; a[0].u.ki.dwFlags = 4;
    a[1].type = 1; a[1].u.ki.wVk = 0; a[1].u.ki.wScan = ch; a[1].u.ki.dwFlags = 6;
    uint n = SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
    if (n != 2) throw new Exception("SendInput failed, err " + Marshal.GetLastWin32Error());
  }
}
"@
[void][W]::SetProcessDPIAware()
function Clamp([int]$v, [int]$lo, [int]$hi) { if ($v -lt $lo) { return $lo }; if ($v -gt $hi) { return $hi }; return $v }
function Move-To([int]$x, [int]$y) {
  $w = [W]::GetSystemMetrics(0); $h = [W]::GetSystemMetrics(1)
  if (-not [W]::SetCursorPos((Clamp $x 0 ($w - 1)), (Clamp $y 0 ($h - 1)))) { throw 'SetCursorPos failed' }
}
switch ($Op) {
  'info' { Write-Output ('{"ok":true,"w":' + [W]::GetSystemMetrics(0) + ',"h":' + [W]::GetSystemMetrics(1) + '}') }
  'move' { Move-To $X $Y; Write-Output '{"ok":true}' }
  'click' {
    Move-To $X $Y
    if ($Button -eq 'right') { $d = 0x8; $u = 0x10 } else { $d = 0x2; $u = 0x4 }
    $n = Clamp $Count 1 2
    for ($i = 0; $i -lt $n; $i++) {
      [W]::mouse_event($d, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30
      [W]::mouse_event($u, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    }
    Write-Output '{"ok":true}'
  }
  'scroll' {
    Move-To $X $Y
    $notches = Clamp $Dy -50 50
    $delta = if ($notches -gt 0) { -120 } else { 120 }
    for ($i = 0; $i -lt [Math]::Abs($notches); $i++) { [W]::mouse_event(0x800, 0, 0, $delta, [UIntPtr]::Zero); Start-Sleep -Milliseconds 20 }
    Write-Output '{"ok":true}'
  }
  'type' {
    $text = [System.IO.File]::ReadAllText($TextFile, [System.Text.Encoding]::UTF8)
    foreach ($ch in $text.ToCharArray()) {
      if ($ch -eq "`n") { [W]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero) }
      elseif ($ch -ne "`r") { [W]::TypeChar([uint16]$ch) }
      Start-Sleep -Milliseconds 8
    }
    Write-Output '{"ok":true}'
  }
  'key' {
    $list = @(); foreach ($p in $Keys.Split(',')) { $a = $p.Split(':'); $list += ,@([int]$a[0], [int]$a[1]) }
    foreach ($k in $list) { $f = 0; if ($k[1] -eq 1) { $f = 1 }; [W]::keybd_event([byte]$k[0], 0, $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 25 }
    [array]::Reverse($list)
    foreach ($k in $list) { $f = 2; if ($k[1] -eq 1) { $f = 3 }; [W]::keybd_event([byte]$k[0], 0, $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 25 }
    Write-Output '{"ok":true}'
  }
  default { throw 'unknown op' }
}
