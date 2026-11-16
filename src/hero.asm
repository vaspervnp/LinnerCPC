; ===========================================================================
; Linner: the circle with the rebellious ray
;
; Linner stays at screen x HERO_X while the Line scrolls under him. He rests
; on the ground with every outline pixel just above it (contact_prof), so
; his XOR drawing never touches ground pixels while he is alive. He jumps,
; falls into gaps and gets soggy on water. The ray turns with the
; distance rolled: 256 angle units per turn, about 4 units per pixel for
; R = 10 (256 / (2 pi R) = 4.07).
; ===========================================================================

; Gear target speeds, pixels per frame in 8.8 fixed point.
gear_speed:
  dw &0000                      ; (unused gear 0)
  dw &0100, &0180, &0200, &02C0, &0380
ACCEL       equ &0006           ; per frame when below the gear's speed
DECEL       equ &000C           ; per frame when above it
MAX_GEAR_NORMAL equ 4           ; gear 5 needs the Maximum Speed powerup

; Vertical motion, rows per frame in 8.8 (game y grows downwards).
; A full jump rises 50 rows and lasts 40 frames: 40 px at gear 1, 110 at
; gear 4, 140 at gear 5. Releasing the button early cuts the climb short.
GRAVITY     equ &0040
JUMP_V      equ &FB00           ; -5.0
JUMP_CUT    equ &FE00           ; -2.0: rise speed left when jump is released
VY_MAX      equ &0600
DROP_MAX    equ 5               ; ground falling away faster than this: airborne
LAND_TOL    equ 4               ; may land up to this far below the surface
HERO_TOP    equ 18              ; highest centre (aim marker stays on screen)
HERO_LOST   equ 255-LINNER_R    ; centre at/below this: off the bottom
NO_GROUND   equ 255

; Water: circles can't swim. Rolling on a water line drags the speed down
; and soaks Linner; SOGGY_MAX frames in a row and he sinks.
WATER_DRAG  equ &0008
WATER_MIN   equ &0080
SOGGY_MAX   equ 80
SINK_SPEED  equ &0040
SINK_TIME   equ 60              ; frames from sinking to the restart
LOST_TIME   equ 25              ; frames after falling off the bottom

HERO_ALIVE   equ 0
HERO_SINKING equ 1
HERO_GONE    equ 2

hero_init:
  ld a,1
  ld (gear),a
  ld (hero_grounded),a
  ld a,MAX_GEAR_NORMAL
  if TEST_GEAR5
  ld a,GEARS
  endif
  ld (max_gear),a
  ld hl,&0100
  ld (speed),hl
  ld hl,0
  ld (hero_angle),hl
  ld (hero_vy),hl
  ld a,AIM_START
  if TEST_FRAMES
  ld a,0                        ; the test autopilot shoots straight ahead
  endif
  ld (hero_aim),a
  xor a
  ld (aim_repeat),a
  ld (marker_drawn),a
  ld (hero_drawn),a
  ld (hero_hidden),a
  ld (hero_state),a
  ld (hero_soggy),a
  ld (hero_on_water),a
  ld (hero_cy_frac),a
  call hero_contact
  ld (hero_cy),a
  ret

; ---------------------------------------------------------------------------
; Input, speed, scrolling and vertical motion (runs after rendering).
; ---------------------------------------------------------------------------
hero_update:
  ld a,(hero_state)
  or a
  jp nz,hero_dying
  call hero_controls
  call hero_speed
  call hero_scroll
  call hero_vertical
  jp hero_water

hero_controls:
  ld a,(pad_new)                ; gear shifts on RIGHT / LEFT presses
  bit PAD_RIGHT,a
  jr z,.no_up
  ld hl,max_gear
  ld a,(gear)
  cp (hl)
  jr nc,.no_up
  inc a
  ld (gear),a
.no_up:
  ld a,(pad_new)
  bit PAD_LEFT,a
  jr z,.no_down
  ld a,(gear)
  cp 2
  jr c,.no_down
  dec a
  ld (gear),a
.no_down:
  call hero_aiming
  ld a,(hero_grounded)
  or a
  jr z,.air
  ld a,(pad_new)                ; jump
  bit PAD_JUMP,a
  ret z
  xor a
  ld (hero_grounded),a
  ld hl,JUMP_V
  ld (hero_vy),hl
  ret
