# One-shot screenshot: shot.ps1 <outfile.jpg> <maxWidth> <quality>
# Writes a JPEG to the given path and prints one JSON line with the sizes. Nothing else.
param([string]$OutPath, [int]$MaxW = 960, [int]$Q = 55)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System.Runtime.InteropServices;
public static class S {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
"@
[void][S]::SetProcessDPIAware()
$w = [S]::GetSystemMetrics(0); $h = [S]::GetSystemMetrics(1)
$scale = [Math]::Min(1.0, $MaxW / $w)
$tw = [int][Math]::Round($w * $scale); $th = [int][Math]::Round($h * $scale)
$full = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($full)
$g.CopyFromScreen(0, 0, 0, 0, $full.Size)
$small = New-Object System.Drawing.Bitmap $tw, $th
$g2 = [System.Drawing.Graphics]::FromImage($small)
$g2.DrawImage($full, 0, 0, $tw, $th)
$p = [System.Windows.Forms.Cursor]::Position
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 2
$g2.DrawEllipse($pen, [int]($p.X * $scale) - 8, [int]($p.Y * $scale) - 8, 16, 16)
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$Q)
$small.Save($OutPath, $codec, $ep)
$g.Dispose(); $g2.Dispose(); $pen.Dispose(); $full.Dispose(); $small.Dispose()
Write-Output ('{"width":' + $tw + ',"height":' + $th + ',"scale":' + $scale.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ',"screenW":' + $w + ',"screenH":' + $h + '}')
