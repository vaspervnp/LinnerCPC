; ===========================================================================
; Objects: the Bureau's enforcers (Rectangles, Triangles) and Linner's shots
;
; Fixed slots at OBJECTS (all in one page, so a slot is named by the low
; byte of its address): 0..3 foes, 4..7 shots. Positions are world
; coordinates (x 16.8, y 8.8 game rows); the screen x is x - scroll_wx.
; Everything is drawn as compiled XOR sprites.
;
; Everything on screen is XOR (ground included), so the objects and the
; ground can be redrawn in any order without disturbing each other.
; ===========================================================================

OBJECTS     equ &7600           ; 8 slots x 22 bytes
MAX_FOES    equ 4
MAX_SHOTS   equ 4
MAX_OBJ     equ MAX_FOES+MAX_SHOTS
OBJ_SIZE    equ 22
SHOTS       equ OBJECTS+MAX_FOES*OBJ_SIZE

; slot fields
O_TYPE      equ 0
O_FLAGS     equ 1
O_XF        equ 2               ; x: fraction, then 16-bit pixels
O_X         equ 3
O_YF        equ 5               ; y: fraction, then game row (top edge)
O_Y         equ 6
O_VX        equ 7               ; 8.8 signed
O_VY        equ 9
O_DSX       equ 11              ; screen x / y where it is drawn now
O_DY        equ 13
O_TIMER     equ 14
O_BASE      equ 15              ; Triangle: centre height of its bobbing
O_NSX       equ 16              ; screen x for the next drawing
O_W         equ 18              ; size and sprite jump table, from type_info
O_H         equ 19
O_SPR       equ 20

T_RECT      equ 1
T_TRI       equ 2
T_SHOT      equ 3

F_DRAWN     equ 0               ; flag bits
F_VIS       equ 1
F_DEAD      equ 2

RECT_SPEED  equ &FF80           ; -0.5 px/frame: marching at Linner
TRI_SPEED   equ &FF00           ; -1.0
SHOT_INTERVAL   equ 8               ; frames between shots
SCORE_RECT  equ 10              ; (x10 on the display, later)
SCORE_TRI   equ 15

; type -> width, height, sprite jump table
type_info:
  db RECT_W, RECT_H
  dw rect_tab
  db TRI_W, TRI_H
  dw tri_tab
  db SHOT_W, SHOT_H
  dw shot_tab

objects_init:
  ld hl,OBJECTS
  ld de,OBJECTS+1
  ld bc,MAX_OBJ*OBJ_SIZE-1
  ld (hl),0
  ldir
  ld hl,level1_foes
  ld (spawn_ptr),hl
  ld hl,0
  ld (spawn_base),hl
  xor a
  ld (shot_cool),a
  ret

; IX = slot, A = type: set the type, size and sprite. Trashes DE, HL.
obj_settype:
  ld (ix+O_TYPE),a
  dec a
  add a,a
  add a,a
  ld e,a
  ld d,0
  ld hl,type_info
  add hl,de
  ld a,(hl)
  ld (ix+O_W),a
  inc hl
  ld a,(hl)
  ld (ix+O_H),a
  inc hl
  ld a,(hl)
  ld (ix+O_SPR),a
  inc hl
  ld a,(hl)
  ld (ix+O_SPR+1),a
  ret

; ---------------------------------------------------------------------------
; Update (after hero_update, so scroll_wx is final for this frame)
; ---------------------------------------------------------------------------
objects_update:
  call spawn_foes
  ld ix,OBJECTS
  ld b,MAX_OBJ
.lp:
  push bc
  ld a,(ix+O_TYPE)
  or a
  jr z,.next
  bit F_DEAD,(ix+O_FLAGS)
  jr nz,.dead
  cp T_RECT
  call z,rect_update
  ld a,(ix+O_TYPE)
  cp T_TRI
  call z,tri_update
  ld a,(ix+O_TYPE)
  cp T_SHOT
  call z,shot_update
  call obj_place
  jr .next
.dead:
  res F_VIS,(ix+O_FLAGS)        ; render erases it, then frees the slot
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .lp
  call shots_vs_foes
  jp foes_vs_hero

