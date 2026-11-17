; ===========================================================================
; High scores: the Top 10 table, the title screen that shows it, and the
; name entry after a game good enough for it. The table is saved to
; HISCORE.DAT on the disk (disk.asm) after every new entry.
;
;   GS_TITLE  title + table; FIRE (or JUMP) starts a game
;   GS_ENTRY  5-letter name: UP/DOWN pick a letter (held: repeats),
;             RIGHT/FIRE next, LEFT back; or just type it (DEL deletes,
;             RETURN/ENTER or FIRE on the last letter finishes)
; ===========================================================================

HS_COUNT    equ 10
HS_SIZE     equ 8               ; name (5 characters) + score (3 BCD bytes)
HS_NAME     equ 5
TITLE_LOCK  equ 25              ; frames before the title takes input
HS_ROW_Y    equ 36              ; game y of the first table row (10 apart)
HS_ROW_DY   equ 13
HS_ROW_COL  equ 29              ; "10. ABCDE  001234 H": 19 characters
NAME_Y      equ 120
NAME_COL    equ 39              ; 5 letters, one cell apart
CURSOR_Y    equ NAME_Y+10
SAVE_Y      equ 178             ; "SAVING..." (above the horizon)

hs_defaults:
  db "CIRCA",&00,&10,&00
  db "ROLLY",&00,&09,&00
  db "ARCUS",&00,&08,&00
  db "LINEA",&00,&07,&00
  db "ORBIT",&00,&06,&00
  db "SPOKE",&00,&05,&00
  db "RADIX",&00,&04,&00
  db "DISKO",&00,&03,&00
  db "WHEEL",&00,&02,&00
  db "TRACE",&00,&01,&00
hs_magic: db "LINNERHI"

; Boot: the built-in table, then the disk's if it holds a good one.
hiscore_init:
  ld a,&FF                      ; HISCORE.DAT not found (yet)
  ld (disk_track),a
  ld hl,hs_defaults
  ld de,hiscores
  ld bc,HS_COUNT*HS_SIZE
  ldir
  if TEST_FRAMES
  if TEST_HISCORE == 0
  ret                           ; scripted demos run without a disk
  endif
  endif
  call disk_load
  ret nc
  ld hl,SECTOR_BUF              ; "LINNERHI", table, checksum
  ld de,hs_magic
  ld b,8
.magic:
  ld a,(de)
  cp (hl)
  ret nz
  inc hl
  inc de
  djnz .magic
  push hl
  call hs_checksum
  pop hl
  cp (ix+0)
  ret nz
  ld de,hiscores
  ld bc,HS_COUNT*HS_SIZE
  ldir
  ret

; HL = the table in the sector: A = its checksum, IX -> the byte after it.
hs_checksum:
  ld b,HS_COUNT*HS_SIZE
  ld a,&A5
.lp:
  add a,(hl)
  rlca
  inc hl
  djnz .lp
  push hl
  pop ix
  ret

; Write the table to the disk (when we know where HISCORE.DAT is).
hiscore_save:
  ld hl,SECTOR_BUF
  ld de,SECTOR_BUF+1
  ld bc,511
  ld (hl),0
  ldir
  ld hl,hs_magic
  ld de,SECTOR_BUF
  ld bc,8
  ldir
  ld hl,hiscores
  ld bc,HS_COUNT*HS_SIZE
  ldir
  ld hl,SECTOR_BUF+8
  call hs_checksum
  ld (ix+0),a
  jp disk_save

; A = place (0..9) the current score earns, HS_COUNT if none.
hiscore_rank:
  ld hl,hiscores+HS_NAME
  ld b,0
.lp:
  push hl
  ld de,score
  ld a,(de)
  cp (hl)
  jr nz,.diff
  inc de
  inc hl
  ld a,(de)
  cp (hl)
  jr nz,.diff
  inc de
  inc hl
  ld a,(de)
  cp (hl)
.diff:
  pop hl
  jr z,.next                    ; a tie keeps the older entry above
  jr nc,.found
