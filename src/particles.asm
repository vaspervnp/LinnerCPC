; ===========================================================================
; Warp particles: a few white streaks in the sky that rush past at a
; multiple of Linner's speed (1.5x for the first ... 4x for the last), so
; the faster he rolls, the faster and longer they get. XOR like everything
; else. To keep the frame cheap, half of them move each frame (by two
; frames' worth), and none on a frame with PART_MAX_OBJ objects alive (they
; are only decoration).
; ===========================================================================

N_PARTS     equ 6
P_ROW       equ 0               ; screen address of its row (x = 0)
P_XF        equ 2               ; x: fraction, then 16-bit pixels
P_X         equ 3
P_ADR       equ 5               ; where its streak is drawn: address and the
P_M1        equ 7               ; pixel masks of that byte and the next
P_M2        equ 8               ; (P_M1 = 0: nothing on screen)
P_SIZE      equ 9
PART_RIGHT  equ 380             ; a particle leaving on the left comes back here
PART_MAX_OBJ equ 5              ; objects alive (shots included): skip a frame

; Spread them out again (after the screen was cleared, or the level wiped
; them with particles_wipe).
particles_init:
  ld hl,parts
  ld b,N_PARTS
  ld de,20                      ; x
.lp:
  push bc
  push de
  call part_row                 ; P_ROW
  pop de
  ld (hl),0                     ; P_XF
  inc hl
  ld (hl),e                     ; P_X
  inc hl
  ld (hl),d
  inc hl
  inc hl
  inc hl
  ld (hl),0                     ; P_M1: not drawn
  inc hl
  inc hl
  ex de,hl
  ld bc,61
  add hl,bc
  ex de,hl
  pop bc
  djnz .lp
  ret

; XOR every drawn streak away (the level is about to restart).
particles_wipe:
  ld hl,parts+P_ADR
  ld b,N_PARTS
.lp:
  push bc
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld a,(hl)
  ld (hl),0
  or a
  jr z,.next
  ld c,a
  inc hl
  ld b,(hl)
  dec hl
  call part_xor
.next:
  ld bc,P_SIZE-2
  add hl,bc
  pop bc
  djnz .lp
  ret

; XOR a streak: DE = address, C = mask there, B = mask of the next byte
; (0: none). Trashes A, DE.
part_xor:
  ld a,(de)
  xor c
  ld (de),a
  ld a,b
  or a
  ret z
  inc de
  ld a,(de)
  xor b
  ld (de),a
  ret

; Render, A = objects alive: move and redraw half of the particles (the
; even ones on even frames), each by twice this frame's step.
particles_update:
  cp PART_MAX_OBJ
  ret nc
  ld hl,part_turn
  ld a,(hl)
  xor 1
  ld (hl),a
  ld hl,(speed)                 ; steps (two frames): 2 x speed x k, k =
  ld b,h                        ; 1.5, 2, 2.5 ... for particles 0, 1, 2 ...
  ld c,l
  add hl,hl                     ; (2 x speed: k = 1, before the first)
  ld de,parts
  or a
  jr z,.even
  add hl,bc                     ; the odd ones start one k higher
  ld de,parts+P_SIZE
.even:
  ld (part_step),hl
  ex de,hl                      ; HL -> the first particle
  ld b,N_PARTS/2
.lp:
  push bc
  ld e,(hl)                     ; its row
  inc hl
  ld d,(hl)
  inc hl
  push de
  ex de,hl                      ; DE -> P_XF
  ld hl,(part_step)             ; BC = its step; the next one's base skips
  ld bc,(speed)                 ; the other half's k
  add hl,bc
  push hl
  add hl,bc
  ld (part_step),hl
  pop bc
  ld a,b                        ; streak length 1..3 pixels by the step:
  srl a                         ; the mask table's row (x 8)
  srl a
  cp 3
  jr c,.len
  ld a,2
.len:
  add a,a
  add a,a
  add a,a
  ld (part_mi),a
  ex de,hl                      ; HL -> P_XF: x -= step
  ld a,(hl)
  sub c
  ld (hl),a
  inc hl
  ld a,(hl)
  sbc a,b
  ld (hl),a
  ld c,a
  inc hl
  ld a,(hl)
  sbc a,0
  ld (hl),a
  ld b,a                        ; BC = x, HL -> P_X+1
  jr nc,.inside
  pop de                        ; off the left: back on the right, on
  call part_wrap                ; another row
  push de
.inside:
  inc hl                        ; HL -> P_ADR
  ld a,c                        ; the masks: row + 2 x (x and 3)
  and 3
  add a,a
  ld e,a
  ld a,(part_mi)
  add a,e
  ld (part_mi),a
  srl b
  rr c
  srl c                         ; BC = x / 4
  ex (sp),hl                    ; HL = row, the P_ADR pointer on the stack
  add hl,bc
  ex de,hl                      ; DE = the new address
  pop hl
  push de
  ld e,(hl)                     ; the old streak off
  inc hl
  ld d,(hl)
  inc hl
  ld a,(hl)
  or a
  jr z,.off
  ld c,a
  inc hl
  ld b,(hl)
  dec hl
  call part_xor
.off:
  pop de                        ; the new one on
  dec hl
  dec hl
  ld (hl),e
  inc hl
  ld (hl),d
  inc hl
  push hl
  ld a,(part_mi)
  ld c,a
  ld b,0
  ld hl,part_masks
  add hl,bc
  ld c,(hl)
  inc hl
  ld b,(hl)
  pop hl
  ld (hl),c
  inc hl
  ld (hl),b
  inc hl                        ; HL -> the next particle
  call part_xor
  ld bc,P_SIZE                  ; skip the other half's
  add hl,bc
  pop bc
  dec b
  jp nz,.lp
  ret

; Masks of a streak of 1, 2, 3 pixels starting at pixel 0..3 of a byte:
; that byte's, then the next one's.
part_masks:
  db &88,0, &44,0, &22,0, &11,0
  db &CC,0, &66,0, &33,0, &11,&88
  db &EE,0, &77,0, &33,&88, &11,&CC

; HL -> P_X+1, BC = x (negative): x += PART_RIGHT, a new row. Out: BC = x,
; DE = the row, HL unchanged.
part_wrap:
  push hl
  ld h,b
  ld l,c
  ld bc,PART_RIGHT
  add hl,bc
  ld b,h
  ld c,l
  pop hl
  ld (hl),b
  dec hl
  ld (hl),c
  dec hl
  dec hl
  dec hl                        ; HL -> P_ROW
  push bc
  call part_row
  pop bc
  inc hl                        ; back to P_X+1
  inc hl
  ret

; HL -> P_ROW: store the address of the next row from part_heights; HL
; advances past it, DE = the row. Trashes A, C.
part_row:
  push hl
  ld hl,part_next
  ld a,(hl)
  inc a
  and 15
  ld (hl),a
  ld e,a
  ld d,0
  ld hl,part_heights
  add hl,de
  ld e,(hl)                     ; game y
  ld d,row_lo>>8
  ld a,(de)
  ld c,a
  inc d
  ld a,(de)
  ld d,a
  ld e,c
  pop hl
  ld (hl),e
  inc hl
  ld (hl),d
  inc hl
  ret

part_heights:                   ; game y, high in the sky (the ground is
  db 22, 74, 40, 98, 12, 58, 86, 30, 66, 104, 48, 18, 80, 36, 92, 54   ; >= 128)