; x += vx (24-bit, vx sign-extended)
obj_move_x:
  ld a,(ix+O_XF)
  add a,(ix+O_VX)
  ld (ix+O_XF),a
  ld a,(ix+O_VX+1)
  ld c,a
  rla
  sbc a,a
  ld b,a                        ; B = sign extension
  ld a,(ix+O_X)
  adc a,c
  ld (ix+O_X),a
  ld a,(ix+O_X+1)
  adc a,b
  ld (ix+O_X+1),a
  ret

; HL = world x -> A = game y of the ground surface there, 255 over a gap.
; Trashes DE, HL.
ground_y_at:
  call ring_addr
  ld a,(hl)
  cp KEY_GAP
  ret z
  and &7F
  add a,GROUND_TOP
  ret

; IX = slot, B = width - 1, C = sample step: A = the highest ground
; surface under the object, sampled every C pixels and at its right edge
; (255 if all gaps). Trashes BC, DE, HL.
ground_under:
  ld a,255
  ld (gu_min),a
  ld d,0                        ; D = offset from the left edge
.lp:
  push de
  ld l,(ix+O_X)
  ld h,(ix+O_X+1)
  ld e,d
  ld d,0
  add hl,de
  call ground_y_at
  ld hl,gu_min
  cp (hl)
  jr nc,.keep
  ld (hl),a
.keep:
  pop de
  ld a,d
  cp b
  jr z,.done
  add a,c
  cp b
  jr c,.step
  ld a,b                        ; last sample exactly on the right edge
.step:
  ld d,a
  jr .lp
.done:
  ld a,(gu_min)
  ret

; A Rectangle marches along the Line and turns back at gaps and water.
rect_update:
  call obj_move_x
  ld l,(ix+O_X)                 ; look just past the leading edge
  ld h,(ix+O_X+1)
  ld de,-1
  bit 7,(ix+O_VX+1)
  jr nz,.ahead
  ld de,RECT_W
.ahead:
  add hl,de
  call ring_addr
  ld a,(hl)
  cp KEY_WATER
  jr c,.walk                    ; dry ground ahead
  ld a,(ix+O_VX)                ; gap or water: about turn
  cpl
  ld l,a
  ld a,(ix+O_VX+1)
  cpl
  ld h,a
  inc hl
  ld (ix+O_VX),l
  ld (ix+O_VX+1),h
.walk:
  ld b,RECT_W-1
  ld c,5
  call ground_under
  cp 255
  jr z,.fall
  sub RECT_H                    ; bottom row one above the surface
  ld (ix+O_Y),a
  xor a
  ld (ix+O_YF),a
  ld (ix+O_VY),a
  ld (ix+O_VY+1),a
  ret
.fall:
  ld l,(ix+O_VY)
  ld h,(ix+O_VY+1)
  ld de,GRAVITY
  add hl,de
  ld (ix+O_VY),l
  ld (ix+O_VY+1),h
  ex de,hl
  ld l,(ix+O_YF)
  ld h,(ix+O_Y)
  add hl,de
  ld (ix+O_YF),l
  ld (ix+O_Y),h
  ld a,h
  cp 256-RECT_H
  ret c
  set F_DEAD,(ix+O_FLAGS)       ; fell out of the Vectorverse
  ret

; A Triangle drifts towards Linner, bobbing; it never dips into the Line.
tri_update:
  call obj_move_x
  inc (ix+O_TIMER)
  ld a,(ix+O_TIMER)
  and 63
  ld e,a
  ld d,0
  ld hl,bob_tab
  add hl,de
  ld a,(ix+O_BASE)
  add a,(hl)
  ld (ix+O_Y),a
  ld b,TRI_W-1
  ld c,7
  call ground_under
  sub TRI_H+1                   ; highest allowed top
  jr c,.top                     ; (ground very high: hug the top)
  cp (ix+O_Y)
  ret nc
  ld (ix+O_Y),a
  ret
.top:
  ld (ix+O_Y),0
  ret

; A shot flies straight; the Line, the screen edges and foes stop it.
shot_update:
  call obj_move_x
  ld a,(ix+O_Y)
  ld b,a                        ; previous row
  ld a,(ix+O_YF)
  add a,(ix+O_VY)
  ld (ix+O_YF),a
  ld a,(ix+O_Y)
  adc a,(ix+O_VY+1)
  ld (ix+O_Y),a
  bit 7,(ix+O_VY+1)
  jr z,.down
  cp b                          ; going up: wrapped past the top?
  jr nc,.dead
  jr .ground