.next:
  ld de,HS_SIZE
  add hl,de
  inc b
  ld a,b
  cp HS_COUNT
  jr nz,.lp
.found:
  ld a,b
  ret

; Put entry_name and the score in at place entry_rank.
hiscore_insert:
  ld a,(entry_rank)
  ld c,a
  ld a,HS_COUNT-1
  sub c
  jr z,.put
  add a,a                       ; entries rank..8 move down one
  add a,a
  add a,a
  ld c,a
  ld b,0
  ld hl,hiscores+(HS_COUNT-1)*HS_SIZE-1
  ld de,hiscores+HS_COUNT*HS_SIZE-1
  lddr
.put:
  ld a,(entry_rank)
  call hs_entry
  ex de,hl
  ld hl,entry_name
  ld bc,HS_NAME
  ldir
  ld hl,score
  ld c,3
  ldir
  ; fall through
; Mark the new entry with the difficulty: 2 - difficulty (so 0 = hard, as
; every table saved before there were difficulties) in bit 7 of its first
; two letters.
hs_mark:
  ld a,(entry_rank)
  call hs_entry
  ld a,(difficulty)
  cpl
  add a,3
  ld c,a
  rrca
  and &80
  or (hl)
  ld (hl),a
  inc hl
  ld a,c
  rrca
  rrca
  and &80
  or (hl)
  ld (hl),a
  ret

; A = place: HL -> its entry. Trashes A only.
hs_entry:
  add a,a
  add a,a
  add a,a
  add a,hiscores and &FF
  ld l,a
  adc a,hiscores>>8
  sub l
  ld h,a
  ret

; ---------------------------------------------------------------------------
; Screens
; ---------------------------------------------------------------------------

; Black out and clear the whole screen; nothing of the game is drawn now.
screen_clear:
  call palette_black
  call cls
  xor a
  ld (hero_drawn),a
  ld (marker_drawn),a
  ld (drawn_valid),a
  ld (hud_soggy),a
  ld hl,hud_box
  ld b,GEARS
.box:
  ld (hl),a
  inc hl
  djnz .box
  ld hl,0
  ld (msg_cur),hl
  inc a
  ld (hero_hidden),a
  call particles_init
  jp objects_init

; A = place to show highlighted (blinking), &FF for none.
title_start:
  ld (title_hl),a
  call screen_clear
  call menu_world               ; the vector world under the words
  ld b,4
  ld de,txt_title
  call text_mid
  ld a,PEN1_MASK                ; the Line under the title
  call line_pen
  ld hl,96
  ld de,287
  ld bc,16*256+16
  call line_xor
  ld a,PEN3_MASK
  call line_pen
  ld b,24
  ld de,txt_hiscores
  call text_mid
  xor a
.rows:
  push af
  call hs_row_xor
  pop af
  inc a
  cp HS_COUNT
  jr nz,.rows
  call title_press
  call title_diff
  ld b,164
  ld de,txt_help1
  call text_mid
  ld b,174
  ld de,txt_help2
  call text_mid
  ld b,184
  ld de,txt_help3
  call text_mid
  xor a
  ld (title_tick),a
  ld a,GS_TITLE
  ld b,TITLE_LOCK
  call game_state_set
  call wait_frame
  ld hl,menu_palette
  jp palette_hl

title_press:
  ld b,140
  ld de,txt_press
  jp text_mid

; XOR "DIFFICULTY  < MEDIUM >" (LEFT / RIGHT change it on the title).
title_diff:
  ld a,(difficulty)
  ld l,a
  add a,a
  add a,l
  add a,a                       ; * 6
  ld l,a
  ld h,0
  ld de,txt_diffs
  add hl,de
  ld de,txt_diff+14
  ld bc,6
  ldir
  ld b,152
  ld de,txt_diff
  jp text_mid

