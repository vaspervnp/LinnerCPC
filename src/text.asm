; ===========================================================================
; Text: the 5x7 font (tools/gen_tables.py) in 8x8 cells, pen 3.
;
; print_hud writes (the HUD rows belong to it alone); print_xor XORs, for
; messages over the play area (print the same text again to remove it).
; Strings end with 0; codes 32..90 (space, digits, capitals, ! - . : @).
; ===========================================================================

HUD_TEXT_ROW0  equ &8000+4*&800+32  ; screen row 4, byte column 0

; HL = screen address, DE = string: print in write mode.
print_hud:
  ld a,&77                      ; ld (hl),a
  ld (txt_print.put1),a
  ld (txt_print.put2),a
  xor a                         ; nop
  ld (txt_print.put1-1),a
  ld (txt_print.put2-1),a
  jr txt_print

; HL = screen address, DE = string: print in XOR mode.
print_xor:
  ld a,&AE                      ; xor (hl)
  ld (txt_print.put1-1),a
  ld (txt_print.put2-1),a
  ld a,&77
  ld (txt_print.put1),a
  ld (txt_print.put2),a
  ; fall through

txt_print:
  ld a,(de)
  or a
  ret z
  inc de
  push de
  push hl
  sub FONT_FIRST                ; glyph address = font + 8 * code
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  ld de,font
  add hl,de
  ex de,hl                      ; DE -> glyph rows
  pop hl
  push hl
  ld b,8
.row:
  ld a,(de)
  inc de
  push de
  ld c,a
  rrca                          ; left 4 pixels
  rrca
  rrca
  rrca
  and &0F
  ld e,a
  ld d,nib_pen3>>8
  ld a,e
  add a,nib_pen3 and &FF
  ld e,a
  ld a,(de)
  nop                           ; (xor (hl) in XOR mode)
.put1:
  ld (hl),a
  inc hl
  ld a,c                        ; right 4 pixels
  and &0F
  add a,nib_pen3 and &FF
  ld e,a
  ld a,(de)
  nop
.put2:
  ld (hl),a
  dec hl
  DOWN
  pop de
  djnz .row
  pop hl
  inc hl                        ; next cell: 2 bytes right
  inc hl
  pop de
  jr txt_print

; B = game y, DE = string: XOR it centred on the screen.
text_mid:
  ld h,d
  ld l,e
  ld c,BYTES_PER_LINE/2         ; left byte column = 48 - length
.len:
  ld a,(hl)
  or a
  jr z,.got
  inc hl
  dec c
  jr .len
.got:
  ld a,c
  ; fall through
; A = byte column, B = game y, DE = string: XOR it there.
text_at:
  ld l,b
  ld h,row_lo>>8
  add a,(hl)
  ld c,a
  inc h                         ; row_hi
  ld a,(hl)
  adc a,0
  ld h,a
  ld l,c
  jp print_xor

; ---------------------------------------------------------------------------
; HUD fields. Each frame at most one field is brought up to date, one
; character at a time, so a change never costs more than ~300 NOPs.
; ---------------------------------------------------------------------------
HUD_SCORE_COL  equ 48               ; "SCORE 000000"
HUD_TIME_COL   equ 74               ; "T 000"
HUD_LIVES_COL  equ 86               ; "@x3"

hud_labels:
  ld hl,HUD_TEXT_ROW0+HUD_SCORE_COL
  ld de,txt_score
  call print_hud
  ld hl,HUD_TEXT_ROW0+HUD_TIME_COL
  ld de,txt_time
  call print_hud
  ld hl,HUD_TEXT_ROW0+HUD_LIVES_COL
  ld de,txt_lives
  call print_hud
  ld hl,hud_shown               ; force every digit to be redrawn
  ld b,HUD_DIGITS
.inv:
  ld (hl),&FF
  inc hl
  djnz .inv
  ret
txt_score: db "SCORE",0
txt_time:  db "T",0
txt_lives: db "@X",0

; The digits on screen (hud_shown) chase the wanted ones (hud_want).
; Returns NZ if it drew one this frame.
HUD_DIGITS equ 10                   ; 6 score, 3 time, 1 lives
hud_digit_col:
  db HUD_SCORE_COL+12, HUD_SCORE_COL+14, HUD_SCORE_COL+16
  db HUD_SCORE_COL+18, HUD_SCORE_COL+20, HUD_SCORE_COL+22
  db HUD_TIME_COL+4, HUD_TIME_COL+6, HUD_TIME_COL+8
  db HUD_LIVES_COL+4

hud_text_update:
  ld hl,score                   ; BCD -> one digit per byte
  ld de,hud_want
  ld b,3
.sc:
  ld a,(hl)
  rrca
  rrca
  rrca
  rrca
  and &0F
  ld (de),a
  inc de
  ld a,(hl)
  and &0F
  ld (de),a
  inc de
  inc hl
  djnz .sc
  ld a,(time_left+1)            ; time: 3 BCD digits
  and &0F
  ld (de),a
  inc de
  ld a,(time_left)
  rrca
  rrca
  rrca
  rrca
  and &0F
  ld (de),a
  inc de
  ld a,(time_left)
  and &0F
  ld (de),a
  inc de
  ld a,(lives)
  ld (de),a
  ld hl,hud_want                ; first digit that differs
  ld de,hud_shown
  ld b,0
.find:
  ld a,(de)
  cp (hl)
  jr nz,.draw
  inc hl
  inc de
  inc b
  ld a,b
  cp HUD_DIGITS
  jr nz,.find
  ret
.draw:
  ld a,(hl)
  ld (de),a
  add a,"0"
  ld (hud_char),a
  ld e,b
  ld d,0
  ld hl,hud_digit_col
  add hl,de
  ld e,(hl)
  ld hl,HUD_TEXT_ROW0
  add hl,de
  ld de,hud_char
  call print_hud
  or 1                          ; NZ: a digit was drawn
  ret
