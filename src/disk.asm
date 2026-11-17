; ===========================================================================
; Disk: the high score table lives in HISCORE.DAT on the game disk (put
; there by iDSK, no AMSDOS header). The firmware is gone once the game
; runs, so we talk to the uPD765 directly (non-DMA, polled):
;   boot  find HISCORE.DAT in the directory (track 0, sector &C1) and
;         read its first sector;
;   save  write that sector back.
; Every wait has a time-out: with no drive, no disc or a stuck FDC we just
; give up (disk_track = &FF) and the table lives on in RAM only.
;
; Data format discs: 9 sectors &C1..&C9 per track, no reserved tracks,
; 1K blocks (2 sectors), block 0 starts at track 0 sector &C1.
; ===========================================================================

FDC_MSR     equ &FB7E           ; main status: 7 RQM, 6 DIO, 5 EXM, 4 CB
FDC_MOTOR   equ &FA7E
SECTOR_BUF  equ &C4E0           ; 512 bytes of screen RAM nobody sees
                                ; (charlines 21..33 end at &C4DF in each
                                ; 2K row block of the &C000 page)
SPIN_FRAMES equ 50              ; motor spin-up (AMSDOS waits 1 s too)

; Motor on and give it a second (interrupts stay on for wait_frame).
disk_motor_on:
  ld bc,FDC_MOTOR
  ld a,1
  out (c),a
  ld b,SPIN_FRAMES
.spin:
  push bc
  call wait_frame
  pop bc
  djnz .spin
  ret

disk_motor_off:
  ld bc,FDC_MOTOR
  xor a
  out (c),a
  ret

; Boot: find HISCORE.DAT and read it into SECTOR_BUF.
; Returns C if the sector was read (disk_track/disk_sector then point at it).
disk_load:
  ld a,&FF
  ld (disk_track),a
  call fdc_present
  ret nc
  call disk_motor_on
  di
  call sound_mute              ; (no interrupt, no sound: no drone)
  call fdc_start                ; specify, recalibrate (track 0)
  jr nc,.done
  xor a                         ; the directory's first sector
  ld e,&C1
  call fdc_chr
  call fdc_read
  jr nc,.done
  call dir_find                 ; -> disk_track / disk_sector
  jr nc,.done
  call fdc_seek_file
  jr nc,.done
  call fdc_read
.done:
  push af
  call disk_motor_off
  ei
  pop af
  ret

; Write SECTOR_BUF back to HISCORE.DAT. Returns C on success.
disk_save:
  ld a,(disk_track)
  inc a
  ret z                         ; never found the file (CF = 0)
  call disk_motor_on
  di
  call sound_mute              ; (no interrupt, no sound: no drone)
  call fdc_start
  jr nc,.done
  call fdc_seek_file
  jr nc,.done
  call fdc_write
.done:
  push af
  call disk_motor_off
  ei
  pop af
  ret

; Look for "HISCORE DAT" (user 0, extent 0) among the 16 entries of the
; directory sector in SECTOR_BUF. C if found.
dir_find:
  ld ix,SECTOR_BUF
  ld b,16
.entry:
  push bc
  ld a,(ix+0)                   ; user 0 (&E5 = free)
  or a
  jr nz,.next
  ld a,(ix+12)                  ; extent 0
  or a
  jr nz,.next
  push ix
  pop hl
  inc hl
  ld de,hs_filename
  ld b,11
.cmp:
  ld a,(hl)
  and &7F                       ; attribute bits
  ex de,hl
  cp (hl)
  ex de,hl
  jr nz,.next
  inc hl
  inc de
  djnz .cmp
  pop bc
  ld a,(ix+16)                  ; first block -> logical sector 2*block
  add a,a
  ld c,0                        ; track = sector / 9
.div:
  cp 9
  jr c,.got
  sub 9
  inc c
  jr .div
.got:
  add a,&C1
  ld (disk_sector),a
  ld a,c
  ld (disk_track),a
  scf
  ret
.next:
  ld de,32
  add ix,de
  pop bc
  djnz .entry
  or a
  ret
hs_filename: db "HISCORE DAT"

; ---------------------------------------------------------------------------
; uPD765 primitives. Interrupts must be off. All return C on success.
; ---------------------------------------------------------------------------

; Is there an FDC? An idle one shows RQM alone; drain any results left
; over first (machines without one read &FF).
fdc_present:
  ld d,16
.lp:
  ld bc,FDC_MSR
  in a,(c)
  cp &80
  scf
  ret z
  and &C0
  cp &C0                        ; a result byte waiting: read it
  jr nz,.no
  inc c
  in a,(c)
  call fdc_delay
  dec d
  jr nz,.lp
.no:
  or a
  ret

; Specify (6 ms steps, non-DMA, as AMSDOS) and recalibrate to track 0
; (twice if needed: one recalibrate steps at most 77 times).
fdc_start:
  ld hl,cmd_specify
  ld b,3
  call fdc_send
  ret nc
  call fdc_recal
  ret c
  ; fall through: try once more
fdc_recal:
  ld hl,cmd_recal
  ld b,2
  call fdc_send
  ret nc
  jr fdc_seek_end
