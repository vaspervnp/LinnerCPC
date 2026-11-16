#!/usr/bin/env python3
"""Show (or blank) the high score table in a Linner disk image.

  tools/hiscore.py build/linner.dsk          print HISCORE.DAT's table
  tools/hiscore.py --where build/linner.dsk  also say which track/sector
  tools/hiscore.py --sna x.sna x.sym         the table in a snapshot's RAM

The game finds HISCORE.DAT in the directory (track 0, sector &C1), reads its
first sector at boot and writes it back after a new entry. The sector holds
"LINNERHI", 10 entries of name (5 chars) + score (3 BCD bytes) and a
checksum; anything else (a fresh file of zeros) means "use the built-in
table"."""
import sys

TRACK_SIZE_OFF = 0x32


def sectors(d):
    """{(track, sector id): offset of its data} for a standard or extended DSK."""
    ext = d[:8] == b"EXTENDED"
    ntracks, nsides = d[0x30], d[0x31]
    out, off = {}, 0x100
    for t in range(ntracks * nsides):
        size = d[0x34 + t] * 256 if ext else d[0x32] | d[0x33] << 8
        if size == 0:
            continue
        ti = d[off:off + 256]
        p = off + 256
        for i in range(ti[0x15]):
            info = ti[0x18 + 8 * i:0x20 + 8 * i]
            n = 128 << info[3]
            out[(info[0], info[2])] = p
            p += (info[6] | info[7] << 8) if ext else n
        off += size
    return out


def find(d):
    secs = sectors(d)
    dirsec = d[secs[(0, 0xC1)]:secs[(0, 0xC1)] + 512]
    for i in range(16):
        e = dirsec[32 * i:32 * i + 32]
        name = bytes(b & 0x7F for b in e[1:12])
        if e[0] == 0 and e[12] == 0 and name == b"HISCORE DAT":
            ls = 2 * e[16]
            t, r = ls // 9, 0xC1 + ls % 9
            return t, r, secs[(t, r)]
    raise SystemExit("no HISCORE.DAT on the disk")


def checksum(table):
    a = 0xA5
    for b in table:
        a = (a + b) & 0xFF
        a = ((a << 1) | (a >> 7)) & 0xFF
    return a


def show(table):
    for i in range(10):
        e = table[8 * i:8 * i + 8]
        print(f"{i + 1:2}. {e[:5].decode('ascii', 'replace')}  {e[5:8].hex()}")


def from_sna(sna, sym):
    addr = None
    for line in open(sym):
        f = line.split()
        if f and f[0] == "HISCORES":
            addr = int(f[1].lstrip("#"), 16)
    d = open(sna, "rb").read()
    show(d[0x100 + addr:0x100 + addr + 80])


def main():
    args = sys.argv[1:]
    if args and args[0] == "--sna":
        return from_sna(args[1], args[2])
    where = "--where" in args
    args = [a for a in args if a != "--where"]
    d = open(args[0], "rb").read()
    t, r, off = find(d)
    if where:
        print(f"HISCORE.DAT: track {t}, sector &{r:02X}")
    s = d[off:off + 512]
    if s[:8] != b"LINNERHI":
        print("(no table saved yet: the game uses its built-in one)")
        return
    table = s[8:88]
    ok = checksum(table) == s[88]
    show(table)
    if not ok:
        print("BAD CHECKSUM: the game will ignore this table")


main()