.down:
  cp b
  jr c,.dead                    ; wrapped past the bottom
  cp 256-SHOT_H
  jr nc,.dead
.ground:
  ld l,(ix+O_X)
  ld h,(ix+O_X+1)
  call ground_y_at
  dec a                         ; the shot's bottom row must stay above it
  cp (ix+O_Y)
  jr z,.dead
  ret nc
.dead:
  set F_DEAD,(ix+O_FLAGS)
  ret

; Screen position and visibility for the next drawing; objects that left
; the screen on the left (or shots leaving anywhere) are done.
obj_place:
  res F_VIS,(ix+O_FLAGS)
  bit F_DEAD,(ix+O_FLAGS)
  ret nz
  ld l,(ix+O_X)
  ld h,(ix+O_X+1)
  ld de,(scroll_wx)
  or a
  sbc hl,de
  ld (ix+O_NSX),l
  ld (ix+O_NSX+1),h
  bit 7,h
  jr nz,.left
  ld e,(ix+O_W)
  ld c,(ix+O_H)
  ld d,0
  add hl,de
  ld de,SCREEN_W+1
  or a
  sbc hl,de
  jr nc,.right                  ; not fully on screen (yet)
  ld a,(ix+O_Y)                 ; bottom edge must be on the play area
  add a,c
  jr c,.off
  set F_VIS,(ix+O_FLAGS)
  ret
.right:
  ld a,(ix+O_TYPE)
  cp T_SHOT
  ret nz                        ; foes still arriving
.off:
  set F_DEAD,(ix+O_FLAGS)
  ret
.left:
  ld a,(ix+O_TYPE)
  cp T_SHOT
  jr z,.off
  ld de,40                      ; foes: gone once well off the left edge
  add hl,de
  bit 7,h
  ret z
  jr .off

; ---------------------------------------------------------------------------
; Spawning: level1_foes is a list of (dw x, db type, db param) sorted by x,
; ended by &FFFF. A foe appears when its x reaches the right screen edge;
; the list repeats with the terrain loop.
; ---------------------------------------------------------------------------
spawn_foes:
  ld hl,(spawn_ptr)
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld a,d
  and e
  inc a
  jr nz,.entry
  ld hl,(spawn_ptr)             ; an empty list: nothing ever spawns
  ld de,level1_foes
  or a
  sbc hl,de
  ret z
  ld hl,(spawn_base)            ; end of the list: next lap of the level
  ld de,level1_length
  add hl,de
  ld (spawn_base),hl
  ld hl,level1_foes
  ld (spawn_ptr),hl
  jr spawn_foes
.entry:
  ld hl,(spawn_base)
  add hl,de                     ; world x of the next foe
  push hl
  ld de,(scroll_wx)
  or a
  sbc hl,de
  ld de,SCREEN_W
  or a
  sbc hl,de
  jr c,.due
  ld a,h
  or l
  jr z,.due
  pop hl
  ret
.due:
  ld ix,OBJECTS                 ; free foe slot?
  ld b,MAX_FOES
.find:
  ld a,(ix+O_TYPE)
  or a
  jr z,.found
  ld de,OBJ_SIZE
  add ix,de
  djnz .find
  pop hl                        ; all busy: this one never shows up
  jr .advance
.found:
  pop hl
  push ix
  pop de
  ld b,OBJ_SIZE                 ; clean slot
  push hl
  ld h,d
  ld l,e
  xor a
.clr:
  ld (hl),a
  inc hl
  djnz .clr
  pop hl
  ld (ix+O_X),l
  ld (ix+O_X+1),h
  ld hl,(spawn_ptr)
  inc hl
  inc hl
  ld a,(hl)                     ; type
  push hl
  call obj_settype
  pop hl
  inc hl
  ld a,(hl)                     ; param
  ld (ix+O_BASE),a
  ld (ix+O_Y),a
  ld hl,RECT_SPEED
  ld a,(ix+O_TYPE)
  cp T_RECT
  jr z,.speed
  ld hl,TRI_SPEED
.speed:
  ld (ix+O_VX),l
  ld (ix+O_VX+1),h
.advance:
  ld hl,(spawn_ptr)
  ld de,4
  add hl,de
  ld (spawn_ptr),hl
  jp spawn_foes

