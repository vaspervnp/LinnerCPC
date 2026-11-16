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

; One ground column (pixel mask = mask): if its key changed, clear the old
; pixel and set the new one. Main set: DE -> old key, HL -> new key (both
; advanced). Alternate set: B' = ground_lo page, DE' = byte column.
; Gap keys index a scratch row, so they need no test. ~11 NOPs unchanged,
; ~55 changed.
  macro GROUND_PX mask
  ld a,(de)
  cp (hl)
  jr z,@next
  exx
  ld l,a                        ; old key -> address of its pixel
  ld h,b
  ld a,(hl)
  inc h
  ld h,(hl)
  ld l,a
  add hl,de
  ld a,(hl)
  and {mask} xor &FF
  ld (hl),a
  exx
  ld a,(hl)                     ; new key
  exx
  ld l,a
  ld h,b
  cp KEY_WATER
  jr c,@ground
  ld a,(hl)                     ; water (or gap): pen 2
  inc h
  ld h,(hl)
  ld l,a
  add hl,de
  ld a,(hl)
  and {mask} xor &FF
  or {mask} and &0F
  ld (hl),a
  exx
  jr @next
@ground:                        ; ground: pen 1
  ld a,(hl)
  inc h
  ld h,(hl)
  ld l,a
  add hl,de
  ld a,(hl)
  and {mask} xor &FF
  or {mask} and &F0
  ld (hl),a
  exx
@next:
  inc hl
  inc de
  mend
