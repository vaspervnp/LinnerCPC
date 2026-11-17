#!/usr/bin/env python3
"""Music and sound effects for Linner (build/music.asm).

  gen_music.py out.asm

The driver is src/sound.asm (run from the interrupt, 50 times a second).

Music: three channels (A bass, B lead / arpeggio, C drums or a second
voice). A song has a speed (frames per row; a row is a 16th note) and an
order list per channel. Patterns are written below as text:

  a4:2       note A4 for 2 rows (the length stays until changed)
  c#5 eb5    sharps and flats; octaves 1..8 (c1 = note 0, 32.7 Hz)
  -          rest            =    hold the note (no new attack)
  @lead      switch instrument

Order lists: pattern names, "+n" / "-n" to transpose the next patterns by
n semitones (relative to the song's key, which the game sets: the in-game
song goes up or down with the level), "|" marks the loop point (the list
plays to the end and repeats from there; no "|" = play once and stop).

Bytes: pattern 0..&5F note, &60+n length n+1 rows, &80+i instrument,
&90 rest, &91 hold, &FF end. Order: 0..&7F pattern, &A0+t transpose,
&FE end, &FF + dw loop address.

Instruments are per-frame envelopes: (volume 0..15, pitch offset in
semitones) with flags for noise (then the second number is the noise
period) and tone off; the last frame holds.

Sound effects take over channel C. Each one is a sweep: frames, tone and
or noise, a start period and its change per frame, volume (4.4 fixed
point) and its change, noise period and its change, and the effect that
follows (chains). The number is also the priority: a playing effect is
only replaced by an equal or higher one.
"""
import sys

AY_CLOCK = 1_000_000            # CPC: 1 MHz
NOTE_NAMES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}

# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------
NOISE, TONE_OFF, HOLD = 0x20, 0x10, 0x80


def env(vols, offs=None, noise=None, tone=True):
    """Frames as (flags | volume, second byte)."""
    out = []
    for i, v in enumerate(vols):
        flags = v
        if not tone:
            flags |= TONE_OFF
        second = (offs[i] if offs and i < len(offs) else 0) & 0xFF
        if noise is not None:
            n = noise[i] if isinstance(noise, list) else noise
            if n is not None:
                flags |= NOISE
                second = n
        out.append([flags, second])
    out[-1][0] |= HOLD
    return out


def ramp(a, b, n):
    return [round(a + (b - a) * i / (n - 1)) for i in range(n)]