; ---------------------------------------------------------------------------
; Firing (called from hero_controls when FIRE is held)
; ---------------------------------------------------------------------------
fire_shot:
  ld a,(shot_cool)
  or a
  ret nz
  ld ix,SHOTS
  ld b,MAX_SHOTS
.find:
  ld a,(ix+O_TYPE)
  or a
  jr z,.found
  ld de,OBJ_SIZE
  add ix,de
  djnz .find
  ret                           ; all four in flight
.found:
  ld a,SHOT_INTERVAL
  ld (shot_cool),a
  ld a,T_SHOT
  call obj_settype
  xor a
  ld (ix+O_FLAGS),a
  ld (ix+O_XF),a
  ld (ix+O_YF),a
  ld a,(hero_aim)
  ld e,a
  ld d,0
  ld hl,aim_x0                  ; muzzle: just outside the rim
  add hl,de
  ld a,(hl)
  sub SHOT_W/2
  ld c,a
  rla
  sbc a,a
  ld b,a
  ld hl,(scroll_wx)
  add hl,bc
  ld bc,HERO_X
  add hl,bc
  ld (ix+O_X),l
  ld (ix+O_X+1),h
  ld hl,aim_y0
  add hl,de
  ld a,(hero_cy)
  add a,(hl)
  sub SHOT_H/2
  ld (ix+O_Y),a
  ld hl,shot_vx                 ; velocity: aim, plus Linner's own speed
  add hl,de
  add hl,de
  ld c,(hl)
  inc hl
  ld b,(hl)
  ld hl,(speed)
  add hl,bc
  ld (ix+O_VX),l
  ld (ix+O_VX+1),h
  ld hl,shot_vy
  add hl,de
  add hl,de
  ld a,(hl)
  ld (ix+O_VY),a
  inc hl
  ld a,(hl)
  ld (ix+O_VY+1),a
  ret

; ---------------------------------------------------------------------------
; Collisions
; ---------------------------------------------------------------------------
; Live, undead slot? IX = slot -> Z if it should be ignored.
obj_live:
  ld a,(ix+O_TYPE)
  or a
  ret z
  bit F_DEAD,(ix+O_FLAGS)
  jr nz,.no
  or a                          ; NZ
  ret
.no:
  xor a
  ret

; A shot's centre inside a foe's box destroys both.
shots_vs_foes:
  ld ix,OBJECTS                 ; foes outside, shots inside (usually fewer
  ld b,MAX_FOES                 ; foes are alive)
.foe:
  push bc
  call obj_live
  jr z,.nextfoe
  ld iy,SHOTS
  ld b,MAX_SHOTS
.shot:
  ld a,(iy+O_TYPE)
  or a
  jr z,.miss
  bit F_DEAD,(iy+O_FLAGS)
  jr nz,.miss
  ld a,(iy+O_Y)                 ; dy = shot centre - foe top < height?
  inc a
  sub (ix+O_Y)
  jr c,.miss
  cp (ix+O_H)
  jr nc,.miss
  ld l,(iy+O_X)                 ; dx = shot centre - foe left < width?
  ld h,(iy+O_X+1)
  inc hl
  ld e,(ix+O_X)
  ld d,(ix+O_X+1)
  or a
  sbc hl,de
  ld a,h
  or a
  jr nz,.miss
  ld a,l
  cp (ix+O_W)
  jr nc,.miss
  set F_DEAD,(ix+O_FLAGS)       ; hit!
  set F_DEAD,(iy+O_FLAGS)
  ld a,(ix+O_TYPE)
  ld e,SCORE_RECT
  cp T_RECT
  jr z,.score
  ld e,SCORE_TRI
.score:
  ld d,0
  ld hl,(score)
  add hl,de
  ld (score),hl
  jr .nextfoe
.miss:
  ld de,OBJ_SIZE
  add iy,de
  djnz .shot
.nextfoe:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .foe
  ret

; Touching a foe costs Linner his life: boxes overlap, with the circle
; approximated by a box a little smaller than itself.
HIT_R equ LINNER_R-3
foes_vs_hero:
  ld a,(hero_state)
  or a
  ret nz
  ld ix,OBJECTS
  ld b,MAX_FOES
