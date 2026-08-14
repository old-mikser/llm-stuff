#!/usr/bin/env python3
"""Build a quiet chime WAV: scale a source WAV's amplitude down and prepend
silence (so a sleeping audio device has time to wake before the audible part).

Pure stdlib, no external tools. Reports peak amplitude so you can judge loudness
without playing anything. 16-bit PCM WAV in, 16-bit PCM WAV out.

Example:
    ./make-chime.py --src some-sound.wav --amp 0.6 --lead 0.6 \\
        --out ~/.claude/hooks/claude-chime.wav
"""
import argparse
import array
import os
import wave


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--src", required=True, help="source 16-bit PCM WAV")
    ap.add_argument("--out", default=os.path.expanduser("~/.claude/hooks/claude-chime.wav"))
    ap.add_argument("--amp", type=float, default=0.6, help="0..1 loudness multiplier")
    ap.add_argument("--lead", type=float, default=0.6, help="leading silence, seconds")
    args = ap.parse_args()

    with wave.open(args.src, "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)
    if width != 2:
        raise SystemExit(f"source is {width * 8}-bit; this tool expects 16-bit PCM")

    samples = array.array("h")
    samples.frombytes(raw)

    peak = 0
    for i, s in enumerate(samples):
        v = int(round(s * args.amp))
        v = 32767 if v > 32767 else -32768 if v < -32768 else v
        samples[i] = v
        if abs(v) > peak:
            peak = abs(v)

    silence = array.array("h", [0] * (int(rate * args.lead) * channels))

    with wave.open(args.out, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(silence.tobytes())
        w.writeframes(samples.tobytes())

    pct = round(100.0 * peak / 32767, 1)
    dur = round(args.lead + frames / rate, 2)
    print(f"OK wrote {args.out}")
    print(f"  source={os.path.basename(args.src)} amp={args.amp}")
    print(f"  peak={peak} of 32767 ({pct}% full scale)  duration={dur}s (incl {args.lead}s silence)")


if __name__ == "__main__":
    main()
