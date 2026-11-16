; ===========================================================================
; Disk loader (runs at &9000 with the firmware still active)
;
; DISC.BAS sets MEMORY below &8800, loads this file and CALLs it. We pull
; LINNER.BIN into &0040 with the AMSDOS cassette-vector calls (BASIC itself
; can't load over its own program), then take over the machine.
; ===========================================================================

CAS_IN_OPEN     equ &BC77
CAS_IN_CLOSE    equ &BC7A
CAS_IN_DIRECT   equ &BC83
DISK_BUFFER     equ &8800       ; 2K AMSDOS buffer, below the loader

  org &9000
loader:
  ld hl,fn_game
  ld b,fn_end-fn_game
  ld de,DISK_BUFFER
  call CAS_IN_OPEN
  jr nc,disk_error
  ld hl,&0040
  call CAS_IN_DIRECT
  jr nc,disk_error
  call CAS_IN_CLOSE
  di
  ld bc,&FA7E                   ; drive motor off
  xor a
  out (c),a
  ld bc,&7F8D                   ; Mode 1, both ROMs off: &0040 is our RAM
  out (c),c
  jp &0040

disk_error:
  ld bc,&7F10                   ; red border: disk error
  out (c),c
  ld a,&4C
  out (c),a
  di
  halt

fn_game: db "LINNER.BIN"
fn_end:
