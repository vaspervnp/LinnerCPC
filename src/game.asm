; ===========================================================================
; The game loop: lives, the level timer, powerups, the finish line,
; level complete (time bonus), game over.
;
;   GS_READY     "LEVEL n  GET READY", the world frozen for a moment
;   GS_PLAY      the game proper (hero_update, objects_update, timer)
;   GS_COMPLETE  past the finish post: the time left becomes points
;   GS_OVER      "GAME OVER", then the name entry or the title
; Losing a life (hero_dying runs out) restarts the level, or ends the game.
; ===========================================================================

GS_READY    equ 0
GS_PLAY     equ 1
GS_COMPLETE equ 2
GS_OVER     equ 3
GS_TITLE    equ 4               ; (hiscore.asm) from here on the game
GS_ENTRY    equ 5               ; world isn't on screen

START_LIVES equ 3
  ifndef TEST_LEVEL
TEST_LEVEL equ 1                ; tests: start at another level
  endif
READY_TIME  equ 90
DONE_TIME   equ 100             ; after the bonus is counted
OVER_TIME   equ 200
PHASE_WARN  equ 50              ; the ghost flickers for its last second
                                ; (each Rhombus lasts 3..8 s: see the level)
MSG_ROW     equ 64              ; game y of the message line

game_new:
  ld a,(difficulty)             ; the world's speed for this game
  ld l,a
  ld h,0
  ld d,h
  ld e,l
  add hl,hl                     ; * DIFF_SIZE (37 = 32 + 4 + 1)
  add hl,hl
  ld b,h
  ld c,l
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,bc
  add hl,de
  ld de,diff_table
  add hl,de
  ld de,phys
  ld bc,DIFF_SIZE
  ldir
  xor a
  ld (score),a
  ld (score+1),a
  ld (score+2),a
  ld a,START_LIVES
  if TEST_HISCORE
  ld a,1                        ; tests: one life, a score for the table
  ld hl,&3412
  ld (score+1),hl
  endif
  ld (lives),a
  ld a,TEST_LEVEL
  ld (level_num),a
  ; fall through
; A new level: from its start.
level_begin:
  xor a
  ld (wp_last),a
  ld a,(level_num)              ; the music, in this level's key
  ld e,a
  ld d,0
  ld hl,level_keys-1
  add hl,de
  ld c,(hl)
  ld a,SONG_GAME
  call music_play
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
  call particles_wipe
  ld a,(drawn_valid)
  or a
  call nz,ground_wipe
  call level_load
  ld a,(wp_last)
  or a
  jr z,.start
  dec a                         ; restart at the last waypoint passed
  call wp_addr
  push hl
  ld e,(hl)                     ; segment, key, scroll x
  inc hl
  ld d,(hl)
  inc hl
  ld a,(hl)
  inc hl
  ld c,(hl)
  inc hl
  ld b,(hl)
  ex de,hl
  ld d,b
  ld e,c
  call terrain_start
  call hero_init
  call objects_clear
  pop hl
  ld de,5                       ; foe record, the x before it
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld c,(hl)
  inc hl
  ld b,(hl)
  ex de,hl
  ld d,b
  ld e,c
  call objects_start
  ld a,(wp_last)                ; its post is behind him now
  ld (wp_next),a
  ld hl,(wp_time)               ; the time he had there
  jr .timed
.start:
  ld (wp_next),a
  call terrain_init
  call hero_init
  call objects_init
  ld a,(difficulty)             ; the level's time for this difficulty
  add a,a
  ld e,a
  ld d,0
  ld hl,lv_times
  add hl,de
  ld a,(hl)
  inc hl
  ld h,(hl)
  ld l,a
.timed:
  ld (time_left),hl
  call particles_init
  ld a,50
  ld (time_tick),a
  call hud_draw
  call render
  ld hl,txt_ready               ; "LEVEL n: NAME"
  ld de,msg_buf
  ld bc,6
  ldir
  ld a,(level_num)
  add a,"0"
  ld (de),a
  inc de
  ld a,":"
  ld (de),a
  inc de
  ld a," "
  ld (de),a
  inc de
  ld hl,(lv_name)
  ld a,(wp_last)
  or a
  jr z,.name
  ld hl,txt_waypoint            ; "LEVEL n: WAYPOINT k"
  ld bc,9
  ldir
  add a,"0"
  ld (de),a
  inc de
  xor a
  ld (de),a
  jr .named
.name:
  ld a,(hl)
  ld (de),a
  inc hl
  inc de
  or a
  jr nz,.name
