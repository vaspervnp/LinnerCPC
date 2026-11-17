; ===========================================================================
; Objects: the Bureau's enforcers (Rectangles, Triangles), Rhombus
; powerups, spike traps, the finish post, and Linner's shots
;
; Fixed slots at OBJECTS: 0..5 "things" from the level, 6..9 shots. Positions are world
; coordinates (x 16.8, y 8.8 game rows); the screen x is x - scroll_wx.
; Everything is drawn as compiled XOR sprites.
;
; Everything on screen is XOR (ground included), so the objects and the
; ground can be redrawn in any order without disturbing each other.
; ===========================================================================

OBJECTS     equ &7600           ; 9 slots x 22 bytes
MAX_FOES    equ 6               ; things from the level (foes, items, traps)
MAX_SHOTS   equ 3               ; (a 4th cost ~900 us a frame: see level2asm.py)
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

T_RECT      equ 1               ; foes (shots destroy them)
T_TRI       equ 2
T_SHOT      equ 3
T_FAST      equ 4               ; Rhombus: Max Speed
T_PHASE     equ 5               ; Rhombus: Phase Out
T_SPIKE     equ 6               ; trap on the Line
T_GOAL      equ 7               ; the finish post
T_WAY       equ 8               ; a waypoint post (both: no collisions)

F_DRAWN     equ 0               ; flag bits
F_VIS       equ 1
F_DEAD      equ 2