INSTRUMENTS = {
    # in-game bass: a pluck that pumps with the octave jumps
    "bass": env([13, 12, 11, 10, 10, 9, 9, 8, 8, 7]),
    # lead: a soft attack, a slow fall to a steady 9
    "lead": env([10, 12, 13, 12, 12, 11, 11, 11, 10, 10, 10, 10, 9]),
    # the title's arpeggio: a short pluck
    "arp": env([11, 9, 8, 7, 6, 6, 5, 5, 4, 4, 3]),
    # the title's bass: swells, then fades to a hum
    "pad": env([7, 8, 9, 10, 10] + ramp(10, 6, 30)),
    # drums (channel C)
    "kick": env([14, 13, 12, 10, 8, 5, 2, 0], offs=[0, -5, -10, -14, -18, -21, -24, -24]),
    "snare": env([13, 12, 10, 8, 7, 5, 4, 3, 2, 0],
                 noise=[6, 7, 8, 8, 9, 9, 10, 10, 10, 10], tone=False),
    "hat": env([8, 5, 3, 0], noise=1, tone=False),
    # the title's melody and the jingles' harmony
    "soft": env([5, 7, 8, 9, 9, 9, 9, 8, 8, 8, 8, 8, 7]),
    # the jingles' bell
    "bell": env([14, 13, 12, 11, 10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4]),
}
INS_ORDER = list(INSTRUMENTS)

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------
BEAT = "@kick c4:2 @hat c4 @snare c4 @hat c4 @kick c4 @hat c4 @snare c4 @hat c4"
PATTERNS = {
    "rest16": "-:16",
    # in-game: bass (on C; transposed to each chord's root)
    "bass": "@bass c3:2 c4 c3 c4 c3 c4 c3 c4",
    "bass2": "@bass c3:2 c3 c4 c3 g3 c3 c4 g3",
    "beat": BEAT,
    "fill": "@kick c4:2 @hat c4 @snare c4 @hat c4 @kick c4 @snare c4:1 c4 c4:2 c4:1 c4",
    "beat0": "@kick c4:4 c4 c4 c4",      # the intro: kicks only
    # in-game lead, A section (Am F C G Am F C E)
    "l1": "@lead e5:4 a4:2 c5 e5:4 d5:2 c5",
    "l2": "c5:6 a4:2 f4:4 a4",
    "l3": "g4:4 c5:2 e5 g5:4 e5:2 c5",
    "l4": "d5:8 b4:4 g4",
    "l5": "e5:4 a4:2 c5 e5:4 g5:2 e5",
    "l6": "f5:6 e5:2 c5:4 a4",
    "l7": "g4:2 c5 e5 g5 c6:4 b5:2 g5",
    "l8": "g#5:8 e5:4 b4",
    # B section (F G Am Am F G E E)
    "l9": "a5:4 g5:2 f5 e5:4 c5",
    "l10": "d5:4 e5:2 f5 g5:8",
    "l11": "e5:4 c5:2 a4 c5:4 e5",
    "l12": "a5:12 -:4",
    "l13": "a5:4 g5:2 f5 e5:4 f5",
    "l14": "g5:4 f5:2 e5 d5:4 b4",
    "l15": "e5:4 g#5 b5 g#5",
    "l16": "e5:8 b4:4 g#4",
    # title: bass, arpeggios (minor / major on C), melody
    "pad": "@pad c3:16",
    "arpmin": "@arp c4:1 eb4 g4 c5 eb5 c5 g4 eb4 c4 eb4 g4 c5 eb5 c5 g4 eb4",
    "arpmaj": "@arp c4:1 e4 g4 c5 e5 c5 g4 e4 c4 e4 g4 c5 e5 c5 g4 e4",
    "t1": "@soft e5:8 c5:4 a4",
    "t2": "c5:12 a4:4",
    "t3": "g4:8 c5:4 e5",
    "t4": "d5:16",
    "t5": "e5:8 a5:4 g5",
    "t6": "f5:8 e5:4 c5",
    "t7": "e5:6 d5:2 c5:4 g4",
    "t8": "b4:16",
    "t9": "a4:8 d5:4 f5",
    "t10": "e5:16",
    "t11": "c5:8 f5:4 a5",
    "t12": "g#5:8 b4:4 e5",
    # level complete (speed 5)
    "doneB": "@bell g4:2 c5 e5 g5:4 e5:2 g5 c6:16",
    "doneA": "@bass c3:6 e3:2 g3:4 c3:2 g2 c3:16",
    "doneC": "@soft e4:2 g4 c5 e5:4 c5:2 e5 g5:16",
    # game over (speed 8)
    "overB": "@lead e5:4 d5 c5 b4 a4 g#4 a4:16",
    "overA": "@pad a2:16 e2:8 a2:16",
    "overC": "@soft c5:4 b4 a4 g#4 e4 e4 e4:16",
}

# chord roots as transposes of the C-based patterns
AM, F, C, G, E, DM = -3, -7, 0, -5, -8, 2
GAME_A = (["+%d" % AM if AM >= 0 else str(AM), "bass", "bass", "|"]
          + sum([[str(t) if t < 0 else "+%d" % t, b] for t, b in
                 [(AM, "bass"), (F, "bass"), (C, "bass"), (G, "bass"),
                  (AM, "bass"), (F, "bass"), (C, "bass"), (E, "bass2"),
                  (F, "bass"), (G, "bass"), (AM, "bass"), (AM, "bass2"),
                  (F, "bass"), (G, "bass"), (E, "bass"), (E, "bass2")]], []))
