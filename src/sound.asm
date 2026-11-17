; ===========================================================================
; Sound and music on the AY-3-8912 (through the PPI), played from the
; interrupt: sound_tick runs in the 6th interrupt of each frame, ~3 ms
; before VSYNC, when the main loop is usually in its logic or idle (the
; first one, at VSYNC, is the drawing's: Linner and the objects race the
; beam). ~0.4-0.6 ms a frame.
;
; Music: channels A, B, C (C has the drums); sound effects take over C
; while they play. The game only posts requests (music_play, sfx_play:
; single bytes, so the interrupt never sees half of one). Data:
; build/music.asm (tools/gen_music.py).
;
; The keyboard is read through the AY too: kbd_scan runs with interrupts
; off, and the mixer keeps port A an input (register 7 bit 6 = 0).
; ===========================================================================

AY_NREGS    equ 11              ; tone A/B/C, noise, mixer, volume A/B/C
SND         equ &7700           ; the sound's state (between the object
                                ; slots, &7600-&76C5, and RUNS, &7800)
CH_HELD     equ 0               ; 1: on a held envelope frame, all set
CH_ENV      equ 1               ; dw envelope frame
CH_VOL      equ 3               ; volume out
CH_TM       equ 4               ; its tone bit in the mixer (1, 2, 4)
CH_NM       equ 5               ; its noise bit (8, 16, 32)
CH_MIX      equ 6               ; mixer bits it wants (tone / noise enable)
CH_NP       equ 7               ; noise period out
CH_NOTE     equ 8               ; note (transposed)
CH_PNOTE    equ 9               ; the note CH_PER is for (&FF: none yet)
CH_PER      equ 10              ; dw tone period out
CH_ORD      equ 12              ; dw next order list entry
CH_PAT      equ 14              ; dw next pattern byte
CH_INS      equ 16              ; dw instrument (its first frame)
CH_ROWS     equ 18              ; rows left of this note
CH_DUR      equ 19              ; note length in rows
CH_TR       equ 20              ; transpose
CH_ON       equ 21              ; 0: the channel's order list has ended
CH_SIZE     equ 22

snd_ch      equ SND             ; channels A, B, C
snd_speed   equ SND+3*CH_SIZE   ; frames per row
snd_tick    equ snd_speed+1     ; frames to the next row
snd_song    equ snd_tick+1      ; the song playing (SONG_x, 0 none)
snd_req     equ snd_song+1      ; request: SONG_x, &FF = stop, 0 none
snd_req_tr  equ snd_req+1       ; its key (transpose)
snd_base_tr equ snd_req_tr+1    ; the playing song's key
sfx_req     equ snd_base_tr+1       ; request: SFX_x (the highest this frame)
sfx_cur     equ sfx_req+1       ; the effect playing (its priority), 0 none
sfx_left    equ sfx_cur+1       ; frames left of this part
sfx_ptr     equ sfx_left+1      ; dw its record
sfx_per     equ sfx_ptr+2       ; dw tone period
sfx_vol     equ sfx_per+2       ; volume, 4.4
sfx_np      equ sfx_vol+1       ; noise period
ay_last     equ sfx_np+1        ; registers 0..10 as last written
int_n       equ ay_last+11      ; interrupts since VSYNC (0..5)
snd_dirty   equ int_n+1         ; a tone or noise period may have changed
  assert (ay_last and &FF)+AY_NREGS < 256  ; (the write loop counts in E)
SND_END     equ snd_dirty+1
  assert SND_END <= &7800


; Start-up (interrupts off): silence, channels idle.
sound_init:
  ld hl,SND
  ld de,SND+1
  ld bc,SND_END-SND-1
  ld (hl),0
  ldir
  ld hl,ay_last                 ; (nothing written yet: write it all)
  ld b,AY_NREGS
.last:
  ld (hl),&FF
  inc hl
  djnz .last
  ld ix,snd_ch
  ld bc,&0108                   ; tone bit, noise bit
.ch:
  ld (ix+CH_TM),b
  ld (ix+CH_NM),c
  ld (ix+CH_PNOTE),&FF
  ld hl,env_silent
  ld (ix+CH_ENV),l
  ld (ix+CH_ENV+1),h
  ld de,CH_SIZE
  add ix,de
  sla c
  sla b
  bit 3,b
  jr z,.ch
  ret

; ---------------------------------------------------------------------------
; Requests from the game (keep every register but AF)
; ---------------------------------------------------------------------------
; A = SONG_x, C = its key (semitones): start it (or keep it going if it
; is already playing in that key).
music_play:
  push hl
  ld hl,snd_req_tr
  ld (hl),c
  ld (snd_req),a
  pop hl
  ret

music_stop:
  ld a,&FF
  ld (snd_req),a
  ret

; A = SFX_x: play it unless something more important is (the interrupt
; decides; of several in one frame the most important one wins).
sfx_play:
  push hl
  ld hl,sfx_req
  cp (hl)
  jr c,.keep
  ld (hl),a
.keep:
  pop hl
  ret

; Silence now, with interrupts off (the disk: the interrupt can't run, and
; a held note would drone). The next sound_tick writes it all back.
sound_mute:
  ld e,8
.vol:
  xor a
  call ay_out
  ld hl,ay_last
  ld d,0
  add hl,de
  ld (hl),a
  inc e
  ld a,e
  cp AY_NREGS
  jr nz,.vol
  ret

; E = register, A = value. Trashes BC.
ay_out:
  ld b,PPI_A
  out (c),e                     ; the register number
  ld bc,PPI_C*256+&C0           ; latch it
  out (c),c
  ld c,0
  out (c),c
  ld b,PPI_A
  out (c),a                     ; the value
  ld bc,PPI_C*256+&80           ; write it
  out (c),c
  ld c,0
  out (c),c
  ret

; ---------------------------------------------------------------------------
; The interrupt's part (AF, BC, DE, HL saved by int_handler)
; ---------------------------------------------------------------------------
sound_tick:
  push ix
  ld a,(snd_req)
  or a
  call nz,snd_start
  ld a,(snd_song)               ; a new row?
  or a
  jr z,.envs
  ld hl,snd_tick
  dec (hl)
  jr nz,.envs
  ld a,(snd_speed)
  ld (hl),a
  ld ix,snd_ch
  ld b,3
.rows:
  push bc
  ld a,(ix+CH_ON)
  or a
  call nz,snd_row
  ld de,CH_SIZE
  add ix,de
  pop bc
  djnz .rows
.envs:
  ld hl,snd_ch                  ; every frame: the envelopes
  call snd_env
  ld hl,snd_ch+CH_SIZE
  call snd_env
  ld hl,snd_ch+2*CH_SIZE
  call snd_env
  call sfx_tick                 ; an effect takes over channel C
  ld hl,snd_dirty               ; a period changed (or an effect plays)?
  ld a,(hl)
  ld (hl),0
  or a
  jr z,.vols
  ld hl,ay_last                 ; write the registers that changed
  ld a,(snd_ch+CH_PER)
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+CH_PER+1)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+CH_SIZE+CH_PER)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+CH_SIZE+CH_PER+1)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+2*CH_SIZE+CH_PER)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+2*CH_SIZE+CH_PER+1)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+2*CH_SIZE+CH_NP)
  inc l
  cp (hl)
  call nz,ay_put
.vols:
  ld a,(snd_ch+CH_MIX)          ; the mixer
  ld hl,snd_ch+CH_SIZE+CH_MIX
  or (hl)
  ld hl,snd_ch+2*CH_SIZE+CH_MIX
  or (hl)
  cpl                           ; (the AY's bits are "off" bits)
  and &3F                       ; port A stays an input: the keyboard
  ld hl,ay_last+7
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+CH_VOL)
  ld hl,ay_last+8
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+CH_SIZE+CH_VOL)
  inc l
  cp (hl)
  call nz,ay_put
  ld a,(snd_ch+2*CH_SIZE+CH_VOL)
  inc l
  cp (hl)
  call nz,ay_put
  pop ix
  ret

; HL = ay_last + register, A = its new value: remember it, write it.
ay_put:
  ld (hl),a
  push af
  ld a,l
  sub ay_last and &FF
  ld e,a
  pop af
  jp ay_out

; A = request (SONG_x or &FF): start the song, or stop.
snd_start:
  ld hl,snd_req
  ld (hl),0
  cp &FF
  jp z,.stop
  ld c,a
  ld hl,snd_song                ; already playing in this key: leave it
  cp (hl)
  jr nz,.new
  ld a,(snd_req_tr)
  ld hl,snd_base_tr
  cp (hl)
  jr nz,.new
  ld a,(snd_ch+CH_ON)
  ld hl,snd_ch+CH_SIZE+CH_ON
  or (hl)
  ld hl,snd_ch+2*CH_SIZE+CH_ON
  or (hl)
  ret nz
.new:
  ld a,c
  ld (snd_song),a
  ld a,(snd_req_tr)
  ld (snd_base_tr),a
  ld a,c                        ; its record: speed, 3 order lists
  dec a
  ld l,a
  add a,a
  add a,a
  add a,a
  sub l                         ; * 7
  ld l,a
  ld h,0
  ld de,song_tab
  add hl,de
  ld a,(hl)
  ld (snd_speed),a
  inc hl
  ld a,1
  ld (snd_tick),a
  ld ix,snd_ch
  ld b,3
.ch:
  ld a,(hl)
  ld (ix+CH_ORD),a
  inc hl
  ld a,(hl)
  ld (ix+CH_ORD+1),a
  inc hl
  ld a,1
  ld (ix+CH_ON),a
  ld (ix+CH_ROWS),a
  ld (ix+CH_DUR),a
  ld a,(snd_base_tr)
  ld (ix+CH_TR),a
  ld de,(ins_tab)
  ld (ix+CH_INS),e
  ld (ix+CH_INS+1),d
  ld de,env_silent
  ld (ix+CH_ENV),e
  ld (ix+CH_ENV+1),d
  ld (ix+CH_HELD),0
  ld de,snd_end_pat             ; (the first row reads the order list)
  ld (ix+CH_PAT),e
  ld (ix+CH_PAT+1),d
  ld de,CH_SIZE
  add ix,de
  djnz .ch
  ret
.stop:
  xor a
  ld (snd_song),a
  ld ix,snd_ch
  ld b,3
  ld de,env_silent
.off:
  ld (ix+CH_ON),a
  ld (ix+CH_ENV),e
  ld (ix+CH_ENV+1),d
  ld (ix+CH_HELD),a
  push de
  ld de,CH_SIZE
  add ix,de
  pop de
  djnz .off
  ret

snd_end_pat:
  db &FF

; IX = channel: the next row. A note (or rest) ends when its rows run out;
; then the pattern goes on, and at its end the order list.
snd_row:
  dec (ix+CH_ROWS)
  ret nz
  ld l,(ix+CH_PAT)
  ld h,(ix+CH_PAT+1)
.ev:
  ld a,(hl)
  inc hl
  cp &60
  jr c,.note
  cp &80
  jr c,.dur
  cp &90
  jr c,.ins
  jr z,.rest
  cp &91
  jr z,.tie
  call snd_order                ; the pattern's end: the next one
  jr nc,.ev
  ld (ix+CH_ON),0               ; the order list's end: silence
  ld de,env_silent
  jr .env
.dur:
  and &1F
  inc a
  ld (ix+CH_DUR),a
  jr .ev
.ins:
  and &0F
  add a,a
  ld e,a
  ld d,0
  push hl
  ld hl,ins_tab
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  pop hl
  ld (ix+CH_INS),e
  ld (ix+CH_INS+1),d
  jr .ev
.note:
  add a,(ix+CH_TR)
  ld (ix+CH_NOTE),a
  ld e,(ix+CH_INS)
  ld d,(ix+CH_INS+1)
  jr .env
.rest:
  ld de,env_silent
.env:
  ld (ix+CH_ENV),e
  ld (ix+CH_ENV+1),d
  ld (ix+CH_HELD),0
.tie:
  ld (ix+CH_PAT),l
  ld (ix+CH_PAT+1),h
  ld a,(ix+CH_DUR)
  ld (ix+CH_ROWS),a
  ret

; IX = channel: the next pattern from its order list -> HL, NC; C at the
; list's end.
snd_order:
  ld e,(ix+CH_ORD)
  ld d,(ix+CH_ORD+1)
.o:
  ld a,(de)
  inc de
  cp &80
  jr c,.pat
  cp &FE
  jr z,.end
  jr nc,.loop
  sub &A0                       ; transpose from the song's key
  ld hl,snd_base_tr
  add a,(hl)
  ld (ix+CH_TR),a
  jr .o
.loop:
  ex de,hl
  ld e,(hl)
  inc hl
  ld d,(hl)
  jr .o
.end:
  scf
  ret
.pat:
  ld (ix+CH_ORD),e
  ld (ix+CH_ORD+1),d
  add a,a
  ld e,a
  ld d,0
  ld hl,pat_tab
  add hl,de
  ld a,(hl)
  inc hl
  ld h,(hl)
  ld l,a
  or a
  ret

; HL = channel: one frame of its envelope -> volume, mixer bits, period
; (walks the channel's first fields in order: no IX, it runs 150 times a
; second).
snd_env:
  ld a,(hl)                     ; CH_HELD: as last frame
  or a
  ret nz
  inc hl                        ; CH_ENV
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld a,(de)
  ld c,a                        ; hold, noise, tone off, volume
  inc de
  ld a,(de)
  ld b,a                        ; pitch offset, or the noise period
  bit 7,c
  jr z,.adv
  dec hl                        ; the last frame: it holds
  dec hl
  ld (hl),1
  inc hl
  inc hl
  jr .frame
.adv:
  inc de
  ld (hl),d
  dec hl
  ld (hl),e
  inc hl
