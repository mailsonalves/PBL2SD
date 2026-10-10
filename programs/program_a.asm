; Programa A: cena estatica com triangulo e duas figuras sem espelhamento.
; A CLUT e GLOBAL: indices existentes 18 (E7343E) e cores da figura sao
; reutilizados sem PALETTE, preservando as cores do background.
; Inicializacao explicita permite reiniciar A/B depois de outras cenas.

BUFFER_CONFIG 0
CLEAR
SCROLL 0, 0
SPR_ATTR 0, 0, 0, 0, 0
SPR_ATTR 1, 0, 0, 0, 0
SPR_ATTR 2, 0, 0, 0, 0
SPR_ATTR 3, 0, 0, 0, 0
SPR_ATTR 4, 0, 0, 0, 0
SPR_ATTR 5, 0, 0, 0, 0
SPR_ATTR 6, 0, 0, 0, 0
SPR_ATTR 7, 0, 0, 0, 0
SPR_ATTR 8, 0, 0, 0, 0
SPR_ATTR 9, 0, 0, 0, 0
SPR_ATTR 10, 0, 0, 0, 0
SPR_ATTR 11, 0, 0, 0, 0
SPR_ATTR 12, 0, 0, 0, 0
SPR_ATTR 13, 0, 0, 0, 0
SPR_ATTR 14, 0, 0, 0, 0
SPR_ATTR 15, 0, 0, 0, 0
SPR_ATTR 16, 0, 0, 0, 0
SPR_ATTR 17, 0, 0, 0, 0
SPR_ATTR 18, 0, 0, 0, 0
SPR_ATTR 19, 0, 0, 0, 0
SPR_ATTR 20, 0, 0, 0, 0
SPR_ATTR 21, 0, 0, 0, 0
SPR_ATTR 22, 0, 0, 0, 0
SPR_ATTR 23, 0, 0, 0, 0
SPR_ATTR 24, 0, 0, 0, 0
SPR_ATTR 25, 0, 0, 0, 0
SPR_ATTR 26, 0, 0, 0, 0
SPR_ATTR 27, 0, 0, 0, 0
SPR_ATTR 28, 0, 0, 0, 0
SPR_ATTR 29, 0, 0, 0, 0
SPR_ATTR 30, 0, 0, 0, 0
SPR_ATTR 31, 0, 0, 0, 0

TRI1 40, 40
TRI2 120, 40
TRI3 80, 100, 18
SPR_POS 1, 160, 80
SPR_ATTR 1, 1, 1, 0, 0
SPR_STYLE 1, 1, 0, 0
SPR_POS 2, 184, 80
SPR_ATTR 2, 1, 1, 0, 0
SPR_STYLE 2, 2, 0, 0
HALT
