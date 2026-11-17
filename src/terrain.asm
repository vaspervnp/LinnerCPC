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
; columns that changed (old pixel XORed off, new pixel XORed on). No pixel
; is ever erased and redrawn, so the ground cannot flicker; and since
; everything on screen is XOR, objects and ground never disturb each other.
; ===========================================================================

RING      equ &7000             ; 1024 bytes: keys, mirrored
RUNS      equ &7800             ; 1024 bytes, same layout: for each column,
RUNS_OFS  equ (RUNS-RING)>>8    ; how many columns before it share its key
GAPS      equ &7400             ; 384 x KEY_GAP: "old keys" for the first draw

; Start the level: generator at the first segment, screen ground empty.
terrain_init:
  ld hl,(lv_segs)
  ld a,(lv_key)
  ld de,0
  ; fall through
; ... or at a waypoint: HL = segment, A = the key there, DE = scroll x
; (a segment start, so this is the generator's whole state).
terrain_start:
  ld (gen_ptr),hl
  ld (gen_y+1),a
  ld a,&80                      ; half a row in, so the keys round
  ld (gen_y),a
  ex de,hl
  ld (scroll_wx),hl
  ld (gen_wx),hl
  ld (drawn_wx),hl
  ld a,&FE                      ; no column before the first
  ld (gen_prev),a
  call seg_load
  ld hl,GAPS                    ; nothing drawn yet
  ld de,GAPS+1
  ld bc,SCREEN_W-1
  ld (hl),KEY_GAP
  ldir
  xor a                         ; first draw compares against GAPS
  ld (drawn_valid),a
  jp terrain_fill

; Generate columns until the ring holds everything up to scroll_wx + 384
; and a little beyond (foes arriving at the right edge look ahead).
FILL_AHEAD equ 40
terrain_fill:
  ld hl,(scroll_wx)
  ld de,SCREEN_W+FILL_AHEAD
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

; Load the segment at gen_ptr (db len, key; a gap: db len, &FF, key). Past
; the end marker the Line runs on flat (the finish post stands at the end;
; the screen still needs ground). The slope is worked out here, once per
; segment: round((key_end - key_now) * 256 / len), exactly as level2asm.py.
seg_load:
  ld hl,(gen_ptr)
  ld a,(hl)
  or a
  jr nz,.ok
  ld a,255                      ; runout: flat ground, the marker stays
  ld (gen_len),a
  xor a
  ld (gen_type),a
  ld h,a
  ld l,a
  ld (gen_slope),hl
  ld a,(gen_y+1)
  ld (gen_end),a
  ret
.ok:
  ld (gen_len),a
  ld c,a
  inc hl
  ld a,(hl)
  inc hl
  cp KEY_GAP
  jr nz,.line
  ld (gen_type),a               ; a gap: no slope, the height after it
  ld a,(hl)
  inc hl
  ld (gen_end),a
  ld (gen_ptr),hl
  ld hl,0
  ld (gen_slope),hl
  ret
.line:
  ld (gen_ptr),hl
  ld b,a
  and &80                       ; ground or water
  ld (gen_type),a
  ld a,b
  and &7F
  ld (gen_end),a
  ld hl,gen_y+1
  sub (hl)                      ; A = rows to go (signed)
  push af
  jr nc,.abs
  neg
.abs:
  ld h,a                        ; HL = |rows| * 256 + len / 2
  ld a,c
  srl a
  ld l,a
  xor a                         ; HL /= len (C)
  ld b,16
.div:
  add hl,hl
  rla
  jr c,.sub
  cp c
  jr c,.next
.sub:
  sub c
  inc l
.next:
  djnz .div
  pop af
  jr nc,.store
  xor a                         ; going up: negative
  sub l
  ld l,a
  sbc a,a
  sub h
  ld h,a
.store:
  ld (gen_slope),hl
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
  ld a,(gen_prev)               ; run length: same key as the column before?
  cp c
  ld a,c
  ld (gen_prev),a
  ld a,0
  jr nz,.run
  ld a,(gen_run)
  inc a
  jr nz,.run
  dec a                         ; (saturates at 255)
.run:
  ld (gen_run),a
  ld e,a
  ld a,h
  add a,RUNS_OFS
  ld h,a
  ld (hl),e                     ; mirror
  dec h
  dec h
  ld (hl),e
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
; Ground rendering:
;   ground_begin                     work out what changed since drawn_wx
;   ground_cols E=first byte column, B=count
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
  ld a,h                        ; HL = -(scroll step)
  inc a
  jr nz,.noskip                 ; a huge step (never in play)
  ld a,l
  neg
  add a,3                       ; a 4-column group is unchanged when its
  jr c,.noskip                  ; right column's run reaches back step+3
  call ground_skip_on
  ld hl,(drawn_wx)
  call ring_addr
  jr .old
.first:
  call ground_skip_off
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
.noskip:
  call ground_skip_off
  ld hl,(drawn_wx)
  call ring_addr
  jr .old

; A = threshold: groups whose run length >= A may be skipped.
ground_skip_on:
  ld (ground_cols.thresh+1),a
  ld (ground_cols.thresh2+1),a
  ld a,&38                      ; jr c: test the run length
  ld (ground_cols.skipjr),a
  ret
ground_skip_off:
  ld a,&18                      ; jr: always process
  ld (ground_cols.skipjr),a
  ret

; Erase the whole Line from the screen (before a restart).
ground_wipe:
  call ground_skip_off
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

; E = first byte column, B = count (> 0). Works from the right: at each
; group of 4 columns, if the run under its right column shows the ground
; there has had the same height for step+3 columns, the whole group is
; unchanged, and so are the groups further left that the run covers: skip
; them all at once. Flat stretches cost almost nothing.
ground_cols:
  ld a,(g_active)
  or a
  ret z
  ld a,e
  add a,b
  dec a                         ; last byte column
  exx                           ; DE' = byte column, B' = ground row page
  ld e,a
  ld d,0
  ld b,ground_lo>>8
  exx
  ld l,a                        ; HL = DE = 4 * last byte column + 3
  ld h,0
  add hl,hl
  add hl,hl
  inc hl
  inc hl
  inc hl
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
  ld a,h                        ; run length under the group's right column
  add a,RUNS_OFS
  ld h,a
  ld c,(hl)
  sub RUNS_OFS
  ld h,a
  ld a,c
.thresh:
  cp 0                          ; (threshold, set by ground_begin)
.skipjr:
  jr c,.process                 ; (jr c, or jr when skipping is off)
.thresh2:
  sub 0
  srl a
  srl a
  inc a                         ; groups to skip
  cp b
  jr c,.fewer
  ret                           ; the rest of the range is unchanged
.fewer:
  ld c,a
  ld a,b
  sub c
  ld b,a
  exx
  ld a,e
  exx
  sub c
  exx
  ld e,a
  exx
  ld a,c                        ; 4 x groups (at most 64 x 4 = 256: 16-bit)
  push bc
  ld c,a
  ld b,0
  sla c
  rl b
  sla c
  rl b
  or a
  sbc hl,bc
  ex de,hl
  or a
  sbc hl,bc
  ex de,hl
  pop bc
  jr .lp
.process:
  GROUND_PX ground_pen3
  GROUND_PX ground_pen2
  GROUND_PX ground_pen1
  GROUND_PX ground_pen0
  exx
  dec e
  exx
  dec b
  jp nz,.lp
  ret