.frame:
  inc hl                        ; CH_VOL
  ld a,c
  and 15
  ld (hl),a
  inc hl                        ; CH_TM
  xor a
  bit 4,c
  jr nz,.notone
  ld a,(hl)
.notone:
  inc hl                        ; CH_NM
  bit 5,c
  jr z,.nonoise
  or (hl)
  inc hl                        ; CH_MIX
  ld (hl),a
  inc hl                        ; CH_NP
  ld (hl),b
  ld a,1
  ld (snd_dirty),a
  ld b,0                        ; (no pitch offset with noise)
  jr .note
.nonoise:
  inc hl                        ; CH_MIX
  ld (hl),a
  inc hl
.note:
  inc hl                        ; CH_NOTE
  ld a,(hl)
  add a,b
  bit 7,b
  jr z,.up
  jr c,.ok                      ; (down: no carry = below the lowest note)
  xor a
  jr .ok
.up:
  cp 96
  jr c,.ok
  ld a,95
.ok:
  inc hl                        ; CH_PNOTE: the same note, the same period
  cp (hl)
  ret z
  ld (hl),a
  inc hl                        ; CH_PER
  add a,a
  ld e,a
  ld d,0
  push hl
  ld hl,note_per
  add hl,de
  ld e,(hl)
  inc hl
  ld d,(hl)
  pop hl
  ld (hl),e
  inc hl
  ld (hl),d
  ld a,1
  ld (snd_dirty),a
  ret

; Sound effects: a new request (if it may), then this frame of the one
; playing over channel C.
sfx_tick:
  ld a,(sfx_req)
  or a
  jr z,.run
  ld hl,sfx_req
  ld (hl),0
  ld hl,sfx_cur
  cp (hl)
  jr c,.run                     ; something more important is playing
  cp SFX_SHOT                   ; shots don't cut into a drum hit
  jr nz,.take
  ld c,a
  ld a,(snd_ch+2*CH_SIZE+CH_VOL)
  cp 9
  ld a,c
  jr nc,.run
.take:
  ld (sfx_cur),a
  call sfx_load
.run:
  ld a,(sfx_cur)
  or a
  ret z
  ld ix,snd_ch+2*CH_SIZE        ; out on channel C, in place of its music
  ld hl,(sfx_per)
  ld (ix+CH_PER),l
  ld (ix+CH_PER+1),h
  ld (ix+CH_PNOTE),&FF          ; (the music recomputes its period after)
  ld (ix+CH_HELD),0
  ld a,1
  ld (snd_dirty),a
  ld a,(sfx_vol)
  rrca
  rrca
  rrca
  rrca
  and 15
  ld (ix+CH_VOL),a
  ld a,(sfx_np)
  ld (ix+CH_NP),a
  ld c,0
  ld hl,(sfx_ptr)
  inc hl
  ld a,(hl)                     ; bit 0 tone, bit 1 noise
  rra
  jr nc,.t
  set 2,c
.t:
  rra
  jr nc,.n
  set 5,c
.n:
  ld a,c
  ld (ix+CH_MIX),a
  inc hl                        ; the next frame: period + dperiod
  inc hl
  inc hl
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  inc hl                        ; -> dvolume
  push hl
  ld hl,(sfx_per)
  add hl,de
  ld (sfx_per),hl
  pop hl
  ld b,(hl)
  ld a,(sfx_vol)
  add a,b
  bit 7,b
  jr z,.louder
  jr c,.vol                     ; (quieter: no carry = below 0)
  xor a
  jr .vol
.louder:
  jr nc,.vol
  ld a,&F0
.vol:
  ld (sfx_vol),a
  inc hl
  inc hl                        ; -> dnoise
  ld a,(sfx_np)
  add a,(hl)
  and &1F
  ld (sfx_np),a
  inc hl                        ; -> next part
  ld a,(sfx_left)
  dec a
  ld (sfx_left),a
  ret nz
  ld a,(hl)
  or a
  jr nz,sfx_load                ; chained: the next part (same priority)
  ld (sfx_cur),a                ; over
  ret

; A = SFX_x: load its record.
sfx_load:
  dec a
  ld l,a
  ld h,0
  ld d,h
  ld e,l
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,de
  add hl,de
  add hl,de                     ; * 11
  ld de,sfx_tab
  add hl,de
  ld (sfx_ptr),hl
  ld a,(hl)
  ld (sfx_left),a
  inc hl
  inc hl
  ld e,(hl)
  inc hl
  ld d,(hl)
  ld (sfx_per),de
  inc hl
  inc hl
  inc hl
  ld a,(hl)
  ld (sfx_vol),a
  inc hl
  inc hl
  ld a,(hl)
  ld (sfx_np),a
  ret