.lp:
  push bc
  call obj_live
  jr z,.next
  bit F_VIS,(ix+O_FLAGS)
  jr z,.next
  ld c,(ix+O_W)
  ld b,(ix+O_H)
  ld l,(ix+O_NSX)               ; foe left - (Linner x + HIT_R) < 0 ?
  ld h,(ix+O_NSX+1)
  ld de,-(HERO_X+HIT_R)
  add hl,de
  bit 7,h
  jr z,.next
  ld e,c                        ; foe right - (Linner x - HIT_R) > 0 ?
  ld d,0
  add hl,de
  ld de,2*HIT_R
  add hl,de
  bit 7,h
  jr nz,.next
  ld a,h
  or l
  jr z,.next
  ld a,(hero_cy)                ; vertical overlap
  add a,HIT_R
  sub (ix+O_Y)
  jr c,.next                    ; Linner's bottom above the foe's top
  ld a,(ix+O_Y)
  add a,b
  ld c,a                        ; foe bottom
  ld a,(hero_cy)
  sub HIT_R
  jr c,.hit
  cp c
  jr nc,.next                   ; Linner's top below the foe
.hit:
  pop bc
  ld a,HERO_GONE
  ld b,LOST_TIME
  call hero_die
  ld a,1
  ld (hero_hidden),a
  ret
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .lp
  ret

; ---------------------------------------------------------------------------
; Rendering. Right after VSYNC the beam is ~2 ms from the first visible
; row: Linner and the objects go first (each erased and redrawn back to
; back), the ground last.
; ---------------------------------------------------------------------------
render:
  call linner_erase
  call linner_draw
  ld ix,OBJECTS
  ld b,MAX_OBJ
.lp:
  push bc
  ld a,(ix+O_TYPE)
  or a
  jr z,.next
  call obj_redraw
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .lp
  call ground_begin
  ld e,0
  ld b,BYTES_PER_LINE
  call ground_cols
  jp ground_end

; Move one object's picture from where it is drawn to where it should be.
obj_redraw:
  bit F_VIS,(ix+O_FLAGS)
  jr z,.hide
  bit F_DRAWN,(ix+O_FLAGS)
  jr z,.draw
  ld a,(ix+O_Y)                 ; unchanged: nothing to do
  cp (ix+O_DY)
  jr nz,.move
  ld a,(ix+O_NSX)
  cp (ix+O_DSX)
  jr nz,.move
  ld a,(ix+O_NSX+1)
  cp (ix+O_DSX+1)
  ret z
.move:
  call obj_erase
.draw:
  set F_DRAWN,(ix+O_FLAGS)
  ld l,(ix+O_NSX)
  ld h,(ix+O_NSX+1)
  ld (ix+O_DSX),l
  ld (ix+O_DSX+1),h
  ld a,(ix+O_Y)
  ld (ix+O_DY),a
  jr obj_xor
.hide:
  bit F_DRAWN,(ix+O_FLAGS)
  call nz,obj_erase
  res F_DRAWN,(ix+O_FLAGS)
  bit F_DEAD,(ix+O_FLAGS)
  ret z
  ld (ix+O_TYPE),0              ; off the screen and finished: free
  ret

obj_erase:
  ld l,(ix+O_DSX)
  ld h,(ix+O_DSX+1)
  ld a,(ix+O_DY)
  ; fall through

; IX = slot, HL = screen x (0..383), A = top row: XOR its sprite.
obj_xor:
  ld e,a
  ld a,l                        ; sprite for this pixel phase
  and 3
  add a,a
  add a,(ix+O_SPR)
  ld c,a
  ld a,(ix+O_SPR+1)
  adc a,0
  ld b,a
  ld a,(bc)
  ld (.go+1),a
  inc bc
  ld a,(bc)
  ld (.go+2),a
  srl h                         ; HL = row address + x/4
  rr l
  srl l
  ld d,row_lo>>8
  ld a,(de)
  add a,l
  ld l,a
  inc d
  ld a,(de)
  adc a,0
  ld h,a
.go:
  jp 0

; Take every object off the screen (before a restart).
objects_wipe:
  ld ix,OBJECTS
  ld b,MAX_OBJ
.lp:
  push bc
  ld a,(ix+O_TYPE)
  or a
  jr z,.next
  bit F_DRAWN,(ix+O_FLAGS)
  jr z,.next
  ld l,(ix+O_DSX)
  ld h,(ix+O_DSX+1)
  ld a,(ix+O_DY)
  call obj_xor
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .lp
  ret
