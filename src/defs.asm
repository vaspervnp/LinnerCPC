; ===========================================================================
; Hardware ports, key codes and game constants
; ===========================================================================

; --- Gate Array (&7Fxx) -----------------------------------------------------
GA              equ &7F
GA_MODE1_NOROM  equ &8D         ; mode 1, upper + lower ROM off
RAM_BASE64      equ &C0         ; standard 64K map

; --- CRTC -------------------------------------------------------------------
CRTC_SEL        equ &BC
CRTC_DATA       equ &BD

; --- PPI --------------------------------------------------------------------
PPI_A           equ &F4
PPI_B           equ &F5         ; bit 0 = VSYNC
PPI_C           equ &F6

; --- Screen: Mode 1 overscan 384x272, single buffer at &8000 ----------------
SCREEN          equ &8000
SCREEN_W        equ 384
BYTES_PER_LINE  equ 96
CRTC_R12        equ &2C         ; page 2 + 32K overscan bits
CRTC_R13        equ &10         ; 16 words in: charline 21 starts at &C000

; Hardware colour numbers (Gate Array value without the &40)
HW_BLACK        equ &14
HW_BRIGHT_GREEN equ &12
HW_SKY_BLUE     equ &17
HW_BRIGHT_WHITE equ &0B
HW_BRIGHT_MAGENTA equ &0D
HW_BRIGHT_RED   equ &0C
HW_BRIGHT_YELLOW equ &0A
HW_ORANGE       equ &0E
HW_BLUE         equ &04

; Pens (Mode 1): 0 void, 1 ground, 2 water, 3 Linner / foes / shots
PEN_VOID        equ 0
PEN_GROUND      equ 1
PEN_WATER       equ 2
PEN_HERO        equ 3

; --- Keyboard matrix codes: &LB = line L, bit B ------------------------------
KEY_UP          equ &00
KEY_RIGHT       equ &01
KEY_DOWN        equ &02
KEY_LEFT        equ &10
KEY_SPACE       equ &57
KEY_ESC         equ &82
JOY_UP          equ &90
JOY_DOWN        equ &91
JOY_LEFT        equ &92
JOY_RIGHT       equ &93
JOY_FIRE2       equ &94
JOY_FIRE1       equ &95

; pad bits (keyboard and joystick combined)
PAD_UP          equ 0
PAD_DOWN        equ 1
PAD_LEFT        equ 2
PAD_RIGHT       equ 3
PAD_FIRE        equ 4
PAD_JUMP        equ 5

; --- Terrain ----------------------------------------------------------------
; A column's height key: 0..126 = ground at game y 128+key, bit 7 set = water,
; &FF = gap (no ground).
GROUND_TOP      equ 128         ; game y of key 0
KEY_GAP         equ &FF
KEY_WATER       equ &80

; --- Linner -----------------------------------------------------------------
HERO_X          equ 30          ; fixed screen x of Linner's centre: his own
                                ; width (2 x LINNER_R) free behind him
                                ; (tools/gen_tables.py, level2asm.py: HERO_X)
HERO_XB0        equ (HERO_X-12)>>2  ; byte columns under Linner (x +-10)
HERO_XB1        equ (HERO_X+12)>>2
GEARS           equ 5
