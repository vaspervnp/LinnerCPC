; ===========================================================================
; Vector primitives on the single overscan buffer
;
; Screen layout (see tools/gen_tables.py): address = page + raster*&800 + o.
; Charlines 0..20 live in page &8000 (o = 32 + 96*charline), charlines
; 21..33 in page &C000 (o = 96*(charline-21)). Moving one row down or up is
; done in place on HL; the rare charline wraps take the slow path.
;
; Objects are drawn with XOR so drawing them a second time erases them and
; leaves anything underneath (the ground) intact. Objects never share pixels
; with the ground (Linner rests just above it).
; ===========================================================================

; In: HL = pixel x (0..383), E = game y.
; Out: HL = screen address, C = pixel mask (&88 >> (x & 3)). Trashes A, B, D.
pix_addr:
  ld a,l
  and 3
  add a,pix_mask and &FF
  ld c,a
  ld a,0
  adc a,pix_mask>>8
  ld b,a
  ld a,(bc)
  ld c,a
  srl h
  rr l
  srl l                         ; L = x >> 2 (H is now 0)
  ld d,row_lo>>8
  ld a,(de)                     ; row_lo[y]
  add a,l
  ld l,a
  inc d
  ld a,(de)                     ; row_hi[y]
  adc a,0
  ld h,a
  ret

; A = pen mask for line_xor: &FF pen 3 (the game's), &F0 pen 1, &0F pen 2.
line_pen:
  ld (line_xd.pen+1),a
  ld (line_xu.pen+1),a
  ld (line_yd.pen+1),a
  ld (line_yu.pen+1),a
  ret

; E = game y, C = pen mask: XOR a full-width row (96 bytes). Trashes A, B,
; D, HL.
hline_xor:
  ld d,row_lo>>8
  ld a,(de)
  ld l,a
  inc d
  ld a,(de)
  ld h,a
  ld b,BYTES_PER_LINE
.lp:
  ld a,(hl)
  xor c
  ld (hl),a
  inc hl
  djnz .lp
  ret

; ---------------------------------------------------------------------------
; XOR line in pen 3 (or the pen set by line_pen). HL = x0, B = y0, DE = x1,
; C = y1 (game coordinates).
; Lines wider than 255 pixels are not drawn (no object needs one).
; Trashes everything except IY.
; ---------------------------------------------------------------------------
line_xor:
  push hl
  or a
  sbc hl,de
  pop hl
  jr c,.ordered                 ; x0 < x1
  ex de,hl                      ; draw left to right
  ld a,b
  ld b,c
  ld c,a
.ordered:                       ; HL = x0, DE = x1, B = y0, C = y1
  push hl
  ex de,hl
  or a
  sbc hl,de                     ; HL = dx
  ld a,l
  ld ixh,a
  ld a,h
  or a
  pop hl                        ; HL = x0
  ret nz
  ld e,b                        ; E = y0 for pix_addr
  ld a,c
  sub b                         ; dy = y1 - y0
  jr c,.up
  ld ixl,a
  call pix_addr                 ; HL = address, C = mask
  ld a,ixh
  cp ixl
  jr c,.ydown
  call .count
  jp line_xd
.ydown:
  ld a,ixl
  call .count
  jp line_yd
.up:
  neg
  ld ixl,a
  call pix_addr
  ld a,ixh
  cp ixl
  jr c,.yup
  call .count
  jp line_xu
.yup:
  ld a,ixl
  call .count
  jp line_yu
.count:                         ; A = major length -> B = A+1, E = A/2
  ld b,a
  inc b
  srl a
  ld e,a
  ret

; Inner loops. HL = address, C = mask, B = pixel count, E = error,
; IXH = dx, IXL = dy.
line_xd:
  ld a,c
.pen:
  and &FF                       ; line_pen: &F0 pen 1, &0F pen 2, &FF pen 3
  xor (hl)
  ld (hl),a
  ld a,e
  sub ixl
  jr c,.ystep
  ld e,a
.xstep:
  rrc c
  jr nc,.same
  inc hl
.same:
  djnz line_xd
  ret
.ystep:
  add a,ixh
  ld e,a
  DOWN
  jr .xstep

line_xu:
  ld a,c
.pen:
  and &FF                       ; line_pen: &F0 pen 1, &0F pen 2, &FF pen 3
  xor (hl)
  ld (hl),a
  ld a,e
  sub ixl
  jr c,.ystep
  ld e,a
.xstep:
  rrc c
  jr nc,.same
  inc hl
.same:
  djnz line_xu
  ret
.ystep:
  add a,ixh
  ld e,a
  UP
  jr .xstep

line_yd:
  ld a,c
.pen:
  and &FF                       ; line_pen: &F0 pen 1, &0F pen 2, &FF pen 3
  xor (hl)
  ld (hl),a
  ld a,e
  sub ixh
  jr nc,.noxs
  add a,ixl
  rrc c
  jr nc,.noxs
  inc hl
.noxs:
  ld e,a
  DOWN
  djnz line_yd
  ret

line_yu:
  ld a,c
.pen:
  and &FF                       ; line_pen: &F0 pen 1, &0F pen 2, &FF pen 3
  xor (hl)
  ld (hl),a
  ld a,e
  sub ixh
  jr nc,.noxs
  add a,ixl
  rrc c
  jr nc,.noxs
  inc hl
.noxs:
  ld e,a
  UP
  djnz line_yu
  ret

; The slow half of DOWNS: HL has just stepped past the charline's last
; raster row. Trashes A.
down_wrap:
  ld a,l
  add a,BYTES_PER_LINE
  ld l,a
  ld a,h
  adc a,&C0
  ld h,a
  bit 3,h
  ret z
  add a,&38                     ; charline 20 -> 21: continue at &C000
  ld h,a
  ret