; A = place: XOR its row of the table, "10. ABCDE  001234".
hs_row_xor:
  push af
  ld c,a
  ld de,hs_row
  ld a," "                      ; place, 1-based, right-aligned
  inc c
  ld b,"1"
  ld (de),a
  ld a,c
  cp 10
  jr nz,.one
  ld a,b
  ld (de),a
  ld c,0
.one:
  inc de
  ld a,c
  add a,"0"
  ld (de),a
  inc de
  ld a,"."
  ld (de),a
  inc de
  ld a," "
  ld (de),a
  inc de
  pop af
  push af
  call hs_entry
  ld bc,HS_NAME
  ldir
  push hl                       ; the difficulty rides in bit 7 of the
  ld hl,hs_row+4                ; first two letters (hs_mark)
  ld b,2
.mark:
  rl (hl)
  rr c
  srl (hl)
  inc hl
  djnz .mark
  ld a,c
  rlca
  rlca
  and 3
  ld c,a                        ; C = 0 hard, 1 medium, 2 easy
  pop hl
  ld a," "
  ld (de),a
  inc de
  ld (de),a
  inc de
  call bcd_str                  ; HL -> the score
  ld a," "
  ld (de),a
  inc de
  ld hl,txt_marks
  ld b,0
  add hl,bc
  ld a,(hl)
  ld (de),a
  inc de
  xor a
  ld (de),a
  pop af
  ld c,a                        ; y = HS_ROW_Y + 10 * place
  add a,a
  add a,a
  add a,c
  add a,a
  add a,HS_ROW_Y
  ld b,a
  ld a,HS_ROW_COL
  ld de,hs_row
  jp text_at

; HL -> 3 BCD bytes, DE -> 6 characters: write the digits. HL, DE advance.
bcd_str:
  ld b,3
.lp:
  ld a,(hl)
  rrca
  rrca
  rrca
  rrca
  and &0F
  add a,"0"
  ld (de),a
  inc de
  ld a,(hl)
  and &0F
  add a,"0"
  ld (de),a
  inc de
  inc hl
  djnz .lp
  ret

title_update:
  call menu_tick
  ld hl,title_tick
  inc (hl)
  ld a,(hl)
  and 15
  jr nz,.press
  if TEST_FRAMES == 0             ; (tests: keep it still for the screenshot)
  ld a,(title_hl)               ; the new entry blinks
  cp HS_COUNT
  call c,hs_row_xor
  endif
.press:
  ld a,(title_tick)
  and 31
  call z,title_press
  ld hl,state_timer
  ld a,(hl)
  or a
  jr z,.input
  dec (hl)
  ret
.input:
  ld a,(pad_new)
  ld c,a
  and 1<<PAD_LEFT or 1<<PAD_RIGHT
  jr z,.start
  call title_diff               ; off with the old one
  ld a,(pad_new)
  ld c,a
  ld hl,difficulty
  ld a,(hl)
  bit PAD_RIGHT,c
  jr z,.easier
  cp 2
  jr nc,.show
  inc (hl)
  jr .show
.easier:
  or a
  jr z,.show
  dec (hl)
.show:
  jp title_diff
.start:
  ld a,c
  and 1<<PAD_FIRE or 1<<PAD_JUMP
  ret z
  call screen_clear
  jp game_new

; The game is over: a name for the table, or straight back to the title.
hiscore_after_game:
  call hiscore_rank
  cp HS_COUNT
  ld a,&FF
  jp nc,title_start
  ; fall through
entry_start:
  call hiscore_rank
  ld (entry_rank),a
  call screen_clear
  call menu_world
  ld b,40
  ld de,txt_new_hi
  call text_mid
  ld hl,score                   ; "SCORE 001234"
  ld de,txt_your_score+6
  call bcd_str
  ld b,60
  ld de,txt_your_score
  call text_mid
  ld b,92
  ld de,txt_enter
  call text_mid
  ld b,150
  ld de,txt_entry_help1
  call text_mid
  ld b,162
  ld de,txt_entry_help2
  call text_mid
  ld hl,entry_name              ; "A    "
  ld (hl),"A"
  ld b,HS_NAME-1
