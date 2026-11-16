; ===========================================================================
; Video hardware: overscan CRTC set-up, Mode 1 palette, VSYNC interrupts
; ===========================================================================

; Full overscan: 48 characters (96 bytes, 384 Mode 1 pixels) by 34
; charlines (272 rows). R12/R13 use the 32K trick: when the address counter
; passes the end of the 16K page (after 21 charlines) it carries into the
; next page, so the screen covers &8000-&FFFF.
crtc_table:
  db 63, 48, 50, &8E, 38, 0, 34, 35, 0, 7, 0, 0, CRTC_R12, CRTC_R13
CRTC_COUNT equ $-crtc_table

palette:                        ; pens 0..3, border (hardware colours)
  db HW_BLACK, HW_BRIGHT_GREEN, HW_SKY_BLUE, HW_BRIGHT_WHITE, HW_BLACK

video_init:
  ld bc,&7F00+GA_MODE1_NOROM
  out (c),c
  ld bc,&7F00+RAM_BASE64
  out (c),c
  call palette_black
  ld hl,crtc_table
  xor a
.crtc:
  ld b,CRTC_SEL
  out (c),a
  ld b,CRTC_DATA+1              ; OUTI pre-decrements B
  outi
  inc a
  cp CRTC_COUNT
  jr nz,.crtc
  jp cls

palette_black:
  ld bc,&7F00
  ld a,5
.lp:
  out (c),c
  ld e,&40+HW_BLACK
  out (c),e
  inc c
  dec a
  jr nz,.lp
  ret

palette_set:
  ld hl,palette
  ld bc,&7F00
.lp:
  out (c),c
  ld a,(hl)
  or &40
  out (c),a
  inc hl
  inc c
  ld a,c
  cp 4
  jr nz,.pen
  ld c,&10                      ; after pen 3 comes the border
.pen:
  cp &11
  jr nz,.lp
  ret

cls:
  ld hl,SCREEN
  ld de,SCREEN+1
  ld bc,&7FFF
  ld (hl),0
  ldir
  ret

; ---------------------------------------------------------------------------
; Interrupts: the Gate Array fires 6 per frame (300 Hz). The one that lands
; during VSYNC (PPI port B bit 0) marks the start of a new frame.
; ---------------------------------------------------------------------------
int_handler:
  push af
  push bc
  ld b,PPI_B
  in a,(c)
  rra
  jr nc,.done
  ld a,(vsync_count)
  inc a
  ld (vsync_count),a
.done:
  pop bc
  pop af
  ei
  ret

; Wait for the next VSYNC. Counts frames that the previous loop overran
; (more than one VSYNC since the last call) in frame_drops.
wait_frame:
  ld hl,vsync_count
  ld a,(last_vsync)
  cp (hl)
  jr z,.wait
  ; already late: the last frame took more than 1/50 s
  ld a,(frame_drops)
  inc a
  jr z,.wait                    ; saturate at 255
  ld (frame_drops),a
.wait:
  ld a,(last_vsync)
.w:
  cp (hl)
  jr z,.w
  ld a,(hl)
  ld (last_vsync),a
  ret