.named:
  ld de,msg_buf
  call msg_show
  ld a,GS_READY
  ld b,READY_TIME
  call game_state_set
  call wait_frame
  xor a
  ld (frame_drops),a            ; the set-up itself is allowed to take long
  ld (frame_late),a
  jp palette_set

; A = waypoint index -> HL = its record in lv_ways (WAY_SIZE = 11 bytes).
wp_addr:
  ld l,a
  ld h,0
  ld d,h
  ld e,l
  add hl,hl
  ld b,h
  ld c,l                        ; 2
  add hl,hl
  add hl,hl                     ; 8
  add hl,bc
  add hl,de                     ; 11
  ld de,(lv_ways)
  add hl,de
  ret

; Copy level_num's entry of level_table into lv_segs.. (same order).
level_load:
  ld a,(level_num)
  dec a
  ld l,a
  ld h,0
  add hl,hl                     ; * LEVEL_ENTRY (18)
  ld d,h
  ld e,l
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,de
  ld de,level_table
  add hl,de
  ld de,lv_segs
  ld bc,LEVEL_ENTRY
  ldir
  ret

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
  cp GS_TITLE
  jp z,title_update
  cp GS_ENTRY
  jp z,entry_update
  ld hl,state_timer             ; GS_OVER
  dec (hl)
  ret nz
  jp hiscore_after_game
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
  ld a,(wp_next)                ; past the next waypoint's post?
  ld hl,lv_nways
  cp (hl)
  jr nc,.no_way
  call wp_addr
  ld de,9
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld hl,(scroll_wx)
  ld bc,HERO_X
  add hl,bc
  or a
  sbc hl,de
  jr c,.no_way
  ld hl,wp_next                 ; restarts begin here now, with this time
  inc (hl)
  ld a,(hl)
  ld (wp_last),a
  ld hl,(time_left)
  ld (wp_time),hl
  ld a,SFX_WAY
  call sfx_play
.no_way:
  ld hl,(scroll_wx)             ; past the finish post?
  ld de,HERO_X
  add hl,de
  ld de,(lv_goal)
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
  ld a,SONG_DONE
  ld c,0
  call music_play
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
  ld a,(p_bonus)                ; 10 points a second on hard (fewer when
  jp score_add                  ; the clock is longer)
.counted:
  ld hl,state_timer
  dec (hl)
  ret nz
  ld hl,level_num
  ld a,(hl)
  cp LEVEL_COUNT
  jr nc,game_won
  inc (hl)
  jp level_begin

; Past the last finish post: the game is won (then the table, as after a
; game over).
game_won:
  ld de,txt_won
  call msg_show
  ld a,GS_OVER
  ld b,OVER_TIME
  call game_state_set
  ld a,1
  ld (hero_state),a
  ret

; hero_dying ran out: one life less.
game_life_lost:
  ld hl,lives
  dec (hl)
  jp nz,level_setup
  ld de,txt_game_over
  call msg_show
  ld a,SONG_OVER
  ld c,0
  call music_play
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
; A = seconds -> HL = frames (x p_fps: 50 on hard, more when the world
; runs slower). Trashes A, B, DE.
secs_frames:
  ld e,a
  ld d,0
  ld h,d
  ld l,d
  ld a,(p_fps)
  ld b,8
.mul:
  add hl,hl
  rla
  jr nc,.skip
  add hl,de
.skip:
  djnz .mul
  ret

; A = seconds of Max Speed / Phase Out (from the Rhombus).
powerup_fast:
  call secs_frames
  ld (hero_fast),hl
  ld a,GEARS
  ld (max_gear),a
  ld (gear),a                   ; straight into gear 5
  ld a,(p_gear_time)
  ld (gear_timer),a
  ld a,&50
  jp score_add

powerup_phase:
  call secs_frames
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
  ld a,h                        ; the last second: flicker as a warning
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
  ld de,(msg_cur)
  ld b,MSG_ROW
  jp text_mid

msg_hide:
  ld hl,(msg_cur)
  ld a,h
  or l
  ret z
  call msg_xor
  ld hl,0
  ld (msg_cur),hl
  ret

; the in-game song's key in each level (semitones)
level_keys:   db 0,2,3,-2,5,7

txt_waypoint: db "WAYPOINT "
txt_ready:    db "LEVEL "
txt_won:      db "THE LINE IS YOURS!",0
txt_complete: db "LEVEL COMPLETE!",0
txt_time_up:  db "TIME UP!",0
txt_game_over: db "GAME OVER",0