cmd_specify: db &03, &A1, &03
cmd_recal:   db &07, &00

; Seek to HISCORE.DAT's track and set up the read/write command for it.
fdc_seek_file:
  ld a,(disk_sector)
  ld e,a
  ld a,(disk_track)
  ld (cmd_seek+2),a
  call fdc_chr
  ld hl,cmd_seek
  ld b,3
  call fdc_send
  ret nc
  ; fall through
; Poll Sense Interrupt Status until the seek (or recalibrate) has ended.
fdc_seek_end:
  ld hl,0                       ; time-out
.lp:
  push hl
  ld a,&08
  call fdc_put
  call c,fdc_result
  pop hl
  ret nc
  ld a,(fdc_res)
  cp &80                        ; invalid command: nothing to report yet
  jr z,.again
  bit 5,a                       ; seek end
  jr z,.again
  and &D0                       ; abnormal end or equipment check?
  scf
  ret z
  or a
  ret
.again:
  dec hl
  ld a,h
  or l
  jr nz,.lp
  ret                           ; CF = 0
cmd_seek: db &0F, &00, 0

; A = track, E = sector: aim the read/write command at that sector.
fdc_chr:
  ld (fdc_cmd+2),a              ; C
  ld a,e
  ld (fdc_cmd+4),a              ; R
  ld (fdc_cmd+6),a              ; EOT: just this one sector
  ret

; Send the read/write command, then wait (with a time-out: the sector can
; be a turn away, or there may be no disc) for the first byte. Once the
; data flows, a byte comes every 32 us: the loops below have no time-out,
; to keep up with it.
fdc_rw_start:
  ld (fdc_cmd),a
  ld hl,fdc_cmd
  ld b,9
  call fdc_send
  ret nc
  ld hl,SECTOR_BUF
  ld bc,FDC_MSR
  ld de,0
.wait:
  in a,(c)
  jp m,.go
  dec de
  ld a,d
  or e
  jr nz,.wait
  ret                           ; CF = 0: stuck
.go:
  scf
  ret

fdc_read:
  ld a,&46                      ; read data, MFM
  call fdc_rw_start
  ret nc
.lp:
  in a,(c)
  jp p,.lp                      ; wait for RQM
  and &20                       ; execution phase over?
  jr z,fdc_rw_end
  inc c
  in a,(c)
  ld (hl),a
  dec c
  inc hl
  jr .lp

fdc_write:
  ld a,&45                      ; write data, MFM
  call fdc_rw_start
  ret nc
.lp:
  in a,(c)
  jp p,.lp
  and &20
  jr z,fdc_rw_end
  inc c
  ld a,(hl)
  out (c),a
  dec c
  inc hl
  jr .lp

; The result phase of a read or write. The CPC can't signal the end of a
; transfer, so a good one stops at the end of the "cylinder" (EOT = R):
; ST0 = &40, ST1 = &80 (EN) and ST2 = 0.
fdc_rw_end:
  call fdc_result
  ret nc
  ld a,(fdc_res)
  and &C0
  jr z,.ok
  cp &40
  jr nz,.bad
  ld a,(fdc_res+1)
  cp &80
  jr nz,.bad
.ok:
  ld a,(fdc_res+2)
  and &3F                       ; (bit 6 = deleted data mark: fine)
  scf
  ret z
.bad:
  or a
  ret

; Command phase: send B bytes from HL.
fdc_send:
  ld a,(hl)
  inc hl
  push bc
  call fdc_put
  pop bc
  ret nc
  djnz fdc_send
  scf
  ret

; A = command byte: wait until the FDC wants one (RQM, DIO = 0), send it.
fdc_put:
  ld e,a
  ld bc,FDC_MSR
  ld d,0                        ; time-out
.wait:
  in a,(c)
  add a,a                       ; RQM -> carry, DIO -> sign
  jr nc,.busy
  jp m,.bad                     ; it has something to say instead
  inc c
  out (c),e
  call fdc_delay
  scf
  ret
.busy:
  dec d
  jr nz,.wait
.bad:
  or a
  ret

; Result phase: read bytes into fdc_res until the FDC wants commands again.
fdc_result:
  ld hl,fdc_res
  ld bc,FDC_MSR
  ld d,0
  ld e,7                        ; never store more than 7 bytes
.wait:
  in a,(c)
  add a,a
  jr nc,.busy
  jp p,.done                    ; DIO = 0: all read
  inc c
  in a,(c)
  dec c
  dec e
  jp m,.skip
  ld (hl),a
  inc hl
.skip:
  call fdc_delay
  ld d,0
  jr .wait
.busy:
  dec d
  jr nz,.wait
  or a
  ret
.done:
  scf
  ret

; The status register needs a moment after each data byte.
fdc_delay:
  push af
  ld a,8
.lp:
  dec a
  jr nz,.lp
  pop af
  ret

; Read/write data: cmd, drive/head, C, H, R, N, EOT, GPL, DTL.
fdc_cmd: db &46, &00, 0, &00, &C1, &02, &C1, &2A, &FF
