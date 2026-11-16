; ===========================================================================
; The game loop: lives, the level timer, powerups, the finish line,
; level complete (time bonus), game over.
;
;   GS_READY     "LEVEL n  GET READY", the world frozen for a moment
;   GS_PLAY      the game proper (hero_update, objects_update, timer)
;   GS_COMPLETE  past the finish post: the time left becomes points
;   GS_OVER      "GAME OVER", then a new game
; Losing a life (hero_dying runs out) restarts the level, or ends the game.
; ===========================================================================

GS_READY    equ 0
GS_PLAY     equ 1
GS_COMPLETE equ 2
GS_OVER     equ 3

START_LIVES equ 3
READY_TIME  equ 90
DONE_TIME   equ 100             ; after the bonus is counted
OVER_TIME   equ 200
FAST_TIME   equ 1000            ; Max Speed: 20 s of gear 5
PHASE_TIME  equ 500             ; Phase Out: 10 s as a ghost
PHASE_WARN  equ 100             ; the ghost flickers for the last 2 s
MSG_ROW     equ 64              ; game y of the message line

game_new:
  xor a
  ld (score),a
  ld (score+1),a
  ld (score+2),a
  ld a,START_LIVES
  ld (lives),a
  ld a,1
  ld (level_num),a
  ; fall through

; (Re)start the current level: wipe what is on screen, set everything up,
; draw it with the palette black, then "GET READY".
level_setup:
  call palette_black
  call msg_hide
  ld a,1
  ld (hero_hidden),a
  call linner_erase
  call linner_draw
  call objects_wipe
  ld a,(drawn_valid)
  or a
  call nz,ground_wipe
  call terrain_init
  call hero_init
  call objects_init
  ld hl,level1_time
  ld (time_left),hl
  ld a,50
  ld (time_tick),a
  call hud_draw
  call render
  ld a,(level_num)              ; "LEVEL n  GET READY"
  add a,"0"
  ld (txt_level_n),a
  ld de,txt_ready
  call msg_show
  ld a,GS_READY
  ld b,READY_TIME
  call game_state_set
  call wait_frame
  xor a
  ld (frame_drops),a            ; the set-up itself is allowed to take long
  jp palette_set

; A = state, B = frames in it (for the timed ones).
game_state_set:
  ld (game_state),a
  ld a,b
  ld (state_timer),a
  ret

; One frame of the game (after rendering).
game_update:
  ld a,(game_state)
  cp GS_PLAY
  jr z,game_play
  cp GS_READY
  jr z,.ready
  cp GS_COMPLETE
  jp z,game_complete
  ld hl,state_timer             ; GS_OVER
  dec (hl)
  ret nz
  jp game_new
.ready:
  ld hl,state_timer
  dec (hl)
  ret nz
  call msg_hide
  ld a,GS_PLAY
  ld (game_state),a
  ret

game_play:
  call hero_update
  call objects_update
  call powerups_tick
  ld a,(hero_state)             ; the clock stops once Linner is lost
  or a
  ret nz
  ld hl,(scroll_wx)             ; past the finish post?
  ld de,HERO_X
  add hl,de
  ld de,level1_goal
  or a
  sbc hl,de
  jr nc,.finish
  ld hl,time_tick               ; the countdown
  dec (hl)
  ret nz
  ld (hl),50
  ld hl,(time_left)
  ld a,l
  sub 1
  daa
  ld l,a
  ld a,h
  sbc a,0
  daa
  ld h,a
  ld (time_left),hl
  or l
  ret nz
  ld de,txt_time_up             ; out of time: Linner is lost
  call msg_show
  ld a,HERO_GONE
  ld b,LOST_TIME*2
  call hero_die
  ld a,1
  ld (hero_hidden),a
  ret
.finish:
  ld de,txt_complete
  call msg_show
  ld a,GS_COMPLETE
  ld b,DONE_TIME
  jp game_state_set

; Level complete: Linner rolls to a stop while every second left on the
; clock turns into 10 points; then the next level.
game_complete:
  call hero_coast
  call objects_update           ; shots fly on (nothing can touch Linner now)
  ld hl,(time_left)
  ld a,h
  or l
  jr z,.counted
  ld a,l                        ; time - 1 (BCD)
  sub 1
  daa
  ld l,a
  ld a,h
  sbc a,0
  daa
  ld h,a
  ld (time_left),hl
  ld a,&10
  jp score_add
