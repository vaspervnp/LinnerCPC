; ===========================================================================
; Macros (included first: rasm needs a macro defined before its use)
; ===========================================================================

; HL = screen address -> same column, next row down. Trashes A.
  macro DOWN
  ld a,h
  add a,8
  ld h,a
  and &38
  jr nz,@ok                     ; still inside the charline
  ld a,l                        ; next charline: +96, back to the page
  add a,BYTES_PER_LINE
  ld l,a
  ld a,h
  adc a,&C0
  ld h,a
  bit 3,h                       ; ran off the end of the 2K block?
  jr z,@ok
  add a,&38                     ; charline 20 -> 21: continue at &C000
  ld h,a
@ok:
  mend

; DOWN for compiled sprites: the common case inline (9 bytes), the
; charline wrap (one row in 8) in down_wrap. Trashes A.
  macro DOWNS
  ld a,h
  add a,8
  ld h,a
  and &38
  call z,down_wrap
  mend

; HL = screen address -> same column, next row up. Trashes A.
  macro UP
  ld a,h
  sub 8
  ld h,a
  and &38
  cp &38
  jr nz,@ok
  ld a,l
  sub BYTES_PER_LINE
  ld l,a
  ld a,h
  sbc a,&C0
  ld h,a
  bit 3,h                       ; borrowed from the raster bits?
  jr nz,@ok
  sub &38                       ; charline 21 -> 20: back to &8000
  ld h,a
@ok:
  mend

; Debug raster bars: border colour shows where the frame time goes.
  macro BORDER colour
  if DEBUG
  ld bc,&7F10
  out (c),c
  ld c,&40+{colour}
  out (c),c
  endif
  mend

; One ground column (pixel phase = phase): if its key changed, XOR the old
; pixel off and the new one on. XOR keeps the ground independent of the
; objects drawn over it (they are XORed too), whatever the order.
; Main set: DE -> old key, HL -> new key (both moved one column left).
; Alternate set:
; B' = ground_lo page, DE' = byte column. A gap key indexes a scratch row
; with pen bits 0, so it needs no test. ~11 NOPs unchanged, ~50 changed.
  macro GROUND_PX pentab
  ld a,(de)
  cp (hl)
  jr z,@next
  exx
  ld l,a                        ; old key
  ld h,{pentab}>>8
  ld c,(hl)                     ; its pen bits
  ld h,b
  ld a,(hl)
  inc h
  ld h,(hl)
  ld l,a
  add hl,de
  ld a,(hl)
  xor c
  ld (hl),a
  exx
  ld a,(hl)                     ; new key
  exx
  ld l,a
  ld h,{pentab}>>8
  ld c,(hl)
  ld h,b
  ld a,(hl)
  inc h
  ld h,(hl)
  ld l,a
  add hl,de
  ld a,(hl)
  xor c
  ld (hl),a
  exx
@next:
  dec hl
  dec de
  mend
