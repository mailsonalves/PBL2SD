# ISA do coprocessador gráfico PBL2

## Modelo de execução e sintaxe

Cada instrução ocupa 32 bits; o opcode é `[31:28]`. A CPU busca na ROM síncrona interna, captura IR e executa uma instrução por vez. O PC padrão tem 8 bits e endereça **palavras**, de 0 a 255. Branches são absolutos, sem delay slot. O incremento após 255 volta a zero; insira HALT ou um branch intencional. Quando PROGRAM_WORDS<256, um endereço maior ou igual a PROGRAM_WORDS retorna HALT.

Há 16 registradores de 32 bits; r0 é zero permanente. Reset/restart zera registradores, PC, flags e erro, e coloca HALT em IR até a busca. Escrita em r0 é descartada, mas a operação aritmética ainda atualiza flags. Não existem load/store ou memória geral de dados; registradores alimentam gráficos diretamente.

`tools/assemble.py` aceita mnemonics/registradores/labels sem diferenciar maiúsculas/minúsculas, vírgulas opcionais, inteiros decimais ou 0x e comentários ;/#//. Labels podem anteceder a instrução na mesma linha. Valores são validados; operandos imediatos não são truncados. `.WORD u32` emite uma palavra explícita, inclusive inválida, para diagnóstico.

```asm
    MOVI r1, 40
    MOVI r2, 72
    MOVI r3, 4
    SPR_ATTR 1, 1, 1, 0, 0
quadro:
    WAIT_FRAME
    ADDI r1, r1, 16
    SPR_POSR 1, r1, r2
    ADDI r3, r3, -1
    JNZ quadro
    HALT
```

SPR_POSR preserva flags; JNZ observa o contador do ADDI. MOVI estende um imediato **sem sinal de 16 bits** com zeros. ADDI estende um imediato **com sinal de 16 bits**. Shifts e OR permitem construir valores completos de 32 bits.

## Família 2 — ULA

| Bits | Campo comum |
|---|---|
| 31:28 | Opcode 2 |
| 27:24 | Suboperação |
| 23:20 | Destino rd |
| 19:16 | Fonte ra |
| 15:12 | Fonte rb em formato R; parte do imediato em formato I |
| 11:0 | Zero em formato R; parte do imediato em formato I |

| Subop | Assembly | Resultado / reservados |
|---|---|---|
| 0 | `MOVI rd, u16` | rd ← zeroextend([15:0]); ra=0. |
| 1 | `MOV rd, ra` | rd ← ra; [15:0]=0. |
| 2 | `ADD rd, ra, rb` | rd ← ra+rb módulo 2³²; [11:0]=0. |
| 3 | `SUB rd, ra, rb` | rd ← ra−rb módulo 2³²; [11:0]=0. |
| 4 | `AND rd, ra, rb` | AND bit a bit; [11:0]=0. |
| 5 | `OR rd, ra, rb` | OR bit a bit; [11:0]=0. |
| 6 | `XOR rd, ra, rb` | XOR bit a bit; [11:0]=0. |
| 7 | `SHL rd, ra, rb` | Shift lógico à esquerda por rb[4:0]; [11:0]=0. |
| 8 | `SHR rd, ra, rb` | Shift lógico à direita por rb[4:0]; [11:0]=0. |
| 9 | `CMP ra, rb` | Flags de ra−rb; nenhuma escrita; rd=0 e [11:0]=0. |
| A | `ADDI rd, ra, s16` | rd ← ra+signextend([15:0]) módulo 2³². |
| B…F | Inválido | Erro persistente, sem escrita no banco/flags. |

Todas as operações válidas atualizam flags, inclusive quando rd=0:

| Bit | Nome | Significado |
|---|---|---|
| 0 | Z | Resultado de 32 bits igual a zero. |
| 1 | N | Bit 31 do resultado. |
| 2 | C | Carry da soma; em SUB/CMP, 1 quando ra≥rb sem sinal (sem empréstimo). |
| 3 | V | Overflow com sinal em complemento de dois. |

ADD/ADDI define V quando operandos têm o mesmo sinal e resultado tem sinal oposto. SUB/CMP define V quando operandos têm sinais diferentes e resultado difere do sinal de ra. MOV/MOVI/AND/OR/XOR/SHL/SHR sempre definem C=V=0; shifts não armazenam o bit deslocado para fora. CMP usa o resultado apenas para flags. Gráficos e fluxo preservam flags.

Exemplos: MOVI r1,40 → `20100028`; ADDI r1,r1,16 → `2A110010`; CMP r1,r2 → `29012000`.

## Família 4 — gráficos por registrador

```text
31      28 27      24 23      20 19      16 15      12 11       7 6       0
+----------+----------+----------+----------+----------+----------+---------+
|    4     |  subop   |    ra    |    rb    |    rc    | spriteID |    0    |
+----------+----------+----------+----------+----------+----------+---------+
```