.air:
  ld a,(pad)                    ; released while still rising fast: cut
  bit PAD_JUMP,a
  ret nz
  ld hl,(hero_vy)
  ld de,-JUMP_CUT and &FFFF
  add hl,de                     ; vy - JUMP_CUT
  bit 7,h
  ret z
  ld hl,JUMP_CUT
  ld (hero_vy),hl
  ret

; UP / DOWN turn the aim through 0..180 degrees in 10 degree steps (UP
; towards straight up and over to behind), repeating while held. FIRE shoots.
AIM_START   equ 2               ; 20 degrees up from straight ahead
AIM_DELAY   equ 12              ; frames before a held key repeats
AIM_RATE    equ 4
hero_aiming:
  ld hl,shot_cool
  ld a,(hl)
  or a
  jr z,.cool
  dec (hl)
.cool:
  ld a,(pad)
  bit PAD_FIRE,a
  call nz,fire_shot
  ld a,(pad)
  and 1<<PAD_UP or 1<<PAD_DOWN
  ret z
  ld b,a
  ld a,(pad_new)
  and b
  ld a,AIM_DELAY
  jr nz,.turn                   ; just pressed
  ld hl,aim_repeat
  dec (hl)
  ret nz
  ld a,AIM_RATE
.turn:
  ld (aim_repeat),a
  ld hl,hero_aim
  bit PAD_UP,b
  jr z,.down
  ld a,(hl)
  cp AIM_STEPS-1
  ret nc
  inc (hl)
  ret
.down:
  ld a,(hl)
  or a
  ret z
  dec (hl)
  ret

; Speed eases towards the gear's target; on water it drains away instead.
hero_speed:
  ld a,(hero_on_water)
  or a
  jr z,.ease
  ld hl,(speed)
  ld de,-WATER_DRAG
  add hl,de
  ld de,WATER_MIN
  push hl
  or a
  sbc hl,de
  pop hl
  ret c                         ; already at the crawl
  ld (speed),hl
  ret
.ease:
  ld a,(gear)
  add a,a
  ld l,a
  ld h,0
  ld de,gear_speed
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)                     ; DE = target
  ld hl,(speed)
  or a
  sbc hl,de
  ret z
  jr nc,.too_fast
  add hl,de                     ; below target: accelerate
  ld bc,ACCEL
  add hl,bc
  push hl
  or a
  sbc hl,de
  pop hl
  jr c,.store
  ex de,hl                      ; overshot: settle on the target
  jr .store
.too_fast:
  add hl,de
  ld bc,-DECEL
  add hl,bc
  push hl
  or a
  sbc hl,de
  pop hl
  jr nc,.store
  ex de,hl
.store:
  ld (speed),hl
  ret

; Scroll the Line by the speed (keeping the fraction) and roll the ray:
; angle += speed * 4.
hero_scroll:
  ld hl,(speed)
  ld a,(scroll_frac)
  add a,l
  ld (scroll_frac),a
  ld a,h
  adc a,0
  ld e,a
  ld d,0
  ld hl,(scroll_wx)
  add hl,de
  ld (scroll_wx),hl
  call terrain_fill
  ld hl,(speed)
  add hl,hl
  add hl,hl
  ex de,hl
  ld hl,(hero_angle)
  add hl,de
  ld (hero_angle),hl
  ret

; Follow the ground, or fly and fall.
hero_vertical:
  call hero_contact
  ld c,a                        ; C = resting centre y (or NO_GROUND)
  ld a,(hero_grounded)
  or a
  jr z,.air
  ld a,c
  cp NO_GROUND
  jr z,.leave
  ld hl,hero_cy
  sub (hl)
  jr c,.follow                  ; uphill: always follow
  cp DROP_MAX+1
  jr nc,.leave                  ; the ground fell away (ledge, gap)
.follow:
  ld a,c                        ; climbing and dropping turn the ray too:
  sub (hl)                      ; 2 angle units per row
  jr nc,.abs
  neg
.abs:
  add a,a
  ld de,hero_angle+1
  ex de,hl
  add a,(hl)
  ld (hl),a
  ld a,c
  ld (de),a                     ; hero_cy = C
  ret
.leave:
  xor a
  ld (hero_grounded),a
  ld h,a
  ld l,a
  ld (hero_vy),hl
  ret