.counted:
  ld hl,state_timer
  dec (hl)
  ret nz
  ld hl,level_num
  inc (hl)
  ld a,(hl)
  cp 10
  jr c,.next
  ld (hl),1
.next:
  jp level_setup

; hero_dying ran out: one life less.
game_life_lost:
  ld hl,lives
  dec (hl)
  jp nz,level_setup
  ld de,txt_game_over
  call msg_show
  ld a,GS_OVER
  ld b,OVER_TIME
  call game_state_set
  ld a,1                        ; nothing more happens behind the message
  ld (hero_state),a
  ret

; A = points in BCD (tens and ones of the score's last byte pair):
; score += A.
score_add:
  ld hl,score+2
  add a,(hl)
  daa
  ld (hl),a
  dec hl
  ld a,(hl)
  adc a,0
  daa
  ld (hl),a
  dec hl
  ld a,(hl)
  adc a,0
  daa
  ld (hl),a
  ret

; ---------------------------------------------------------------------------
; Powerups
; ---------------------------------------------------------------------------
powerup_fast:
  ld hl,FAST_TIME
  ld (hero_fast),hl
  ld a,GEARS
  ld (max_gear),a
  ld a,&50
  jp score_add

powerup_phase:
  ld hl,PHASE_TIME
  ld (hero_phase),hl
  ld a,&50
  jp score_add

; Count the powerups down; pick Linner's look (solid or ghost).
powerups_tick:
  ld hl,(hero_fast)
  ld a,h
  or l
  jr z,.phase
  dec hl
  ld (hero_fast),hl
  ld a,h
  or l
  jr nz,.phase
  ld a,MAX_GEAR_NORMAL          ; Max Speed over: back under the limit
  ld (max_gear),a
  ld hl,gear
  cp (hl)
  jr nc,.phase
  ld (hl),a
.phase:
  if TEST_GHOST
  ld hl,PHASE_WARN+50
  ld (hero_phase),hl
  endif
  ld de,circle_tab
  ld hl,(hero_phase)
  ld a,h
  or l
  jr z,.look
  dec hl
  ld (hero_phase),hl
  ld de,ghost_tab
  ld a,h                        ; the last 2 s: flicker as a warning
  or a
  jr nz,.look
  ld a,l
  cp PHASE_WARN
  jr nc,.look
  and 8
  jr z,.look
  ld de,circle_tab
.look:
  ld (hero_ctab),de
  ret

; Z if Linner is a ghost right now.
hero_phased:
  ld hl,(hero_phase)
  ld a,h
  or l
  jr z,.no
  xor a
  ret
.no:
  inc a                         ; NZ
  ret

; ---------------------------------------------------------------------------
; Messages over the play area (XOR, so the same call removes them)
; ---------------------------------------------------------------------------
; DE = string: show it centred on the message line (replacing any other).
msg_show:
  push de
  call msg_hide
  pop de
  ld (msg_cur),de
  ; fall through
msg_xor:
  ld hl,(msg_cur)               ; length -> left byte column 48 - len
  ld b,0
.len:
  ld a,(hl)
  or a
  jr z,.got
  inc hl
  inc b
  jr .len
.got:
  ld a,BYTES_PER_LINE/2
  sub b
  ld e,MSG_ROW
  ld d,row_lo>>8
  ld l,a
  ld a,(de)
  add a,l
  ld l,a
  inc d
  ld a,(de)
  adc a,0
  ld h,a
  ld de,(msg_cur)
  jp print_xor

msg_hide:
  ld hl,(msg_cur)
  ld a,h
  or l
  ret z
  call msg_xor
  ld hl,0
  ld (msg_cur),hl
  ret

txt_ready:    db "LEVEL "
txt_level_n:  db "1  GET READY",0
txt_complete: db "LEVEL COMPLETE!",0
txt_time_up:  db "TIME UP!",0
txt_game_over: db "GAME OVER",0
