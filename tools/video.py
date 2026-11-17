#!/usr/bin/env python3
"""Record a video of a scripted demo: cpcsim frames + the AY's sound.

  video.py game.sna --sym game.sym --frames N --out video.mp4
           [--slow 1.25] [--log] [--no-video] [--wav out.wav]

Runs the snapshot in tools/cpcsim.py, grabs the displayed screen after
every frame (384x272, Mode 1, scaled x4 to 1536x1088 with square pixels)
and the AY registers the game wrote (the driver writes them once a frame,
from the interrupt), synthesises the AY (1 MHz: three square waves, the
17-bit noise, the logarithmic volume steps; the envelope generator isn't
used by the game) at 125 kHz and lets ffmpeg resample and mux.
--log prints the game's state changes (state, level, lives, x).
"""
import argparse
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcsim import CPC, load_syms  # noqa: E402
from snapinfo import IDX_TO_RGB  # noqa: E402

RATE = 125_000                  # AY tone counter rate (1 MHz / 8)
FPS = 50
N = RATE // FPS                 # samples per frame
# AY-3-8912 output levels (normalised), volume 0..15
AY_VOL = [0.0, 0.0106, 0.0150, 0.0222, 0.0320, 0.0466, 0.0665, 0.1039,
          0.1237, 0.1986, 0.2803, 0.3548, 0.4702, 0.6030, 0.7530, 1.0]
LANE = 21845                    # one channel at full volume (3 fit in 16 bits)


class AY:
    def __init__(self):
        self.tone_pos = [0, 0, 0]
        self.noise_pos = 0
        self.lfsr_bits = self.make_lfsr()
        self.lfsr_i = 0
        self.out = []

    @staticmethod
    def make_lfsr():
        r = 1
        bits = bytearray()
        for _ in range((1 << 17) - 1):
            bits.append(r & 1)
            r = (r >> 1) | (((r ^ (r >> 3)) & 1) << 16)
        return bytes(bits)

    def noise_mask(self, np_):
        """Noise as 16-bit lanes (all ones / zeros) for this frame."""
        step = 2 * max(1, np_)
        bits, i = self.lfsr_bits, self.lfsr_i
        spent = min(self.noise_pos, step - 1)
        on, off = b"\xff\xff", b"\x00\x00"
        parts = []
        t = 0
        while t < N:
            n = min(step - spent, N - t)
            parts.append((on if bits[i] else off) * n)
            t += n
            spent += n
            if spent >= step:
                spent = 0
                i = (i + 1) % len(bits)
        self.noise_pos, self.lfsr_i = spent, i
        return int.from_bytes(b"".join(parts), "big")

    def frame(self, r):
        mixer = r[7]
        total = 0
        noise = None
        for ch in range(3):
            vol = r[8 + ch] & 15
            tone_on = not (mixer >> ch) & 1
            noise_on = not (mixer >> (ch + 3)) & 1
            period = (r[2 * ch] | (r[2 * ch + 1] & 15) << 8) or 1
            # keep the phase going even when silent
            pos = self.tone_pos[ch]
            self.tone_pos[ch] = (pos + N) % (2 * period)
            if vol == 0 or (not tone_on and not noise_on):
                continue
            level = round(LANE * AY_VOL[vol]).to_bytes(2, "big")
            if tone_on and period > 2:
                pat = level * period + b"\x00\x00" * period
                reps = (pos + N) // (2 * period) + 2
                data = (pat * reps)[2 * pos:2 * (pos + N)]
                v = int.from_bytes(data, "big")
            elif tone_on:   # beyond hearing: the AY's output sits at the mean
                v = int.from_bytes((round(LANE * AY_VOL[vol] / 2).to_bytes(2, "big")) * N, "big")
            else:
                v = int.from_bytes(level * N, "big")
            if noise_on:
                if noise is None:
                    noise = self.noise_mask(r[6] & 31)
                v &= noise
            total += v
        if noise is None:   # the noise runs on regardless
            self.noise_mask(r[6] & 31)
        self.out.append(total.to_bytes(2 * N, "big"))


