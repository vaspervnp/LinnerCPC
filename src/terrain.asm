; ===========================================================================
; The Line: terrain generation and flicker-free ground rendering
;
; The ground is a height map: each world column has one key byte
; (0..126 = ground at game y 128+key, bit 7 = water, &FF = gap). Slopes are
; at most 45 degrees, so one pixel per column draws a connected line.
;
; Keys are generated a few columns at a time into a 512-entry ring, written
; twice (at i and i+512) so the 384 visible columns can be read in one run.
; The ring still holds the keys of the last drawn frame (drawn_wx), so each
; frame compares old and new keys column by column and only touches the
; columns that changed (old pixel cleared, new pixel set). No pixel is ever
; erased and redrawn, so the ground cannot flicker.
; ===========================================================================

RING      equ &7000             ; 1024 bytes: keys, mirrored
GAPS      equ &7400             ; 384 x KEY_GAP: "old keys" for the first draw

; Start the level: generator at the first segment, screen ground empty.
terrain_init:
  ld hl,level1
  ld (gen_ptr),hl
  ld a,level1_start_key
  ld (gen_y+1),a
  ld a,&80                      ; half a row in, so the keys round
  ld (gen_y),a
  ld hl,0
  ld (scroll_wx),hl
  ld (gen_wx),hl
  ld (drawn_wx),hl
  call seg_load
  ld hl,GAPS                    ; nothing drawn yet
  ld de,GAPS+1
  ld bc,SCREEN_W-1
  ld (hl),KEY_GAP
  ldir
  xor a                         ; first draw compares against GAPS
  ld (drawn_valid),a
  jp terrain_fill

; Generate columns until the ring holds everything up to scroll_wx + 384.
terrain_fill:
  ld hl,(scroll_wx)
  ld de,SCREEN_W
  add hl,de
  ex de,hl                      ; DE = end
.lp:
  ld hl,(gen_wx)
  or a
  sbc hl,de
  ret z
  push de
  call gen_column
  pop de
  jr .lp

; Load the segment at gen_ptr (wrapping to the start at the end marker).
seg_load:
  ld hl,(gen_ptr)
  ld a,(hl)
  or a
  jr nz,.ok
  ld hl,level1
  ld a,(hl)
.ok:
  ld (gen_len),a
  inc hl
  ld a,(hl)
  ld (gen_type),a
  inc hl
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld (gen_slope),de
  ld a,(hl)
  ld (gen_end),a
  inc hl
  ld (gen_ptr),hl
  ret

; Emit the key for world column gen_wx and step the generator.
gen_column:
  ld a,(gen_type)
  cp KEY_GAP
  jr z,.key
  ld b,a
  ld a,(gen_y+1)
  or b
.key:
  ld c,a
  ld hl,(gen_wx)
  ld a,h
  and 1
  ld h,a
  ld de,RING
  add hl,de
  ld (hl),c
  inc h
  inc h                         ; +512: the mirror
  ld (hl),c
  ld hl,(gen_wx)
  inc hl
  ld (gen_wx),hl
  ld hl,(gen_y)
  ld de,(gen_slope)
  add hl,de
  ld (gen_y),hl
  ld hl,gen_len
  dec (hl)
  ret nz
  ld a,(gen_end)                ; snap to the exact end height
  ld (gen_y+1),a
  ld a,&80
  ld (gen_y),a
  jp seg_load

; HL = world x -> HL = ring address of that column's key.
ring_addr:
  ld a,h
  and 1
  ld h,a
  ld de,RING
  add hl,de
  ret

; ---------------------------------------------------------------------------
; Ground rendering, in three steps so Linner can be redrawn in between:
;   ground_begin                     work out what changed since drawn_wx
;   ground_cols E=first byte column, B=count   (any number of calls)
;   ground_end                       the screen now shows scroll_wx
; ---------------------------------------------------------------------------
ground_begin:
  ld a,(drawn_valid)
  or a
  jr z,.first
  ld hl,(drawn_wx)
  ld de,(scroll_wx)
  or a
  sbc hl,de
  ld a,0
  jr z,.set                     ; no scroll: nothing to do
  ld hl,(drawn_wx)
  call ring_addr
  jr .old
.first:
  ld hl,GAPS
.old:
  ld (g_old),hl
  ld hl,(scroll_wx)
  call ring_addr
  ld (g_new),hl
  ld a,1
.set:
  ld (g_active),a
  ret

; Erase the whole Line from the screen (before a restart).
ground_wipe:
  ld hl,(drawn_wx)
  call ring_addr
  ld (g_old),hl
  ld hl,GAPS
  ld (g_new),hl
  ld a,1
  ld (g_active),a
  ld e,0
  ld b,BYTES_PER_LINE
  jp ground_cols

ground_end:
  ld hl,(scroll_wx)
  ld (drawn_wx),hl
  ld a,1
  ld (drawn_valid),a
  ret

ground_cols:
  ld a,(g_active)
  or a
  ret z
  ld a,e                        ; DE' = byte column, B' = ground row table page
  exx
  ld e,a
  ld d,0
  ld b,ground_lo>>8
  exx
  ld l,e                        ; HL = DE = 4 * first byte column
  ld h,0
  add hl,hl
  add hl,hl
  ld e,l
  ld d,h
  push hl
  ld hl,(g_old)
  add hl,de
  ex de,hl                      ; DE -> old keys
  pop hl
  push de
  ld de,(g_new)
  add hl,de                     ; HL -> new keys
  pop de
.lp:
  GROUND_PX &88
  GROUND_PX &44
  GROUND_PX &22
  GROUND_PX &11
  exx
  inc e
  exx
  dec b
  jp nz,.lp
  ret