.air:
  ld a,(hero_cy)
  ld b,a                        ; B = centre y before this frame's move
  ld hl,(hero_vy)
  ld de,GRAVITY
  add hl,de
  bit 7,h
  jr nz,.vy_ok
  ld de,VY_MAX
  push hl
  or a
  sbc hl,de
  pop hl
  jr c,.vy_ok
  ex de,hl                      ; terminal velocity
.vy_ok:
  ld (hero_vy),hl
  ex de,hl
  ld hl,(hero_cy_frac)
  add hl,de
  ld (hero_cy_frac),hl
  bit 7,d
  jr z,.down
  ld a,h                        ; rising: stop at the top of the screen
  cp HERO_TOP
  ret nc
  ld a,HERO_TOP
  ld (hero_cy),a
  ld hl,0
  ld (hero_vy),hl
  ret
.down:
  ld a,c                        ; land on the Line coming from above
  cp NO_GROUND
  jr z,.lost
  ld a,h
  cp c
  jr c,.lost                    ; still above it
  ld a,c
  add a,LAND_TOL
  jr c,.land
  cp b
  jr c,.lost                    ; was already below the surface: no landing
.land:
  ld a,c
  ld (hero_cy),a
  xor a
  ld (hero_cy_frac),a
  ld h,a
  ld l,a
  ld (hero_vy),hl
  inc a
  ld (hero_grounded),a
  ret
.lost:
  ld a,(hero_cy)
  cp HERO_LOST
  ret c
  ld a,HERO_GONE                ; fell off the bottom of the Vectorverse
  ld b,LOST_TIME
  jp hero_die

; Water under Linner's centre soaks him; dry ground dries him off.
hero_water:
  xor a
  ld (hero_on_water),a
  ld a,(hero_grounded)
  or a
  jr z,.dry
  ld hl,(scroll_wx)
  ld de,HERO_X
  add hl,de
  call ring_addr
  ld a,(hl)
  cp KEY_WATER
  jr c,.dry                     ; ground
  inc a
  jr z,.dry                     ; gap
  ld a,1
  ld (hero_on_water),a
  ld hl,hero_soggy
  inc (hl)
  ld a,(hl)
  cp SOGGY_MAX
  ret c
  ld a,HERO_SINKING
  ld b,SINK_TIME
  jp hero_die
.dry:
  ld hl,hero_soggy
  ld a,(hl)
  or a
  ret z
  dec (hl)
  ret

; A = new state, B = frames until the restart.
hero_die:
  ld (hero_state),a
  ld a,b
  ld (hero_timer),a
  ld hl,0
  ld (speed),hl
  ret

hero_dying:
  ld a,(hero_state)
  cp HERO_SINKING
  jr nz,.wait
  ld hl,(hero_cy_frac)          ; sink slowly through the water line
  ld de,SINK_SPEED
  add hl,de
  ld (hero_cy_frac),hl
  ld a,h
  cp HERO_LOST
  jr c,.wait
  ld a,1
  ld (hero_hidden),a
.wait:
  ld a,(hero_state)
  cp HERO_GONE
  jr nz,.tick
  ld a,1
  ld (hero_hidden),a
.tick:
  ld hl,hero_timer
  dec (hl)
  ret nz
  jp level_restart

; A = the centre y at which Linner rests on the ground under him (every
; outline pixel just above it), or NO_GROUND over a gap.
hero_contact:
  ld hl,(scroll_wx)
  ld de,HERO_X-LINNER_R
  add hl,de
  call ring_addr
  call contact_scan             ; C = min(ground y - profile)
  ld a,c
  cp NO_GROUND
  ret z
  dec a                         ; min - 1: one row clear of the ground
  ret

; ---------------------------------------------------------------------------
; Rendering (runs right after VSYNC, well before the beam reaches Linner):
; XOR the old picture away and XOR the new one in. Between the two the
; ground under Linner is updated, so his outline never lands on a ground
; pixel that is about to be cleared (or vice versa).
; ---------------------------------------------------------------------------
hero_erase:
  ld a,(hero_drawn)
  or a
  jr z,.first
  ld a,(hero_hidden)            ; gone: erase him for good
  or a
  jr nz,.all
  ld a,(hero_drawn_cy)
  ld hl,hero_cy
  cp (hl)
  jr nz,.all
  ld a,(hero_angle+1)           ; same height: only the ray may have turned
  ld hl,hero_drawn_ang
  cp (hl)
  ld a,0
  ld (hero_redraw),a
  ret z
  inc a
  ld (hero_redraw),a
  jr .ray
