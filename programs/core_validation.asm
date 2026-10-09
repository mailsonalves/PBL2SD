; Finite CPU smoke program. OUT0=0x12345678 indicates all branches succeeded.
; Graphics: one direct palette update and one register-generated scroll command.
; The invalid raw word is intentional: STATUS must record it and CLRE clear it.
start:
    LI R1, 0x12345678
    MOV R2, R1
    LDI R3, 7
    LDI R4, 3
    ADD R5, R3, R4             ; 10
    SUB R6, R3, R4             ; 4
    CMP R6, R4
    BLT failure
    BGE loop_init
    JMP failure
loop_init:
    LDI R7, 3
loop:
    ADDI R7, R7, -1
    BNE loop
    CMP R7, R0
    BEQ logic
    JMP failure
logic:
    LDI R8, 0x0F
    LDI R9, 0x33
    AND R9, R8, R9             ; 3
    OR R9, R9, R8              ; 15
    XOR R9, R9, R8             ; 0
    ADDI R9, R9, 7
    LDI R10, 1
    SHL R9, R9, R10            ; 14
    SHR R8, R9, R10            ; 7
    LI R8, 0x50000A14          ; SCROLL 10,20 command for later CMD
    LI R11, -1
    CMP R11, R0
    BLT signed_ok
    JMP failure
signed_ok:
    LI R11, 0x7FFFFFFF
    ADDI R11, R11, 1           ; 0x80000000: N=1,V=1,Z=0,C=0
    BGE overflow_ok            ; signed comparison uses N XOR V
    JMP failure
overflow_ok:
    STATUS R12
    .word 0x2D000001           ; invalid CLRE reserved bit; no flags/register effects
    STATUS R13                ; ERROR=1
    CLRE
    STATUS R14                ; ERROR=0
    IN R3, 0                  ; synchronized switches
    IN R4, 1                  ; synchronized pressed keys
    IN R7, 2                  ; frame count before WAIT_FRAME
    WAIT_FRAME
    PALETTE 255, 0xF800
    CMD R8
    STATUS R15
    OUT 0, R1
    HALT
failure:
    OUT 0, R0
    HALT
