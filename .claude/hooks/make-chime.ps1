# Build a quiet, pleasant chime: scale an existing WAV down in amplitude and
# prepend silence (device-wake headroom). SoundPlayer ignores volume, so the
# loudness is baked into the file. Reports peak amplitude WITHOUT playing.
param(
  [string]$Src = "C:\Windows\Media\Windows Notify Messaging.wav",
  [string]$Out = "$env:USERPROFILE\claude-chime.wav",
  [double]$Amp = 0.15,
  [double]$LeadSec = 0.6
)

$b = [System.IO.File]::ReadAllBytes($Src)

# --- inline chunk scan (no function -> avoids comma-precedence bug) ---
$fmtOff = -1; $dataOff = -1; $dataLen = 0
$i = 12
while ($i -lt $b.Length - 8) {
  $cid = [System.Text.Encoding]::ASCII.GetString($b, $i, 4)
  $sz  = [BitConverter]::ToInt32($b, $i + 4)
  if ($cid -eq "fmt ") { $fmtOff = $i + 8 }
  elseif ($cid -eq "data") { $dataOff = $i + 8; $dataLen = $sz }
  $i += 8 + $sz + ($sz -band 1)
}
if ($fmtOff -lt 0 -or $dataOff -lt 0) { throw "could not parse WAV chunks" }

$channels = [BitConverter]::ToInt16($b, $fmtOff + 2)
$rate     = [BitConverter]::ToInt32($b, $fmtOff + 4)
$bits     = [BitConverter]::ToInt16($b, $fmtOff + 14)
if ($bits -ne 16) { throw "source is $bits-bit; expected 16-bit PCM" }

# --- scale samples, track peak ---
$scaled = New-Object byte[] $dataLen
$peak = 0
for ($k = 0; $k -lt $dataLen - 1; $k += 2) {
  $s = [BitConverter]::ToInt16($b, $dataOff + $k)
  $v = [int][math]::Round($s * $Amp)
  if ($v -gt 32767) { $v = 32767 } elseif ($v -lt -32768) { $v = -32768 }
  if ([math]::Abs($v) -gt $peak) { $peak = [math]::Abs($v) }
  $bytes = [BitConverter]::GetBytes([int16]$v)
  $scaled[$k] = $bytes[0]; $scaled[$k + 1] = $bytes[1]
}

$silBytes = [int]($rate * $LeadSec) * $channels * 2
$newLen = $silBytes + $dataLen

$ms = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($ms)
$w.Write([char[]]"RIFF"); $w.Write([int](36 + $newLen)); $w.Write([char[]]"WAVE")
$w.Write([char[]]"fmt "); $w.Write([int]16)
$w.Write([int16]1); $w.Write([int16]$channels); $w.Write([int]$rate)
$w.Write([int]($rate * $channels * 2)); $w.Write([int16]($channels * 2)); $w.Write([int16]16)
$w.Write([char[]]"data"); $w.Write([int]$newLen)
$w.Write((New-Object byte[] $silBytes))
$w.Write($scaled)
$w.Flush()
[System.IO.File]::WriteAllBytes($Out, $ms.ToArray())

$pct = [math]::Round(100.0 * $peak / 32767, 1)
$dur = [math]::Round($LeadSec + ($dataLen / 2.0 / $channels / $rate), 2)
Write-Output "OK wrote $Out"
Write-Output "  source=$(Split-Path $Src -Leaf) amp=$Amp"
Write-Output "  peak=$peak of 32767 ($pct% full scale)  duration=${dur}s (incl ${LeadSec}s silence)"