.all:
  ld a,2
  ld (hero_redraw),a
  ld a,(hero_drawn_cy)
  call hero_circle
.ray:
  ld a,(hero_drawn_cy)
  ld b,a
  ld a,(hero_drawn_ang)
  jp hero_ray
.first:
  ld a,2
  ld (hero_redraw),a
  ret

; Draw what hero_erase took away, at the new position and angle.
hero_draw:
  ld a,(hero_redraw)
  or a
  ret z
  ld a,(hero_hidden)
  or a
  jr z,.show
  xor a
  ld (hero_drawn),a
  ret
.show:
  ld a,1
  ld (hero_drawn),a
  ld a,(hero_cy)
  ld (hero_drawn_cy),a
  ld a,(hero_redraw)
  cp 2
  jr nz,.ray
  ld a,(hero_cy)
  call hero_circle
.ray:
  ld a,(hero_cy)
  ld b,a
  ld a,(hero_angle+1)
  ld (hero_drawn_ang),a
  ; fall through

; A = angle, B = centre y. XOR the ray from the centre to the rim.
hero_ray:
  ld l,a
  ld h,ray_dx>>8
  ld e,(hl)                     ; dx (signed)
  inc h
  ld a,(hl)                     ; dy (signed)
  add a,b
  ld c,a                        ; y1
  ld a,e
  rla
  sbc a,a
  ld d,a                        ; sign-extend dx
  ld hl,HERO_X
  add hl,de
  ex de,hl                      ; DE = x1
  ld hl,HERO_X                  ; HL = x0, B = y0
  jp line_xor

; A = centre y. XOR the circle outline.
hero_circle:
  sub LINNER_R
  ld e,a
  ld hl,HERO_X-LINNER_R
  call pix_addr                 ; HL = top-left byte of the bounding box
  ld de,(circle_xor_tab+((HERO_X-LINNER_R) and 3)*2)
  push de
  ret                           ; jump to the sprite for this pixel phase

; ---------------------------------------------------------------------------
; Linner as a render item: the circle and ray (hero_erase / hero_draw) plus
; the aim marker, a short tick just outside the rim.
; ---------------------------------------------------------------------------
linner_erase:
  call hero_erase
  ld a,(marker_drawn)
  or a
  ret z
  ld a,(hero_hidden)
  or a
  jr nz,.off
  ld a,(marker_dcy)
  ld hl,hero_cy
  cp (hl)
  jr nz,.off
  ld a,(marker_daim)
  ld hl,hero_aim
  cp (hl)
  ret z
.off:
  xor a
  ld (marker_drawn),a
  ld a,(marker_daim)
  ld c,a
  ld a,(marker_dcy)
  jr marker_xor

linner_draw:
  call hero_draw
  ld a,(marker_drawn)
  or a
  ret nz
  ld a,(hero_hidden)
  or a
  ret nz
  inc a
  ld (marker_drawn),a
  ld a,(hero_aim)
  ld (marker_daim),a
  ld c,a
  ld a,(hero_cy)
  ld (marker_dcy),a
  ; fall through

; A = centre y, C = aim step: XOR the marker.
marker_xor:
  ld b,a
  ld e,c
  ld d,0
  ld hl,aim_y1
  add hl,de
  ld a,(hl)
  add a,b
  ld (mk_y1),a
  ld hl,aim_y0
  add hl,de
  ld a,(hl)
  add a,b
  ld (mk_y0),a
  ld hl,aim_x1
  add hl,de
  ld a,(hl)
  call .xpos
  ld (mk_x1),hl
  ld hl,aim_x0
  add hl,de
  ld a,(hl)
  call .xpos                    ; HL = x0
  ld de,(mk_x1)
  ld a,(mk_y0)
  ld b,a
  ld a,(mk_y1)
  ld c,a
  jp line_xor
.xpos:                          ; A = signed offset -> HL = HERO_X + A
  push de
  ld e,a
  rla
  sbc a,a
  ld d,a
  ld hl,HERO_X
  add hl,de
  pop de
  ret
