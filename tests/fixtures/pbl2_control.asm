; Programa pequeno para a integracao CPU + graficos + MMIO.
; F0000001 e uma instrucao malformada proposital, nunca HALT.
CLEAR
MOVI r1, 30
MOVI r2, 40
SPR_POSR 0, r1, r2
WAIT_FRAME
ADDI r1, r1, 1
SPR_POSR 0, r1, r2
.word 0xf0000001
STATUS r3
HALT
