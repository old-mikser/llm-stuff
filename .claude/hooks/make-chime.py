#!/usr/bin/env python3
"""Build a quiet chime WAV: scale a source WAV's amplitude down and prepend
silence (so a sleeping audio device has time to wake before the audible part).

Pure stdlib, no external tools. Reports peak amplitude so you can judge loudness
without playing anything. 16-bit PCM WAV in, 16-bit PCM WAV out.

Examples:
    ./make-chime.py --src some-sound.wav --amp 0.6 --lead 0.6 \\
        --out ~/.claude/hooks/claude-chime.wav

    # Two blips from an already-built chime, dropping the lead it came with:
    ./make-chime.py --src claude-chime.wav --amp 1.0 --skip 0.6 \\
        --repeat 2 --gap 0.22 --out claude-ask.wav
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
    ap.add_argument("--skip", type=float, default=0.0,
                    help="seconds to drop off the front of the source")
    ap.add_argument("--clip", type=float, default=0.0,
                    help="keep at most this many seconds of the source (0 = all)")
    ap.add_argument("--repeat", type=int, default=1, help="how many times to play the sound")
    ap.add_argument("--gap", type=float, default=0.22,
                    help="silence between repeats, seconds")
    args = ap.parse_args()
    if args.repeat < 1:
        raise SystemExit("--repeat must be at least 1")

    with wave.open(args.src, "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width != 2:
        raise SystemExit(f"source is {width * 8}-bit; this tool expects 16-bit PCM")

    samples = array.array("h")
    samples.frombytes(raw)
    del samples[: int(rate * args.skip) * channels]
    if not samples:
        raise SystemExit(f"--skip {args.skip} left nothing of the source")
    if args.clip:
        keep = int(rate * args.clip) * channels
        if keep < len(samples):
            del samples[keep:]
            # Ramp the cut end down to zero, or the truncation clicks.
            fade = min(int(rate * 0.05) * channels, len(samples))
            for i in range(fade):
                at = len(samples) - fade + i
                samples[at] = int(samples[at] * (fade - i) / fade)

    peak = 0
    for i, s in enumerate(samples):
        v = int(round(s * args.amp))
        v = 32767 if v > 32767 else -32768 if v < -32768 else v
        samples[i] = v
        if abs(v) > peak:
            peak = abs(v)

    def silence(seconds):
        return array.array("h", [0] * (int(rate * seconds) * channels))

    lead = silence(args.lead)
    gap = silence(args.gap)

    with wave.open(args.out, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(lead.tobytes())
        for n in range(args.repeat):
            if n:
                w.writeframes(gap.tobytes())
            w.writeframes(samples.tobytes())

    body = len(samples) / channels / rate
    dur = args.lead + args.repeat * body + (args.repeat - 1) * args.gap
    pct = round(100.0 * peak / 32767, 1)
    print(f"OK wrote {args.out}")
    print(f"  source={os.path.basename(args.src)} amp={args.amp} repeat={args.repeat}")
    print(f"  peak={peak} of 32767 ({pct}% full scale)  duration={round(dur, 2)}s "
          f"(incl {args.lead}s silence)")


if __name__ == "__main__":
    main()
