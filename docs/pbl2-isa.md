# ISA programável de 32 bits — etapa 4

Contrato de implementação. O opcode está em [31:28]. Endereços de programa
são índices de palavras, não bytes. R0 é zero; R1–R15 têm 32 bits e reset zero.
Operações aritméticas usam complemento de dois com resultado módulo 2^32.

Os comandos gráficos 0,1,3,5,6,7,8,9,A,B,C,D da etapa 3 permanecem válidos.
Podem ser escritos diretamente no programa. Opcode 4 envia um comando calculado
em um registrador; o comando é validado pelo decoder gráfico, sem reinterpretação
como instrução do processador. F0000000 é HALT; qualquer outro F gera erro.

## Opcode 2: registradores e ULA

[27:24]=subop, [23:20]=rd, [19:16]=rs, [15:12]=rt, [11:0]=zero,
salvo os formatos imediatos abaixo. Campos não utilizados devem ser zero.

| Subop | Assembly | Campos / efeito |
|---|---|---|
| 0 | LDI rd, imm20 | [19:0] imediato sem sinal |
| 1 | ADD rd, rs, rt | Soma |
| 2 | SUB rd, rs, rt | Subtração |
| 3 | AND rd, rs, rt | E bit a bit |
| 4 | OR rd, rs, rt | OU bit a bit |
| 5 | XOR rd, rs, rt | OU exclusivo |
| 6 | SHL rd, rs, rt | Deslocamento lógico à esquerda; quantidade rt[4:0] |
| 7 | SHR rd, rs, rt | Deslocamento lógico à direita; quantidade rt[4:0] |
| 8 | CMP rs, rt | rd=0; atualiza flags da subtração, sem escrita |
| 9 | MOV rd, rs | rt=0; copia, sem alterar flags |
| A | ADDI rd, rs, imm16 | [15:0] imediato com sinal |
| B | IN rd, port | rs=porta; [15:0]=0; portas 0=SW, 1=KEY pressionadas, 2=contador de quadros |
| C | STATUS rd | [19:0]=0; captura status |
| D | CLRE | [23:0]=0; limpa erro acumulado |
| E | LUI rd, imm16 | [19:16]=0; resultado imm16<<16 |
| F | ORI rd, rs, imm16 | OU com imediato sem sinal |

ADD/SUB/AND/OR/XOR/SHL/SHR/CMP/ADDI/ORI atualizam Z,N,C,V. LDI/MOV/LUI/IN/STATUS
preservam flags. SUB/CMP: C=1 significa ausência de empréstimo. Operações lógicas
zeram C/V. Deslocamentos usam C como último bit deslocado; quantidade zero dá C=0.
V só é significativo para soma/subtração. BLT/BGE usam N XOR V, com comparação signed.

Opcode 4: CMD rs — [27:24]=registrador fonte; [23:0]=0.

## Opcode E: fluxo, quadro e saída de demonstração

| Subop [27:24] | Assembly | Campos |
|---|---|---|
| 0 | WAIT_FRAME | [23:0]=0; aguarda próximo frame_boundary após entrar na espera |
| 1 | JMP label | [23:16]=0; [15:0]=PC absoluto |
| 2 | BEQ label | Mesmo formato; salta se Z=1 |
| 3 | BNE label | Salta se Z=0 |
| 4 | BLT label | Salta se N XOR V=1 |
| 5 | BGE label | Salta se N XOR V=0 |
| 6 | OUT port, rs | [23:20]=rs, [19:16]=port=0, [15:0]=0; saída de diagnóstico de 32 bits |

Saltos exigem destino dentro de PROGRAM_WORDS; instruções inválidas acumulam erro,
não alteram registradores/saídas gráficas e avançam PC. HALT mantém PC/IR e VGA.
Após um comando gráfico aceito, SETTLE protege o start registrado, e a execução
aguarda cmd_ready e ausência de busy antes de avançar PC/IR.

## Status e entradas

Bits: 0 Z, 1 N, 2 C, 3 V, 4 ERROR, 5 HALTED, 6 GRAPHICS_BUSY, 7 WAITING_FRAME,
8 BUFFER_INITIALIZED, 9 FRONT_BUFFER, 10 DOUBLE_BUFFERED, 11 CMD_READY; demais zero.
Flags e erro são registrados; estados dos motores são observáveis no status.
Erro gráfico ou de instrução vence CLRE na mesma borda. Reset limpa flags e erro.

IN porta0 retorna SW[9:0] sincronizadas. Porta1 retorna bits 0=KEY1, 1=KEY2,
2=KEY3, ativos em 1, sincronizados e filtrados. Porta2 retorna contador de quadros
de 32 bits incrementado no início do intervalo vertical, independentemente da CPU.
OUT porta0 alimenta o identificador da tela nos três LEDs inferiores.

## Sintaxe Assembly e pseudoinstruções

Um comando por linha, comentários `;` ou `#`, labels `nome:`. Literais decimal,
0xhex e 0bbin. Registradores R0..R15. `.word valor32` injeta uma palavra explícita.
LI rd,valor32 usa LDI se couber em 20 bits, senão LUI + ORI. A resolução de labels
considera essa expansão. LI longa atualiza flags na ORI final; LI curta preserva
flags como LDI. Não coloque uma LI longa entre CMP e o salto que usa suas flags.
Pseudoinstruções gráficas preservam os formatos da etapa3:
CLEAR; PALETTE addr,rgb565; TILE x,y,id; SCROLL x,y; SPRPOS id,x,y;
SPRATTR id,tile,enable,flipH,flipV; SPRSTYLE id,priority,paletteEnable,bank;
V0 x,y; V1 x,y; TRI x,y,color; BUFFER 0/1; PRESENT; HALT.
RETANGLE/loops são escritos com vértices/triângulos e registradores/saltos.
