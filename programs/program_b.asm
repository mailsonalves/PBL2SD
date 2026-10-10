; Programa B: cena estatica distinta com retangulo e figuras espelhadas H/V.
; A CLUT e GLOBAL: indice existente 2 (F5F5F5) e cores da figura sao
; reutilizados sem PALETTE, preservando as cores do background.
; RECT usa cantos inclusivos e expande em dois triangulos preenchidos.

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

RECT 40, 136, 120, 184, 2
SPR_POS 1, 160, 144
SPR_ATTR 1, 1, 1, 1, 0
SPR_STYLE 1, 1, 0, 0
SPR_POS 2, 184, 144
SPR_ATTR 2, 1, 1, 0, 1
SPR_STYLE 2, 2, 0, 0
HALT