Índices de registrador são 0–15; ID imediato, 0–31. [6:0] e campos não usados são zero. O datapath lê até três fontes e traduz a instrução para o decoder gráfico preservado; não existe destino de registrador.

| Subop | Assembly | Valores usados | Campos adicionais zero |
|---|---|---|---|
| 0 | `EMIT ra` | Palavra inteira de 32 bits em ra. | rb, rc, ID |
| 1 | `SCROLLR ra, rb` | X=ra[8:0], Y=rb[7:0]. | rc, ID |
| 2 | `SPR_POSR id, ra, rb` | X=ra[8:0], Y=rb[7:0]. | rc |
| 3 | `TRI1R ra, rb` | X0=ra[8:0], Y0=rb[7:0]. | rc, ID |
| 4 | `TRI2R ra, rb` | X1=ra[8:0], Y1=rb[7:0]. | rc, ID |
| 5 | `TRI3R ra, rb, rc` | X2=ra[8:0], Y2=rb[7:0], cor=rc[7:0]; inicia desenho. | ID |
| 6 | `TILER ra, rb, rc` | X=ra[5:0], Y=rb[4:0], tile=rc[7:0]. | ID |
| 7 | `PALETTER ra, rb` | Endereço=ra[7:0], RGB565=rb[15:0]. | rc, ID |
| 8 | `SPR_ATTRR id, ra, rb` | Tile=ra[7:0], rb[2:0]={enable,flipH,flipV}. | rc |
| 9 | `SPR_STYLER id, ra, rb` | Prioridade=ra[1:0], rb[4:0]={palette_enable,bank[3:0]}. | rc |
| A…F | Inválido | Sem efeito gráfico. | — |

Bits altos dos **valores** são ignorados conforme a largura indicada; campos reservados da **instrução** são validados. Por exemplo, SPR_POSR com X=512 produz X=0. TILER com X=40 após mascaramento ainda é rejeitado: a área válida é 40×30. Coordenadas fora de 320×240 não provocam escritas fora da área lógica; sprites/polígonos são recortados.

EMIT encaminha ra apenas ao decoder gráfico. Um payload da família ULA, fluxo ou HALT é rejeitado como comando gráfico; não vira instrução executada pela CPU. Essa instrução permite compor comandos legados dinamicamente. Exemplo: SPR_POSR 1,r1,r2 → `42120080`.

## Gráficos imediatos e compatibilidade

Codificações válidas do PBL1 foram preservadas. Todo bit não atribuído a campo de dados, opcode ou constante é zero.

| Palavra/opcode | Assembly | Campos / efeito |
|---|---|---|
| 0F000000 | `CLEAR` | Limpa buffer de desenho de polígonos com zero e espera conclusão. |
| 1 | `PALETTE addr, rgb565` | [27:24]=0; addr[23:16], RGB565[15:0]. |
| 3 | `TILE x, y, tile` | [27:22]=0; X[21:16]<40; [15:13]=0; Y[12:8]<30; tile[7:0]. |
| 5 | `SCROLL x, y` | [27:17]=0; X[16:8] (0–511), Y[7:0] (0–255). |
| 6 | `BIRD_Y y` | [27:8]=0; Y[7:0]; sprite 0 recebe enable=1, flips=0, X=152, imagem=1 e estilo padrão. |
| 7 | `TRI1 x, y` | [27:17]=0; X0[16:8], Y0[7:0]. |
| 8 | `TRI2 x, y` | [27:17]=0; X1[16:8], Y1[7:0]. |
| 9 | `TRI3 x, y, cor` | Cor[27:20]; [19:17]=0; X2[16:8], Y2[7:0]; dispara rasterizador. |
| A | `SPR_POS id, x, y` | ID[27:23], X[22:14], Y[13:6]; [5:0]=0. Preserva imagem/enable/flips/estilo. |
| B | `SPR_ATTR id, tile, en, h, v` | ID[27:23], tile[22:15], enable[14], H[13], V[12]; [11:0]=0. Preserva posição/estilo. |
| C | `SPR_STYLE id, priority, pen, bank` | ID[27:23], prioridade[22:21], paleta enable[20], banco[19:16]; [15:0]=0. Preserva demais atributos. |
| D0000000 | `BUFFER_CONFIG 0` | Desabilita buffer duplo. |
| D0000001 | `BUFFER_CONFIG 1` | Habilita buffer duplo. |
| D1000000 | `PRESENT` | Troca buffers no evento de quadro e espera; inválido sem buffer duplo. |

RGB565 vira RGB888 por preenchimento com zeros: R={r5,000}, G={g6,00}, B={b5,000}. Triângulos incluem arestas, aceitam duas orientações e não escrevem com área zero. Cada sprite 16×16 usa quatro tiles consecutivos 8×8 em quadrantes; soma dos IDs é módulo 256. Bases 253–255 atravessam esse wrap.

