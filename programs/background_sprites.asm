; PBL2 demo 1: existing tile background, scroll computed by the ALU,
; and overlapping transparent 16x16 sprites with all four flip combinations.
; Run from PC0. Four frame-paced updates then HALT retain the final scene.
; Increase the r5 countdown for a longer animation and reassemble.
CLEAR
BUFFER_CONFIG 0
SPR_ATTR 0, 0, 0, 0, 0          ; disable the legacy bird
TILE 2, 3, 5
TILE 3, 3, 6
TILE 39, 29, 5                 ; valid last cell of the 40x30 map
SCROLL 0, 0
; Bank3: low-nibble0 remains transparent, regardless of palette entry48.
PALETTE 49, 0xF81F
PALETTE 50, 0x07E0
PALETTE 51, 0xF81F
PALETTE 52, 0x07E0
PALETTE 53, 0xF81F
PALETTE 54, 0x07E0
PALETTE 55, 0xF81F
PALETTE 56, 0x07E0
PALETTE 57, 0xF81F
PALETTE 58, 0x07E0
PALETTE 59, 0xF81F
PALETTE 60, 0x07E0
PALETTE 61, 0xF81F
PALETTE 62, 0x07E0
PALETTE 63, 0xF81F

MOVI r1, 0                      ; scrollX
MOVI r2, 0                      ; scrollY
MOVI r3, 40                     ; sprite1X
MOVI r4, 72                     ; sprite1Y
MOVI r5, 4                      ; finite iteration count
MOVI r7, 76                     ; sprite2Y
ADDI r6, r3, 6                  ; sprite2X follows sprite1, with overlap
SPR_POSR 1, r3, r4
SPR_ATTR 1, 1, 1, 0, 0
SPR_STYLE 1, 1, 0, 0
SPR_POSR 2, r6, r7
MOVI r11, 1                     ; base tile1, existing transparent bird
MOVI r12, 6                     ; bits2..0 = enable,flipH,flipV = 110
SPR_ATTRR 2, r11, r12
MOVI r13, 3                     ; highest sprite priority
MOVI r14, 0x13                  ; bank enable in bit4, bank3 in bits3..0
SPR_STYLER 2, r13, r14
SPR_POS 3, 140, 72
SPR_ATTR 3, 1, 1, 0, 1
SPR_STYLE 3, 2, 0, 0
SPR_POS 31, 180, 72
SPR_ATTR 31, 1, 1, 1, 1
SPR_STYLE 31, 0, 0, 0

frame_loop:
WAIT_FRAME                     ; next VGA frame after entry into the wait
ADDI r1, r1, 8
SCROLLR r1, r2
ADDI r3, r3, 16
SPR_POSR 1, r3, r4
ADDI r6, r3, 6
SPR_POSR 2, r6, r7
ADDI r5, r5, -1                ; updates Z used by JNZ
JNZ frame_loop
HALT                           ; final scroll32; sprites1/2 at104/110
