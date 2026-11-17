#!/usr/bin/env python3
"""Convert a standard CPC disk image (iDSK writes "MV - CPCEMU") into the
Extended DSK format in place.

    tools/dsk2edsk.py build/linner.dsk

Extended images list each track's size and each sector's real data length.
Some emulators (Retro Virtual Machine, for one) save a standard image that
the game wrote to as an extended one with every other track missing; given
an extended image they write it back whole.
"""
import sys

STD = b"MV - CPCEMU"
EXT_HEADER = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
CREATOR = b"LINNER make   "            # 14 bytes


def convert(d):
    if d.startswith(b"EXTENDED"):
        return d                        # already extended
    if not d.startswith(STD):
        raise SystemExit("not a CPC disk image")
    ntracks, nsides = d[0x30], d[0x31]
    tsize = d[0x32] | d[0x33] << 8
    head = bytearray(256)
    head[:34] = EXT_HEADER
    head[0x22:0x30] = CREATOR
    head[0x30], head[0x31] = ntracks, nsides
    body = bytearray()
    for t in range(ntracks * nsides):
        blk = bytearray(d[0x100 + t * tsize:0x100 + (t + 1) * tsize])
        if len(blk) < 256 or not blk.startswith(b"Track-Info"):
            head[0x34 + t] = 0         # unformatted track
            continue
        size = 256
        for i in range(blk[0x15]):
            info = 0x18 + 8 * i
            n = 128 << blk[info + 3]
            blk[info + 6], blk[info + 7] = n & 0xFF, n >> 8
            size += n
        size = (size + 255) // 256 * 256
        head[0x34 + t] = size // 256
        body += blk[:size].ljust(size, b"\0")
    return bytes(head) + bytes(body)


def main():
    for path in sys.argv[1:]:
        d = open(path, "rb").read()
        e = convert(d)
        open(path, "wb").write(e)


if __name__ == "__main__":
    main()