Opções antes não atribuídas, **opcodes 2/4/E**, agora têm instruções válidas. A palavra `20000000`, antes usada como diagnóstico inválido, é MOVI r0,0 e atualiza flags. O diagnóstico do programa histórico de validação foi migrado para `F0000001`, que continua inválido; comandos gráficos válidos conservaram seus encodings.

## Família E — fluxo e status

| Palavra/formato | Assembly | Efeito |
|---|---|---|
| E0000000 | `NOP` | PC+1, sem efeito gráfico/aritmético. |
| E1000000 | `WAIT_FRAME` | Espera evento posterior à entrada no estado WAIT_FRAME. |
| E20000aa | `JMP alvo` | PC ← endereço absoluto de palavra. |
| E30000aa | `JZ alvo` | Branch se Z=1; caso contrário PC+1. |
| E40000aa | `JNZ alvo` | Branch se Z=0; caso contrário PC+1. |
| E5d00000 | `STATUS rd` | rd ← zeroextend({erro,V,C,N,Z}); erro bit4; preserva flags. |

JMP/JZ/JNZ exigem [23:8]=0; aa=[7:0]. STATUS usa d=[23:20] e exige [19:0]=0. NOP/WAIT_FRAME exigem a palavra exata; E6–EF são inválidas. Labels resolvem endereço **após expansão** de pseudoinstruções.

Evento coincidente com emissão de WAIT_FRAME não satisfaz a espera; é necessário outro evento. WAIT_FRAME apenas sincroniza: não troca buffers nem congela sprites/tilemap. PRESENT efetua a apresentação dos polígonos. STATUS lê flags/erro; MMIO apresenta também o estado completo de execução, conforme [hps-mmio.md](hps-mmio.md).

## HALT, erros e conclusão

**Somente F0000000 encerra o programa.** PC permanece no endereço do HALT, IR mantém a palavra e done pulsa uma vez. VGA/composição/estado gráfico continuam. Reset/restart permite nova execução. Outros words F são rejeitados pelo decoder gráfico, geram erro e avançam.

Uma instrução inválida 2/4/E é descartada antes de efeitos no banco/flags/gráficos. Comandos imediatos inválidos, inclusive TILE fora de limites e PRESENT sem buffer duplo, são rejeitados pelo decoder gráfico. Todos concluem, avançam PC e tornam o erro persistente. Reset/restart/clear_error limpa o erro; novo erro durante clear_error tem prioridade. Não existe handler de exceção.

`done` é **pulso de conclusão de instrução**, incluindo inválida e HALT; não significa programa inteiro terminado. Gráficos concluem somente após aceitação e término. `busy` indica execução/espera; `cmd_valid` apresenta gráfico até cmd_ready. [pbl2-architecture.md](pbl2-architecture.md) descreve pausa, restart e FSM.

## Pseudoinstruções e aliases

RECT x0,y0,x1,y1,cor expande para:

```asm
TRI1 x0,y0
TRI2 x1,y0
TRI3 x1,y1,cor
TRI1 x0,y0
TRI2 x1,y1
TRI3 x0,y1,cor
```

Cantos são inclusivos; o montador exige **área positiva** (`x0<x1`, `y0<y1`). RECTR rx0,ry0,rx1,ry1,rcor usa a mesma expansão na família 4, sem modificar registradores; geometria dos valores é responsabilidade do programa. Largura/altura zero produz primitivas degeneradas sem pixels. Cada expansão ocupa seis palavras.

| Alias legado | Canônico |
|---|---|
| CLEAR_SCREEN | CLEAR |
| SET_PALETTE / SET_PALETTER | PALETTE / PALETTER |
| WRITE_TILEMAP / WRITE_TILEMAPR | TILE / TILER |
| SET_SCROLL / SET_SCROLLR | SCROLL / SCROLLR |
| UPDATE_BIRD_Y | BIRD_Y |
| DRAW_TRI_V1, DRAW_TRI_V2, DRAW_TRI_V3 | TRI1, TRI2, TRI3 |
| DRAW_TRI_V1R, DRAW_TRI_V2R, DRAW_TRI_V3R | TRI1R, TRI2R, TRI3R |
| SET_SPRITE_POS / SET_SPRITE_POSR | SPR_POS / SPR_POSR |
| SET_SPRITE_ATTR / SET_SPRITE_ATTRR | SPR_ATTR / SPR_ATTRR |
| SET_SPRITE_STYLE / SET_SPRITE_STYLER | SPR_STYLE / SPR_STYLER |
| BUFFER_SWAP | PRESENT |

Aliases não acrescentam opcodes. O CLI preenche a imagem até --words (padrão 256) com HALT e rejeita programas maiores/operandos inválidos. A API `assemble(source, words=None)` produz palavras sem padding para inspeção/testes.