.sp:
  inc hl
  ld (hl)," "
  djnz .sp
  xor a
  ld (entry_pos),a
  ld (aim_repeat),a
  ld hl,key_prev                ; keys held now don't count as typed
  ld b,10
.kp:
  ld (hl),a
  inc hl
  djnz .kp
  call entry_char_xor
  call entry_cursor_xor
  ld a,GS_ENTRY
  ld b,0
  call game_state_set
  call wait_frame
  ld hl,menu_palette
  jp palette_hl

; XOR the letter at entry_pos.
entry_char_xor:
  ld a,(entry_pos)
  ld e,a
  ld d,0
  ld hl,entry_name
  add hl,de
  ld a,(hl)
  ld (hud_char),a
  ld b,NAME_Y
  jr entry_xor_at

entry_cursor_xor:
  ld a,"-"
  ld (hud_char),a
  ld b,CURSOR_Y
entry_xor_at:
  xor a
  ld (hud_char+1),a
  ld a,(entry_pos)
  add a,a
  add a,a
  add a,NAME_COL
  ld de,hud_char
  jp text_at

; A = character: put it at the cursor.
entry_set:
  push af
  call entry_char_xor           ; the old one off
  ld hl,entry_name
  ld a,(entry_pos)
  ld e,a
  ld d,0
  add hl,de
  pop af
  ld (hl),a
  jr entry_char_xor             ; the new one on

entry_update:
  call menu_tick
  ld ix,entry_keys              ; typed keys first
.key:
  ld a,(ix+0)
  or a
  jr z,.pad
  call key_new
  jr nz,.typed
  inc ix
  inc ix
  jr .key
.typed:
  call key_remember
  ld a,(ix+1)
  cp KEY_DONE
  jp z,entry_done
  cp KEY_DEL
  jp z,entry_delete
  call entry_set
  ld a,(entry_pos)              ; on the last letter the cursor stays
  cp HS_NAME-1
  ret z
  jp entry_right
.pad:
  call key_remember
  ld a,(pad_new)
  and 1<<PAD_FIRE or 1<<PAD_JUMP
  jr z,.nofire
  ld a,(entry_pos)
  cp HS_NAME-1
  jp z,entry_done
  jp entry_right
.nofire:
  ld a,(pad_new)
  bit PAD_RIGHT,a
  jp nz,entry_right
  bit PAD_LEFT,a
  jp nz,entry_left
  ld a,(pad)                    ; UP/DOWN: next/previous letter
  and 1<<PAD_UP or 1<<PAD_DOWN
  ret z
  ld b,a
  ld a,(pad_new)
  and b
  ld a,AIM_DELAY
  jr nz,.turn
  ld hl,aim_repeat
  dec (hl)
  ret nz
  ld a,AIM_RATE
.turn:
  ld (aim_repeat),a
  push bc
  ld a,(entry_pos)              ; where is the letter in the cycle?
  ld e,a
  ld d,0
  ld hl,entry_name
  add hl,de
  ld a,(hl)
  ld hl,entry_cycle
  ld c,0
.find:
  cp (hl)
  jr z,.found
  inc hl
  inc c
  ld e,a
  ld a,c
  cp CYCLE_LEN
  ld a,e
  jr nz,.find
  ld c,0
.found:
  pop af
  bit PAD_UP,a
  ld a,c
  jr z,.prev
  inc a
  cp CYCLE_LEN
  jr c,.set
  xor a
  jr .set
.prev:
  dec a
  jp p,.set
  ld a,CYCLE_LEN-1
.set:
  ld e,a
  ld d,0
  ld hl,entry_cycle
  add hl,de
  ld a,(hl)
  jp entry_set

entry_right:
  ld a,(entry_pos)
  cp HS_NAME-1
  ret z
  call entry_cursor_xor
  ld hl,entry_pos
  inc (hl)
  jp entry_cursor_xor

entry_left:
  ld a,(entry_pos)
  or a
  ret z
  call entry_cursor_xor
  ld hl,entry_pos
  dec (hl)
  jp entry_cursor_xor