; Rectangles march at Linner at 0.5 px/frame, Triangles drift at 1.0 (on
; hard: p_rect, p_tri hold the difficulty's)
SHOT_GAP_MIN    equ 4               ; frames between shots, at least (shot_gap)
SCORE_RECT  equ &10             ; points, BCD
SCORE_TRI   equ &15

; type -> width, height, sprite jump table
type_info:
  db RECT_W, RECT_H
  dw rect_tab
  db TRI_W, TRI_H
  dw tri_tab
  db SHOT_W, SHOT_H
  dw shot_tab
  db RHOMB_SPEED_W, RHOMB_SPEED_H
  dw rhomb_speed_tab
  db RHOMB_PHASE_W, RHOMB_PHASE_H
  dw rhomb_phase_tab
  db SPIKE_W, SPIKE_H
  dw spike_tab
  db GOAL_W, GOAL_H
  dw goal_tab
  db WAY_W, WAY_H
  dw way_tab

objects_init:
  call objects_clear
  ld hl,(lv_foes)
  ld de,0
  jr objects_start
objects_clear:
  ld hl,OBJECTS
  ld de,OBJECTS+1
  ld bc,MAX_OBJ*OBJ_SIZE-1
  ld (hl),0
  ldir
  ret
; ... a waypoint's (after objects_clear): HL = foe record, DE = x of the
; record before it.
objects_start:
  ld (spawn_ptr),hl
  ex de,hl
  ld (spawn_base),hl
  ld (spawn_x),hl
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
  add a,a                       ; dispatch on the type
  ld e,a
  ld d,0
  ld hl,update_jump-2
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld hl,.placed
  push hl
  ex de,hl
  ld a,(ix+O_TYPE)
  jp (hl)
.placed:
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
  jp things_vs_hero

update_jump:
  dw rect_update, tri_update, shot_update
  dw thing_update, thing_update, thing_update, thing_update, thing_update

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
  ld de,(p_gravity)
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

; Rhombuses hover, bobbing gently; spikes and the finish post sit on the
; Line (settled once, on their first update).
thing_update:
  cp T_SPIKE
  jr nc,.settle
  inc (ix+O_TIMER)              ; Rhombus: +-3 rows
  ld a,(ix+O_TIMER)
  and 63
  ld e,a
  ld d,0
  ld hl,bob_tab
  add hl,de
  ld a,(hl)
  sra a
  sra a
  add a,(ix+O_BASE)
  ld (ix+O_Y),a
  ret
.settle:
  ld a,(ix+O_TIMER)
  or a
  ret nz
  inc (ix+O_TIMER)
  ld a,(ix+O_W)
  dec a
  ld b,a
  ld c,4
  call ground_under
  sub (ix+O_H)
  ld (ix+O_Y),a
  ret

; A shot flies straight; the Line, the screen edges and foes stop it. On
; screen it keeps its aim velocity: each frame its x speed is the aim's
; (O_SHOT_VX) plus Linner's current one, so a shot fired in a low gear
; doesn't crawl (and hold its slot) once the gears climb.
O_SHOT_VX   equ O_TIMER         ; (word: O_TIMER, O_BASE)
shot_update:
  ld l,(ix+O_SHOT_VX)
  ld h,(ix+O_SHOT_VX+1)
  ld de,(speed)
  add hl,de
  ld (ix+O_VX),l
  ld (ix+O_VX+1),h
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

; The finish and waypoint posts: not compiled sprites (memory) but a small
; XOR loop: a 1-pixel post with a 4-pixel flag on its first POST_FLAG rows,
; right of the post (pen 3). The finish post is the taller one. One entry
; per pixel phase (goal_tab, way_tab).
GOAL_W      equ 5
GOAL_H      equ 48
WAY_W       equ 5
WAY_H       equ 28
POST_FLAG   equ 6
goal_tab:
  dw goal_p0, goal_p1, goal_p2, goal_p3
way_tab:
  dw way_p0, way_p1, way_p2, way_p3
goal_p0:
  ld a,GOAL_H-POST_FLAG
  jr post_p0
goal_p1:
  ld a,GOAL_H-POST_FLAG
  jr post_p1
goal_p2:
  ld a,GOAL_H-POST_FLAG
  jr post_p2
goal_p3:
  ld a,GOAL_H-POST_FLAG
  jr post_p3
way_p0:
  ld a,WAY_H-POST_FLAG
post_p0:
  ld de,&7788                   ; D = flag in the post's byte, E = next byte
  ld c,&88                      ; C = the post pixel
  jr post_xor
way_p1:
  ld a,WAY_H-POST_FLAG
post_p1:
  ld de,&33CC
  ld c,&44
  jr post_xor
way_p2:
  ld a,WAY_H-POST_FLAG
post_p2:
  ld de,&11EE
  ld c,&22
  jr post_xor
way_p3:
  ld a,WAY_H-POST_FLAG
post_p3:
  ld de,&00FF
  ld c,&11
post_xor:                       ; HL = top-left byte, A = rows below the flag
  push af
  ld b,POST_FLAG
.flag:
  ld a,c
  or d
  xor (hl)
  ld (hl),a
  inc hl
  ld a,(hl)
  xor e
  ld (hl),a
  dec hl
  DOWNS
  djnz .flag
  pop af
  ld b,a
.post:
  ld a,(hl)
  xor c
  ld (hl),a
  DOWNS
  djnz .post
  ret

; ---------------------------------------------------------------------------
; Spawning: the level's foe list (levelN_foes, sorted by x) holds records
; db dx, tb [, param]: dx = pixels on from the previous record, tb = type
; (0: just a step) + 16 x seconds for a Rhombus, param (Triangle, Rhombus)
; = the top row of its centre. db 0,&FF ends it. A thing appears when its
; x reaches the right screen edge. spawn_base = x of the previous record.
; ---------------------------------------------------------------------------
spawn_foes:
  ld hl,(spawn_ptr)
  ld e,(hl)
  inc hl
  ld a,(hl)
  inc a
  ret z                         ; the end of the list
  ld d,0
  ld hl,(spawn_base)
  add hl,de                     ; world x of the next record
  ld (spawn_x),hl
  ld de,(scroll_wx)
  or a
  sbc hl,de
  ld de,SCREEN_W
  or a
  sbc hl,de
  jr c,.due
  ld a,h
  or l
  ret nz
.due:
  ld hl,(spawn_ptr)
  inc hl
  ld a,(hl)
  and 15
  jr z,.advance                 ; a step
  ld ix,OBJECTS                 ; free foe slot?
  ld b,MAX_FOES
.find:
  ld a,(ix+O_TYPE)
  or a
  jr z,.found
  ld de,OBJ_SIZE
  add ix,de
  djnz .find
  jr .advance                   ; all busy: this one never shows up
.found:
  push ix                       ; clean slot
  pop hl
  ld b,OBJ_SIZE
  xor a
.clr:
  ld (hl),a
  inc hl
  djnz .clr
  ld hl,(spawn_x)
  ld (ix+O_X),l
  ld (ix+O_X+1),h
  ld hl,(spawn_ptr)
  inc hl
  ld a,(hl)                     ; type + seconds
  inc hl
  push hl
  ld c,a
  rrca
  rrca
  rrca
  rrca
  and 15
  ld (ix+O_VY),a                ; a Rhombus keeps its seconds here
  ld a,c
  and 15
  call obj_settype
  pop hl
  ld a,(ix+O_TYPE)
  call spawn_param
  jr nc,.noparam
  ld a,(hl)                     ; param
  ld (ix+O_BASE),a
  ld (ix+O_Y),a
.noparam:
  ld hl,(p_rect)
  ld a,(ix+O_TYPE)
  cp T_RECT
  jr z,.speed
  ld hl,(p_tri)
  cp T_TRI
  jr z,.speed
  ld hl,0                       ; items, traps and the post stay put
.speed:
  ld (ix+O_VX),l
  ld (ix+O_VX+1),h
.advance:
  ld hl,(spawn_x)
  ld (spawn_base),hl
  ld hl,(spawn_ptr)
  inc hl
  ld a,(hl)
  inc hl
  and 15
  call spawn_param
  jr nc,.next
  inc hl
.next:
  ld (spawn_ptr),hl
  jp spawn_foes

; A = type: carry if its record has a param byte (Triangle, Rhombus).
spawn_param:
  cp T_TRI
  scf
  ret z
  cp T_FAST
  scf
  ret z
  cp T_PHASE
  scf
  ret z
  or a
  ret

; ---------------------------------------------------------------------------
; Firing (automatic: called from hero_aiming every frame)
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
  call shot_gap
  ld (shot_cool),a
  ld a,SFX_SHOT
  call sfx_play
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
  ld (ix+O_SHOT_VX),c
  ld (ix+O_SHOT_VX+1),b
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

; Frames until the next shot: a third of this one's flight to the screen
; edge or the top (gen_tables: shot_gap_x / shot_gap_y), at least
; SHOT_GAP_MIN. Shots then come evenly: by the time the 4th is due, the
; 1st has gone. -> A. Keeps IX.
shot_gap:
  ld a,(hero_aim)
  ld e,a
  ld d,0
  ld hl,shot_gap_y
  add hl,de
  ld c,(hl)                     ; C = 256 / (3 * vy), 0 = level shot
  ld hl,shot_gap_x
  add hl,de
  ld b,(hl)                     ; B = x-limited frames / 3
  ld a,c
  or a
  jr z,.min
  ld hl,aim_y0
  add hl,de
  ld a,(hero_cy)
  add a,(hl)
  sub SHOT_H/2                  ; muzzle row (as fire_shot puts it)
  ld e,a                        ; HL = E * C (8 x 8)
  ld hl,0
  ld d,h
  ld a,8
.mul:
  add hl,hl
  rl c
  jr nc,.skip
  add hl,de
.skip:
  dec a
  jr nz,.mul
  ld a,h                        ; y-limited frames / 3
  cp b
  jr nc,.min
  ld b,a
.min:
  ld a,b
  cp SHOT_GAP_MIN
  ret nc
  ld a,SHOT_GAP_MIN
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
  ld a,(ix+O_TYPE)
  cp T_TRI+1
  jr nc,.nextfoe                ; only foes can be shot
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
  ld a,SFX_HIT
  call sfx_play
  ld a,(ix+O_TYPE)
  cp T_RECT
  ld a,SCORE_RECT
  jr z,.score
  ld a,SCORE_TRI
.score:
  call score_add
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

; Touching things: foes and spikes cost Linner his life (unless he is
; phased out), Rhombuses give their power. Boxes overlap, with the circle
; approximated by a box a little smaller than itself.
HIT_R equ LINNER_R-3
things_vs_hero:
  ld a,(game_state)
  cp GS_PLAY
  ret nz
  ld a,(hero_state)
  or a
  ret nz
  ld ix,OBJECTS
  ld b,MAX_FOES
.lp:
  push bc
  call obj_live
  jp z,.next
  bit F_VIS,(ix+O_FLAGS)
  jp z,.next
  ld a,(ix+O_NSX+1)             ; quick rejects: far right, or entirely
  or a                          ; left or right of Linner
  jp nz,.next
  ld a,(ix+O_NSX)
  cp HERO_X+HIT_R
  jp nc,.next
  add a,(ix+O_W)
  cp HERO_X-HIT_R+1
  jp c,.next
  ld a,(ix+O_TYPE)
  cp T_GOAL
  jp nc,.next                   ; the posts
  ld c,(ix+O_W)
  ld b,(ix+O_H)
  ld l,(ix+O_NSX)               ; left - (Linner x + HIT_R) < 0 ?
  ld h,(ix+O_NSX+1)
  ld de,-(HERO_X+HIT_R)
  add hl,de
  bit 7,h
  jp z,.next
  ld e,c                        ; right - (Linner x - HIT_R) > 0 ?
  ld d,0
  add hl,de
  ld de,2*HIT_R
  add hl,de
  bit 7,h
  jp nz,.next
  ld a,h
  or l
  jp z,.next
  ld a,(hero_cy)                ; vertical overlap
  add a,HIT_R
  sub (ix+O_Y)
  jp c,.next                    ; Linner's bottom above its top
  ld a,(ix+O_Y)
  add a,b
  ld c,a                        ; its bottom
  ld a,(hero_cy)
  sub HIT_R
  jr c,.touch
  cp c
  jp nc,.next                   ; Linner's top below it
.touch:
  ld a,(ix+O_TYPE)
  cp T_FAST
  jr z,.fast
  cp T_PHASE
  jr z,.phase
  call hero_phased              ; foe or spike: a ghost passes through
  jr z,.next
  pop bc
  ld a,HERO_GONE
  ld b,LOST_TIME
  call hero_die
  ld a,1
  ld (hero_hidden),a
  ret
.fast:
  ld a,SFX_POWER
  call sfx_play
  set F_DEAD,(ix+O_FLAGS)
  ld a,(ix+O_VY)                ; its seconds
  call powerup_fast
  jr .next
.phase:
  ld a,SFX_POWER
  call sfx_play
  set F_DEAD,(ix+O_FLAGS)
  ld a,(ix+O_VY)
  call powerup_phase
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  dec b
  jp nz,.lp
  ret

; ---------------------------------------------------------------------------
; Rendering. Right after VSYNC the beam is ~2 ms from the first visible
; row: Linner and the objects go first (each erased and redrawn back to
; back), the ground last.
; ---------------------------------------------------------------------------
render:
  call linner_erase
  call linner_draw
  xor a
  ld (part_busy),a
  ld ix,OBJECTS
  ld b,MAX_OBJ
.lp:
  push bc
  ld a,(ix+O_TYPE)
  or a
  jr z,.next
  ld hl,part_busy               ; (the particles rest on busy frames)
  inc (hl)
  call obj_redraw
.next:
  ld de,OBJ_SIZE
  add ix,de
  pop bc
  djnz .lp
  ld a,(frame_late)             ; behind (a picture was dropped): no
  or a                          ; particles this time
  jr nz,.noparts
  ld a,(part_busy)
  call particles_update
.noparts:
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