GAME_B = ["rest16", "rest16", "|", "+0"] + ["l%d" % i for i in range(1, 17)]
GAME_C = ["beat0", "beat", "|"] + ["beat"] * 7 + ["fill"] + ["beat"] * 7 + ["fill"]


def tr(t):
    return "+%d" % t if t >= 0 else str(t)


TITLE_CHORDS = [(AM, "arpmin"), (F, "arpmaj"), (C, "arpmaj"), (G, "arpmaj"),
                (AM, "arpmin"), (F, "arpmaj"), (C, "arpmaj"), (G, "arpmaj"),
                (DM, "arpmin"), (AM, "arpmin"), (F, "arpmaj"), (E + 12, "arpmaj")]
TITLE_A = ["|"] + sum([[tr(t if t < 12 else t - 12), "pad"] for t, _ in TITLE_CHORDS], [])
TITLE_B = ["|"] + sum([[tr(t), p] for t, p in TITLE_CHORDS], [])
TITLE_C = ["|", "+0"] + ["t%d" % i for i in range(1, 13)]

SONGS = [   # name, speed, order lists A, B, C
    ("TITLE", 7, TITLE_A, TITLE_B, TITLE_C),
    ("GAME", 6, GAME_A, GAME_B, GAME_C),
    ("DONE", 5, ["doneA"], ["doneB"], ["doneC"]),
    ("OVER", 8, ["overA"], ["overB"], ["overC"]),
]

# ---------------------------------------------------------------------------
# Sound effects: frames, tone, noise, period, dperiod, volume, dvolume
# (both 4.4: 0xC0 = 12), noise period, dnoise, next
# ---------------------------------------------------------------------------
SFX = [   # in priority order (the number is the priority)
    ("SHOT", 3, 1, 0, 36, 14, 0x90, -0x28, 0, 0, None),
    ("GEAR", 4, 1, 0, 160, -24, 0x80, -0x14, 0, 0, None),
    ("BLIP", 3, 1, 0, 90, 0, 0xA0, -0x20, 0, 0, None),
    ("SPLASH", 14, 0, 1, 0, 0, 0xC0, -0x0D, 6, 1, None),
    ("HIT", 10, 1, 1, 50, 22, 0xD0, -0x14, 4, 1, None),
    ("JUMP", 10, 1, 0, 280, -16, 0xB0, -0x08, 0, 0, None),
    ("JUMP2", 8, 1, 0, 150, -9, 0xA0, -0x0C, 0, 0, None),
    ("WAY", 5, 1, 0, 71, 0, 0xC0, 0, 0, 0, "WAY2"),
    ("POWER", 12, 1, 0, 220, -13, 0xC0, 0, 0, 0, "POWER2"),
    ("DIE", 30, 1, 0, 60, 16, 0xE0, -0x05, 0, 0, "DIE2"),
    ("SINK", 40, 1, 1, 90, 7, 0xC0, -0x04, 31, -1, None),
    # chained parts (never asked for directly)
    ("WAY2", 16, 1, 0, 47, 0, 0xC0, -0x0C, 0, 0, None),
    ("POWER2", 14, 1, 0, 110, -5, 0xC0, -0x0E, 0, 0, None),
    ("DIE2", 20, 0, 1, 0, 0, 0xB0, -0x09, 20, 0, None),
]


def note_num(tok):
    name = tok[0]
    i = 1
    n = NOTE_NAMES[name]
    while i < len(tok) and tok[i] in "#b" and not tok[i:].isdigit():
        n += 1 if tok[i] == "#" else -1
        i += 1
    octave = int(tok[i:])
    v = (octave - 1) * 12 + n
    assert 0 <= v < 0x60, tok
    return v


