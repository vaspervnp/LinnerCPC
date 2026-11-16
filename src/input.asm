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

; Build pad (held) and pad_new (pressed this frame) from cursor keys,
; joystick 0, SPACE (fire) and COPY (jump).
pad_table:
  db KEY_UP,    JOY_UP,    1<<PAD_UP
  db KEY_DOWN,  JOY_DOWN,  1<<PAD_DOWN
  db KEY_LEFT,  JOY_LEFT,  1<<PAD_LEFT
  db KEY_RIGHT, JOY_RIGHT, 1<<PAD_RIGHT
  db KEY_SPACE, JOY_FIRE1, 1<<PAD_FIRE
  db KEY_COPY,  JOY_FIRE2, 1<<PAD_JUMP
PAD_ENTRIES equ ($-pad_table)/3

pad_read:
  call kbd_scan
  ld ix,pad_table
  ld d,0                        ; new pad bits
  ld e,PAD_ENTRIES
.entry:
  ld a,(ix+0)
  call kbd_down
  jr nz,.on
  ld a,(ix+1)
  call kbd_down
  jr z,.next
.on:
  ld a,d
  or (ix+2)
  ld d,a
.next:
  inc ix
  inc ix
  inc ix
  dec e
  jr nz,.entry
  ld a,(pad)
  cpl
  and d
  ld (pad_new),a
  ld a,d
  ld (pad),a
  ret