; DEL: clear the letter under the cursor, or (on a blank) the one before.
entry_delete:
  ld a,(entry_pos)
  ld e,a
  ld d,0
  ld hl,entry_name
  add hl,de
  ld a,(hl)
  cp " "
  jr nz,.clear
  call entry_left
.clear:
  ld a," "
  jp entry_set

; Into the table, onto the disk, back to the title showing it.
entry_done:
  call entry_cursor_xor
  call hiscore_insert
  ld a,(disk_track)             ; no HISCORE.DAT found at boot: RAM only
  inc a
  jr z,.title
  ld b,SAVE_Y
  ld de,txt_saving
  call text_mid
  call hiscore_save
  jr c,.saved
  ld b,SAVE_Y                   ; write-protected, no disc...: say so
  ld de,txt_saving
  call text_mid
  ld b,SAVE_Y
  ld de,txt_not_saved
  call text_mid
  ld b,100
.show:
  push bc
  call wait_frame
  pop bc
  djnz .show
.saved:
  if TEST_HISCORE
  call hiscore_init             ; read it back: the title shows the disk's
  endif
.title:
  ld a,(entry_rank)
  jp title_start

; A = key code (line * 16 + bit): NZ if it went down since last frame.
key_new:
  ld c,a
  rrca
  rrca
  rrca
  rrca
  and &0F
  ld e,a
  ld d,0
  ld hl,key_prev
  add hl,de
  ld b,(hl)                     ; up before (1)...
  ld hl,keymap
  add hl,de
  ld a,(hl)
  cpl                           ; ... and down now (0)
  and b
  ld b,a
  ld a,c
  and 7
  ld e,a
  ld hl,bit_mask
  add hl,de
  ld a,(hl)
  and b
  ret

key_remember:
  ld hl,keymap
  ld de,key_prev
  ld bc,10
  ldir
  ret

bit_mask: db 1,2,4,8,16,32,64,128

KEY_DONE equ 1
KEY_DEL  equ 2
entry_keys:                     ; key code, character
  db &85,"A", &66,"B", &76,"C", &75,"D", &72,"E", &65,"F", &64,"G"
  db &54,"H", &43,"I", &55,"J", &45,"K", &44,"L", &46,"M", &56,"N"
  db &42,"O", &33,"P", &83,"Q", &62,"R", &74,"S", &63,"T", &52,"U"
  db &67,"V", &73,"W", &77,"X", &53,"Y", &87,"Z"
  db &40,"0", &80,"1", &81,"2", &71,"3", &70,"4", &61,"5", &60,"6"
  db &51,"7", &50,"8", &41,"9", &37,".", &31,"-", &57," "
  db &22,KEY_DONE, &06,KEY_DONE, &97,KEY_DEL
  db 0
entry_cycle: db "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-! "
CYCLE_LEN equ $-entry_cycle

txt_title:       db "L  I  N  N  E  R",0
txt_hiscores:    db "HIGH SCORES",0
txt_press:       db "PRESS FIRE TO PLAY",0
txt_diff:        db "DIFFICULTY  < MEDIUM >",0
txt_diffs:       db " EASY ","MEDIUM"," HARD "
txt_marks:       db "HME"
txt_help1:       db "LEFT RIGHT: GEAR    UP DOWN: AIM",0
txt_help2:       db "LINNER SHOOTS BY HIMSELF",0
txt_help3:       db "SPACE OR FIRE: JUMP",0
txt_new_hi:      db "A NEW HIGH SCORE!",0
txt_your_score:  db "SCORE 000000",0
txt_enter:       db "ENTER YOUR NAME",0
txt_entry_help1: db "UP DOWN: LETTER    FIRE: NEXT",0
txt_entry_help2: db "OR TYPE IT  -  RETURN: DONE",0
txt_saving:      db "SAVING...",0
txt_not_saved:   db "COULD NOT SAVE THE TABLE",0