def compile_pattern(text):
    out = []
    dur = None
    for tok in text.split():
        if tok.startswith("@"):
            out.append(0x80 + INS_ORDER.index(tok[1:]))
            continue
        body, _, ln = tok.partition(":")
        if ln:
            d = int(ln)
            if d != dur:
                assert 1 <= d <= 32
                out.append(0x60 + d - 1)
                dur = d
        assert dur is not None, text
        if body == "-":
            out.append(0x90)
        elif body == "=":
            out.append(0x91)
        else:
            out.append(note_num(body))
    out.append(0xFF)
    return out


def rows_of(text):
    n = dur = 0
    for tok in text.split():
        if tok.startswith("@"):
            continue
        _, _, ln = tok.partition(":")
        if ln:
            dur = int(ln)
        n += dur
    return n


def db(vals):
    return "  db " + ",".join("&%02X" % (v & 0xFF) for v in vals)


def main():
    out = sys.argv[1]
    L = ["; generated by tools/gen_music.py: music and sound effects", ""]
    # tone periods of notes 0..95 (C1..B8)
    pers = [round(AY_CLOCK / 16 / (440 * 2 ** ((n - 45) / 12))) for n in range(96)]
    L.append("note_per:")
    for i in range(0, 96, 12):
        L.append("  dw " + ",".join(str(p) for p in pers[i:i + 12]))
    L.append("ins_tab:")
    L.append("  dw " + ",".join("ins_" + n for n in INS_ORDER))
    L.append("env_silent:")
    L.append(db([HOLD | TONE_OFF, 0]))
    for n in INS_ORDER:
        L.append("ins_%s:" % n)
        L.append(db(sum(INSTRUMENTS[n], [])))
    used = []
    for s in SONGS:
        for order in s[2:]:
            for e in order:
                if e in PATTERNS and e not in used:
                    used.append(e)
    assert len(used) < 128
    L.append("pat_tab:")
    for i in range(0, len(used), 8):
        L.append("  dw " + ",".join("pat_" + n for n in used[i:i + 8]))
    for n in used:
        L.append("pat_%s:" % n)
        L.append(db(compile_pattern(PATTERNS[n])))
    L.append("song_tab:")
    for i, (name, speed, *orders) in enumerate(SONGS):
        L.append("  db %d" % speed)
        L.append("  dw " + ",".join("ord_%s_%s" % (name, "ABC"[c]) for c in range(3)))
    for name, speed, *orders in SONGS:
        lengths = []
        for c, order in enumerate(orders):
            lab = "ord_%s_%s" % (name, "ABC"[c])
            L.append(lab + ":")
            vals = []
            loop = None
            rows = 0
            for e in order:
                if e == "|":
                    loop = len(vals)
                    L.append(db(vals)) if vals else None
                    vals = []
                    L.append(lab + "_loop:")
                elif e[0] in "+-":
                    t = int(e)
                    assert -32 <= t < 32
                    vals.append(0xA0 + t)
                else:
                    vals.append(used.index(e))
                    rows += rows_of(PATTERNS[e])
            if vals:
                L.append(db(vals))
            if loop is None:
                L.append(db([0xFE]))
            else:
                L.append(db([0xFF]))
                L.append("  dw %s_loop" % lab)
            lengths.append(rows)
        if len(set(lengths)) != 1:
            print("note: song %s channel lengths %s rows" % (name, lengths))
    for i, (name, *_r) in enumerate(SONGS):
        L.append("SONG_%s equ %d" % (name, i + 1))
    names = [s[0] for s in SFX]
    L.append("sfx_tab:")
    for (name, frames, tone, noise, per, dper, vol, dvol, np, dnp, nxt) in SFX:
        nx = names.index(nxt) + 1 if nxt else 0
        ctl = tone | noise << 1
        L.append("  db %d,%d" % (frames, ctl))
        L.append("  dw %d,%d" % (per, dper & 0xFFFF))
        L.append(db([vol, dvol, np, dnp, nx]) + "   ; " + name)
    for i, name in enumerate(names):
        L.append("SFX_%s equ %d" % (name, i + 1))
    L.append("SFX_SIZE equ 11")
    with open(out, "w") as f:
        f.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