def frame_rows(cpc):
    """Per screen row: the (start, end) runs of its 96 bytes in RAM."""
    r1, r6 = cpc.crtc[1], cpc.crtc[6]
    start = (cpc.crtc[12] << 8 | cpc.crtc[13]) & 0x3FFF
    rows = []
    for row in range(r6):
        for ra in range(8):
            runs = []
            for j in range(r1):
                ma = start + row * r1 + j
                base = (((ma >> 12) & 3) << 14 | ra << 11 | (ma & 0x3FF) << 1) & 0xFFFF
                if runs and runs[-1][1] == base:
                    runs[-1][1] = base + 2
                else:
                    runs.append([base, base + 2])
            rows.append(runs)
    return rows, r1 * 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sna")
    ap.add_argument("--sym")
    ap.add_argument("--frames", type=int, default=12000)
    ap.add_argument("--slow", type=float, default=1.25)
    ap.add_argument("--out", default="build/video.mp4")
    ap.add_argument("--wav")
    ap.add_argument("--log", action="store_true")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--fade", type=float, default=1.5, help="fade out at the end (s)")
    a = ap.parse_args()

    cpc = CPC(a.sna)
    cpc.slow = a.slow
    cpc.psg_log = []
    syms = load_syms(a.sym)
    watch = [n for n in ("game_state", "level_num", "lives", "wp_last") if n in syms]
    last = None
    ay = AY()
    tmp = tempfile.mkdtemp(prefix="linner_video_", dir=os.path.dirname(os.path.abspath(a.out)))
    vid = os.path.join(tmp, "video.mp4")
    enc = None
    rows = width = None
    crtc_key = None
    luts = {}
    if not a.no_video:
        enc = subprocess.Popen(
            ["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
             "-s", "384x272", "-r", str(FPS), "-i", "-",
             "-vf", "scale=1536:1088:flags=neighbor", "-c:v", "libx264", "-preset", "medium",
             "-crf", "18", "-pix_fmt", "yuv420p", vid], stdin=subprocess.PIPE)
    mem = cpc.m.memory
    for f in range(a.frames):
        cpc.run_frame()
        ay.frame(cpc.psg_log[-1])
        if a.log:
            now = tuple(cpc.base_ram(syms[n], 1)[0] for n in watch)
            if now != last:
                wx = cpc.base_ram(syms["scroll_wx"], 2) if "scroll_wx" in syms else b"\0\0"
                print(f"{f:6d} {f / FPS:7.2f}s " + " ".join(f"{n}={v}" for n, v in zip(watch, now))
                      + f" x={wx[0] | wx[1] << 8}", flush=True)
                last = now
        if enc:
            key = tuple(cpc.crtc[:14])
            if key != crtc_key:
                rows, width = frame_rows(cpc)
                crtc_key = key
            inks = tuple(cpc.inks[:4])
            lut = luts.get(inks)
            if lut is None:
                rgb = [bytes(IDX_TO_RGB.get(i & 0x1F, (255, 0, 255))) for i in inks]
                lut = []
                for b in range(256):
                    px = b""
                    for i in range(4):
                        p = ((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1)
                        px += rgb[p]
                    lut.append(px)
                luts[inks] = lut
            out = bytearray()
            for runs in rows[:272]:
                line = b"".join(mem[s:e] for s, e in runs)
                out += b"".join([lut[x] for x in line])
            enc.stdin.write(out)
        if cpc.stopped:
            print(f"stopped at frame {f}")
            break
    nframes = len(cpc.psg_log)
    raw = os.path.join(tmp, "audio.raw")
    with open(raw, "wb") as fh:
        for chunk in ay.out:
            # unsigned lanes -> signed (x - 32768), still big-endian
            v = int.from_bytes(chunk, "big") ^ int.from_bytes(b"\x80\x00" * N, "big")
            fh.write(v.to_bytes(2 * N, "big"))
    secs = nframes / FPS
    afilt = (f"highpass=f=30,lowpass=f=12000,aresample=48000,volume=1.6,"
             f"afade=t=out:st={max(0, secs - a.fade):.2f}:d={a.fade}")
    if a.wav:
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "s16be", "-ar", str(RATE),
                        "-ac", "1", "-i", raw, "-af", afilt, a.wav], check=True)
        print(f"audio -> {a.wav}")
    if enc:
        enc.stdin.close()
        enc.wait()
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", vid,
                        "-f", "s16be", "-ar", str(RATE), "-ac", "1", "-i", raw,
                        "-vf", f"fade=t=out:st={max(0, secs - a.fade):.2f}:d={a.fade}",
                        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
                        "-af", afilt, "-c:a", "aac", "-b:a", "192k", "-shortest", a.out], check=True)
        print(f"video -> {a.out} ({nframes} frames, {secs:.1f} s)")
    for name in os.listdir(tmp):
        os.remove(os.path.join(tmp, name))
    os.rmdir(tmp)


if __name__ == "__main__":
    main()
