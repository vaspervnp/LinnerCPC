; ===========================================================================
; Linner: the circle with the rebellious ray
;
; Linner stays at screen x HERO_X while the Line scrolls under him. He rests
; on the ground with every outline pixel just above it (contact_prof), so
; his XOR drawing never touches ground pixels. The ray turns with the
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

hero_init:
  ld a,1
  ld (gear),a
  ld a,MAX_GEAR_NORMAL
  if TEST_GEAR5
  ld a,GEARS
  endif
  ld (max_gear),a
  ld hl,&0100
  ld (speed),hl
  ld hl,0
  ld (hero_angle),hl
  xor a
  ld (hero_drawn),a
  call hero_contact
  ld a,(hero_cy_new)
  ld (hero_cy),a
  ret

; ---------------------------------------------------------------------------
; Input, speed, scrolling and ground contact (runs after rendering).
; ---------------------------------------------------------------------------
hero_update:
  ; gear shifts on RIGHT / LEFT presses
  ld a,(pad_new)
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
  ; speed eases towards the gear's target
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
  jr z,.speed_done
  jr nc,.too_fast
  add hl,de                     ; below target: accelerate
  ld bc,ACCEL
  add hl,bc
  jr .clamp_up
.too_fast:
  add hl,de
  ld bc,-DECEL
  add hl,bc
  push hl
  or a
  sbc hl,de
  pop hl
  jr nc,.store
  ex de,hl                      ; overshot: settle on the target
  jr .store
.clamp_up:
  push hl
  or a
  sbc hl,de
  pop hl
  jr c,.store
  ex de,hl
.store:
  ld (speed),hl
.speed_done:
  ; scroll by the speed, keeping the fraction
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
  ; roll: angle += speed * 4
  ld hl,(speed)
  add hl,hl
  add hl,hl
  ex de,hl
  ld hl,(hero_angle)
  add hl,de
  ld (hero_angle),hl
  ; rest on the ground; climbing and dropping turn the ray too
  call hero_contact
  ld a,(hero_cy_new)
  ld hl,hero_cy
  sub (hl)
  jr nc,.abs
  neg
.abs:
  add a,a                       ; 2 angle units per row
  ld hl,hero_angle+1
  add a,(hl)
  ld (hl),a
  ld a,(hero_cy_new)
  ld (hero_cy),a
  ret

; hero_cy_new = the lowest centre y that keeps the outline above the ground
; under Linner. Gap columns don't hold him up; over a full gap the centre
; stays where it is (falling arrives with Phase 4).
hero_contact:
  ld hl,(scroll_wx)
  ld de,HERO_X-LINNER_R
  add hl,de
  call ring_addr
  ld de,contact_prof
  ld b,2*LINNER_R+1
  ld c,255
.lp:
  ld a,(hl)
  cp KEY_GAP
  jr z,.skip
  and &7F
  add a,GROUND_TOP
  ex de,hl
  sub (hl)
  ex de,hl
  cp c
  jr nc,.skip
  ld c,a
.skip:
  inc hl
  inc de
  djnz .lp
  ld a,c
  inc a
  jr z,.keep
  sub 2                         ; (min + 1) - 2 = min - 1
  ld (hero_cy_new),a
  ret
.keep:
  ld a,(hero_cy)
  ld (hero_cy_new),a
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
