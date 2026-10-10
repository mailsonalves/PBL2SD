; PBL2 demo 2: two colored triangles, an inclusive filled rectangle
; (two triangles), and transparent overlapping sprites. Vertex coordinates
; and sprite motion come from register/ALU results, not raw constant commands.
; Four finite updates use both WAIT_FRAME and polygon PRESENT then HALT.
; Double buffering applies to polygons; sprite changes are direct.
BUFFER_CONFIG 1
SPR_ATTR 0, 0, 0, 0, 0
PALETTE 250, 0xF800             ; red
PALETTE 251, 0x07FF             ; cyan
PALETTE 252, 0xFFE0             ; yellow
SPR_POS 1, 232, 64
SPR_ATTR 1, 1, 1, 0, 0
SPR_STYLE 1, 1, 0, 0
SPR_POS 2, 238, 100
SPR_ATTR 2, 1, 1, 1, 0
SPR_STYLE 2, 3, 0, 0

MOVI r1, 24                    ; moving triangle X0
MOVI r2, 48                    ; Y0
MOVI r3, 88                    ; X1
MOVI r4, 48                    ; Y1
MOVI r5, 56                    ; X2
MOVI r6, 100                   ; Y2
MOVI r7, 250                   ; triangle palette index
MOVI r8, 4                     ; finite iteration count
MOVI r9, 64                    ; moving spriteY
MOVI r10, 232                  ; spriteX

frame_loop:
WAIT_FRAME
CLEAR                          ; clear only the back polygon buffer
ADDI r1, r1, 8
ADDI r3, r3, 8
ADDI r5, r5, 8
TRI1R r1, r2
TRI2R r3, r4
TRI3R r5, r6, r7
TRI1 140, 40
TRI2 184, 104
TRI3 120, 104, 251
RECT 120, 140, 208, 176, 252    ; inclusive corners, no gaps on the diagonal
ADDI r9, r9, 8
SPR_POSR 1, r10, r9
PRESENT                        ; swap polygon buffers at next frame boundary
ADDI r8, r8, -1
JNZ frame_loop
HALT                           ; triangleX+32; sprite1 at232,96
