# Etapa 2 — Controle generico dos 32 sprites

Branch: `pbl2/etapa2-sprites-genericos`, criada a partir do commit `bc67ebd` da
etapa 1. A `main` permanece no ponto anterior. Esta etapa completa o acesso aos
atributos basicos dos sprites sem acrescentar banco de registradores ou ULA.

## O que mudou

Dois comandos novos permitem controlar qualquer ID de 0 a 31:

- `SET_SPRITE_POS`: altera X e Y, preservando imagem, habilitacao e flips.
- `SET_SPRITE_ATTR`: altera imagem, habilitacao e flips, preservando X e Y.

O opcode `0x6`, `UPDATE_BIRD_Y`, continua funcionando como antes para a
demonstracao original. Ele substitui os atributos completos do sprite 0:
X=152, Y informado, imagem 1, habilitado e sem espelhamento.

`cmd_decoder.v` agora produz `sat_write_mask`. `sprite_engine.v` usa essa
mascara para alterar somente os campos solicitados do registro existente:

```text
novo_registro = (registro_atual & ~mascara) | (dados & mascara)
```

Um bit 1 na mascara autoriza a alteracao; um bit 0 conserva o valor anterior.
Isso evita manter uma segunda copia da tabela de sprites no decodificador e
permite comandos consecutivos de posicao e atributos para o mesmo ID.
`gpu_de1_soc_top.v` conecta a mascara entre esses dois modulos.

As comparacoes dos limites de 16x16 agora usam um bit extra. Isso evita que
X+16 ou Y+16 volte a zero nas coordenadas proximas ao limite dos campos.

## Formatos de 32 bits

### SET_SPRITE_POS — opcode 0xA

| Bits | Campo |
|---|---|
| 31:28 | Opcode `A` |
| 27:23 | ID do sprite, 0 a 31 |
| 22:14 | X, 0 a 511 |
| 13:6 | Y, 0 a 255 |
| 5:0 | Reservados, enviar zero |

Exemplo: `A08A0F00` posiciona o sprite 1 em (40,60).
O desenho visivel continua limitado a 320x240; partes fora dessa area nao
aparecem no VGA. A posicao indica o canto superior esquerdo.

### SET_SPRITE_ATTR — opcode 0xB

| Bits | Campo |
|---|---|
| 31:28 | Opcode `B` |
| 27:23 | ID do sprite, 0 a 31 |
| 22:15 | Tile inicial da imagem, 0 a 255 |
| 14 | Enable: 1 mostra, 0 desabilita |
| 13 | FlipH: espelhamento horizontal |
| 12 | FlipV: espelhamento vertical |
| 11:0 | Reservados, enviar zero |

Exemplo: `B080C000` habilita o sprite 1 com tile inicial 1, sem espelhamentos.

Cada imagem de 16x16 usa quatro tiles de 8x8, organizados assim:

```text
base + 0 | base + 1
---------+---------
base + 2 | base + 3
```

Os identificadores de tiles possuem 8 bits. A soma e circular, modulo 256:
com base 255, os quatro tiles sao 255, 0, 1 e 2. Para imagens inteiramente
contiguas dentro do arquivo, use bases de 0 a 252. Flips alteram a imagem
inteira de 16x16, incluindo a escolha dos quadrantes.

## Programa e resultado esperado

`programs/sprites_demo.hex` possui 12 palavras. O programa primeiro limpa os
poligonos, depois configura sprites e termina em `HALT`.

| PC | Palavra | Acao |
|---|---|---|
| 0 | `0F000000` | Limpar os poligonos. |
| 1 | `B0000000` | Desabilitar o sprite 0 da demonstracao antiga. |
| 2 | `A08A0F00` | Posicionar o sprite 1 em (40,60). |
| 3 | `B080C000` | Habilitar sprite 1, imagem 1, sem flips. |
| 4 | `A1140F00` | Posicionar sprite 2 em (80,60). |
| 5 | `B102E000` | Habilitar sprite 2, imagem 5, flip horizontal. |
| 6 | `AF9E0F00` | Posicionar sprite 31 em (120,60). |
| 7 | `BF84D000` | Habilitar sprite 31, imagem 9, flip vertical. |
| 8 | `A08C1000` | Mover sprite 1 para (48,64), mantendo seus atributos. |
| 9 | `B102A000` | Desabilitar sprite 2, mantendo sua posicao. |
| 10 | `BF86F000` | Trocar sprite 31 para imagem 13 e ambos os flips, mantendo a posicao. |
| 11 | `F0000000` | Parar o programa e manter o VGA ativo. |

Ao final, os sprites 1 e 31 estao habilitados; 0 e 2 estao desabilitados. A
execucao e rapida, portanto as configuracoes intermediarias nao devem ser
interpretadas como uma animacao com duracao visivel.

## Testes reproduziveis

No ambiente em nuvem:

```bash
cd /workspace/PBL1SD
source /workspace/.pbl-tools/activate.sh
bash scripts/test_step2.sh
```

Em outra maquina, use Verilator 5, compilador C++ e Make no PATH. Nao e
necessario SDL2, ARM ou placa para os testes automatizados. Os resultados e
logs novos ficam em `.build/step2/`; a regressao da etapa 1 usa `.build/step1/`.

| Teste | Cobertura |
|---|---|
| `tb_sprite_commands` | Acesso aos 32 IDs, preservacao dos campos, habilitacao, imagem, quatro combinacoes de flips, pixels e bordas de 16x16, comandos consecutivos, espera/valid, reset e opcode antigo. |
| `tb_sprites_active_fetch` | Programa interno de 12 palavras, dez escritas de sprites, limpeza completa e um quadro VGA com enderecos e pixels reais da VRAM conferidos. |
| Quatro testes da etapa 1 | Memoria, controlador, integracao grafica original e demonstracao por botoes. |

Os seis testes devem imprimir `PASS`. Um erro ou timeout encerra o script com
codigo diferente de zero. Os avisos de HDL permanecem disponiveis nos logs.

## Usar o programa na placa posteriormente

O modo padrao continua sendo a demonstracao por botoes. Para usar a nova cena,
configure estes parametros do top-level antes de compilar:

```verilog
gpu_de1_soc_top #(
    .USE_ACTIVE_FETCH(1),
    .PROGRAM_WORDS(12),
    .PROGRAM_FILE("programs/sprites_demo.hex")
) instancia (...);
```

Esse e o mesmo conjunto de parametros usado pelo testbench de integracao. No
Quartus, aplique os valores ao top-level escolhido e inclua os arquivos listados
em `gpu.qsf`. `LEDR[3]` acende quando o programa para. Os arquivos `.sof`
antigos do repositorio nao contem essas mudancas; sera preciso recompilar.

## O que continua pendente

Esta etapa foi validada em simulacao; sintese, timing e placa permanecem
pendentes. A prioridade entre sprites ainda e fixa pelo menor ID e a
transparencia entre sprites sobrepostos ainda precisa ser corrigida. A selecao
de paleta por sprite tambem nao foi implementada.

Ainda faltam as demais partes da arquitetura do Problema 2: banco de
registradores, ULA/datapath, status, sincronizacao com quadro e programa
Assembly da ISA. A inicializacao do buffer no modo antigo e a estrategia de
troca de buffers seguem como pendencias separadas.
