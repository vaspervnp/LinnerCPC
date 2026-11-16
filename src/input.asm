; ===========================================================================
; Keyboard matrix scan (PSG port A through the PPI) and the combined pad
; ===========================================================================

kbd_scan:
  ld bc,&F40E                   ; PSG register 14 = port A
  out (c),c
  ld bc,&F6C0                   ; PSG: select register
  out (c),c
  xor a
  out (c),a                     ; PSG: inactive
  ld bc,&F792                   ; PPI port A = input
  out (c),c
  ld hl,keymap
  ld a,&40                      ; PSG read + line 0
  ld e,10
.line:
  ld b,PPI_C
  out (c),a
  ld b,PPI_A
  ini                           ; (HL) <- port, HL++
  inc a
  dec e
  jr nz,.line
  ld bc,&F782                   ; PPI port A = output again
  out (c),c
  ld bc,&F600
  out (c),c
  ret

; A = key code. Returns NZ if the key is held. Trashes BC, HL.
kbd_down:
  ld c,a
  rrca
  rrca
  rrca
  rrca
  and &0F
  ld hl,keymap
  add a,l
  ld l,a
  adc a,h
  sub l
  ld h,a
  ld a,c
  and 7
  ld b,a
  ld a,(hl)
  inc b
.bit:
  rrca
  djnz .bit
  ccf                           ; key down = bit 0 -> carry set
  sbc a,a                       ; A = &FF if down
  ret

; Build pad (held) and pad_new (pressed this frame) from the cursor keys,
; Z (fire), SPACE (jump) and joystick 0. The joystick's bits 0..3 (up,
; down, left, right) are already the pad's; fire 1 shoots, fire 2 jumps.
pad_read:
  call kbd_scan
  ld a,(keymap+9)               ; joystick (0 = pressed)
  cpl
  ld b,a
  and &0F
  ld c,a
  bit 5,b                       ; fire 1
  jr z,.f2
  set PAD_FIRE,c
.f2:
  bit 4,b                       ; fire 2
  jr z,.keys
  set PAD_JUMP,c
.keys:
  ld a,(keymap+0)               ; cursor up / right / down
  cpl
  ld b,a
  bit 0,b
  jr z,.k1
  set PAD_UP,c
.k1:
  bit 1,b
  jr z,.k2
  set PAD_RIGHT,c
.k2:
  bit 2,b
  jr z,.k3
  set PAD_DOWN,c
.k3:
  ld a,(keymap+1)               ; cursor left
  bit 0,a
  jr nz,.k4
  set PAD_LEFT,c
.k4:
  ld a,(keymap+8)               ; Z
  bit 7,a
  jr nz,.k5
  set PAD_FIRE,c
.k5:
  ld a,(keymap+5)               ; SPACE
  bit 7,a
  jr nz,.done
  set PAD_JUMP,c
.done:
  ld a,(pad)
  cpl
  and c
  ld (pad_new),a
  ld a,c
  ld (pad),a
  ret
