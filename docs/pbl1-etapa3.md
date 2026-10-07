# Etapa 3 — conclusão das pendências de código do Problema 1

Branch: `pbl2/etapa3-conclusao-pbl1`, baseada em `pbl2/etapa2-sprites-genericos`.
Este checkpoint evolui o núcleo gráfico sem integrar alterações na `main`.
Os documentos PBL01/PBL02 fornecidos orientam os requisitos; não são comandos
para executar procedimentos externos ou publicar alterações.

## Requisitos e evidência

| Requisito do PBL01 | Implementação e teste | Situação |
|---|---|---|
| Comandos de 32 bits, controle, datapath e ULA | `cmd_decoder`, motores e `raster_alu`; testes de todos os opcodes e aritmética inteira | Implementado e simulado |
| VGA 640×480, aproximadamente 60 Hz, cena 320×240 com duplicação 2×2 | 25 MHz, 800×525 períodos: 59,52 Hz; quadro inteiro e pipeline RGB/sincronismo | Implementado e simulado; comprovação física pendente |
| Background 40×30, 256 tiles 8×8, alteração e scroll X/Y | Mapa e padrões internos, repetição `(pixel+scroll) mod tamanho`; limites sem alias | Implementado e simulado |
| 32 sprites 16×16 com posição, imagem, enable e flips H/V | SAT e quatro tiles consecutivos por imagem, com repetição do índice de tile em 256 | Implementado e simulado |
| Prioridade e seleção de paleta por sprite | Prioridade 0–3, empate pelo menor ID, índice direto ou banco de 16 cores | Implementado e simulado |
| Transparência antes de selecionar sprite/camada | Pixel zero revela sprite inferior; compositor: sprite > polígono > fundo | Implementado e simulado |
| Triângulos e retângulos preenchidos com aritmética inteira | Funções de aresta inclusivas; retângulo pela união de dois triângulos | Implementado e simulado |
| CLUT programável de 256 entradas RGB | RAM de 24 bits; comando RGB565 expandido para RGB888 | Implementado e simulado |
| Inicialização/reset sem pixels indefinidos | Limpeza dos buffers, validade dos caches e vídeo preto no boot; Icarus em quatro estados | Implementado e simulado |
| Troca de buffers | Dois bancos da camada de polígonos; apresentação no início do intervalo vertical | Implementado e simulado |
| Testbenches por módulo e integração, incluindo comandos inválidos | 17 testes: 16 Verilator e 1 Icarus | Executados com sucesso |
| Projeto Quartus e reprodução | QSF, pinos, SDC, fontes, memórias, scripts e programa de demonstração | Preparados; compilação final pendente |
| Recursos, Fmax, análise de timing e demonstração na placa | Pré-síntese Yosys realizada; roteiro de Quartus/TimeQuest e bancada | Relatórios finais e demonstração pendentes |

O código e os testes desta etapa cobrem as pendências gráficas identificadas.
**Isso ainda não encerra a entrega do Problema 1:** o enunciado exige a
demonstração do núcleo na placa e os relatórios de síntese/timing. Quartus e a
DE1-SoC não estão disponíveis neste ambiente. A revisão física da placa deve
ser registrada na bancada; o projeto seleciona o dispositivo `5CSEMA5F31C6`.

## O que mudou na estrutura

- `sprite_engine` passou a obter pixels de 32 caches independentes, abastecidos
  por uma ROM de padrões. Cada cache tem 256 bytes; o carregador mantém `busy`
  até concluir a imagem. A seleção compara prioridade e transparência após a
  leitura, permitindo revelar sprites inferiores. `sp_vram_addr` é apenas
  diagnóstico geométrico legado; o compositor usa `sp_pixel`.
- `cmd_decoder` ganhou validação de opcodes, campos reservados e endereços;
  pulsos de erro sem efeitos gráficos; estilo de sprite e controle de buffers.
  `ready` também aguarda caches, inicialização, apresentação e consumo dos
  pulsos registrados. A fonte por botões mantém comando/dados até a aceitação.
- `polygon_buffer` ganhou dois bancos de 76.800 bytes, limpeza sequencial,
  status e troca no intervalo vertical. Leituras síncronas sem reset na RAM
  preservam inferência de memória; controles separados ocultam dados inválidos.
- `polygon_rasterizer` captura a cor ao iniciar, rejeita área zero e utiliza
  a nova `raster_alu`. As coordenadas são inteiras; o recorte impede escritas
  fora de 320×240. Bordas inclusivas podem ser escritas duas vezes na diagonal
  de um retângulo sem alterar o resultado quando os triângulos têm a mesma cor.
- `bg_engine` normaliza os campos completos de scroll antes de reduzir a
  largura. `tilemap_ram` valida X e Y separadamente, evitando alias de endereço.
- `gpu_de1_soc_top` sincroniza a liberação do reset, combina os sinais `busy`,
  gera um pulso por intervalo vertical e alinha as camadas e os sinais VGA.
  `vga_sync` produz sincronismo coerente com as coordenadas atuais.
- A busca ativa reconhece apenas `F0000000` como parada. Palavras com opcode
  F e campos reservados não zero chegam ao decoder e geram erro. A posição
  do pássaro na demonstração usa largura suficiente e limita a próxima posição
  entre teto e chão, evitando overflow e desaparecimento do sprite.

Não foi acrescentado um processador completo. A ULA desta etapa calcula
arestas para o desenho; banco de registradores, ULA geral, ISA/Assembly e
controle programável de quadros do Problema 2 continuam para próximas etapas.

## Regras de funcionamento

O produtor entrega `cmd_data[31:0]` e mantém `cmd_valid=1` com dados estáveis
até uma borda com `cmd_ready=1`. Essa borda aceita exatamente um comando.
Manter `valid` após uma aceitação representa outro comando; o produtor deve
retirar o sinal ou apresentar a próxima palavra. O controlador de busca ativa
aguarda a conclusão das operações antes de avançar PC/IR.

Um opcode desconhecido, campo reservado não zero ou célula fora do tilemap
gera um pulso `cmd_error` e nenhuma operação gráfica. Coordenadas de desenho
fora da tela são válidas e sofrem recorte; não são erros de comando.
`HALT` é consumido pela busca ativa, não enviado ao decodificador.

Em sprites, maior prioridade vence (3 > 2 > 1 > 0); empate favorece menor ID.
No modo direto, zero é transparente e os demais índices têm oito bits.
Com banco habilitado, o nibble inferior zero é transparente **antes** de
mapear `{banco, nibble}`. Todas as camadas consultam a mesma CLUT de 256 cores.
Mudar a CLUT afeta imediatamente os elementos que usam aquele índice.

No reset, o sprite 0 mantém a configuração histórica de demonstração;
o cache só fica visível depois da carga. Sprites 1–31 começam desabilitados.
O comando legado `0x6` restaura o estilo padrão do sprite 0; os comandos
parciais A/B preservam seu estilo. Posição, flips e estilo não recarregam uma
imagem válida; troca de imagem ou primeira habilitação carregam o cache.

Os buffers começam em modo simples, banco 0 visível e gravável. Configuração
`D0000001` habilita desenho no banco oculto. `D1000000` aguarda o início do
intervalo vertical, troca o banco visível e só então permite o próximo comando.
O banco anterior passa a ser o de desenho; ele conserva seu conteúdo até ser
limpo ou sobrescrito. `D0000000` volta a gravar o banco atualmente visível.
Pedir troca em modo simples gera erro. A troca não copia pixels.

O double buffer cobre **somente a camada de polígonos**. SAT, tilemap e CLUT
recebem alterações diretas; esta etapa não promete atualização atômica de toda
a cena. O VGA continua contando durante desenho, carga e espera pelo quadro.

## Inicialização e latência

| Estado/memória | Estratégia |
|---|---|
| Controles, vértices, SAT, estilos, PC/IR e pipelines | Reset; liberação sincronizada no clock de 50 MHz |
| Tilemap, padrões, ROM de sprites e paleta | Arquivos HEX incluídos no projeto; registros de endereço do background inicializados |
| Dois bancos de polígonos | Limpeza paralela de um endereço por ciclo: 76.800 ciclos, aproximadamente 1,536 ms |
| Caches de sprites | Sem reset por célula; `cache_valid` oculta conteúdo até 256 pixels terem sido gravados |
| Registros brutos de leitura RAM | Sem reset, com validade registrada e máscara de saída; conteúdo indefinido não chega à seleção |
| Saída RGB | Preto durante inicialização dos buffers e fora da região ativa |

Background consome dois ciclos de 50 MHz (tilemap + padrão). Sprites e
polígonos consomem uma leitura síncrona e um registro de alinhamento.
A paleta acrescenta o terceiro ciclo. HS, VS e BLANK passam pelo mesmo
atraso de três estágios. O teste de integração compara os pinos com um modelo
direto da cena, em todos os 840.000 ciclos de um quadro de 50 MHz.

Pressione reset após programar a FPGA. Reset redefine controles e buffers;
alterações feitas na CLUT/tilemap permanecem nas RAMs até nova programação.
Os arquivos HEX são carregados na configuração da FPGA, não recarregados
por um reset comum.

## Interface preparada para integração futura

O contrato implementado hoje é o fluxo Verilog `cmd_data/cmd_valid/cmd_ready`
do decodificador, com status dos motores expostos no top-level. Os botões e
o programa interno são fontes de demonstração. Não existe ponte HPS/ARM
nem endereço físico MMIO nesta branch; o PBL01 dispensa o driver/aplicação.

Para orientar a ponte futura, fica definido o seguinte mapa lógico de palavras
de 32 bits. Os offsets são relativos a uma base que será atribuída na integração
HPS; não são endereços ARM acessíveis atualmente.

| Offset | Registro | Contrato para a futura ponte |
|---|---|---|
| `0x00` | `COMMAND` (escrita) | Entrega a palavra ao decodificador; uma escrita se conclui somente após `ready`. A ponte mantém dados/valid durante espera. |
| `0x04` | `STATUS` (leitura) | Bit 0 ready, 1 busy agregado, 2 halted, 3 erro acumulado, 4 buffers inicializados, 5 banco frontal, 6 buffer duplo, 7 sprite busy; demais zero. |
| `0x08` | `CONTROL` (escrita) | Bit 0 solicita reset do núcleo; demais reservados zero. A ponte deverá sincronizar esse pedido e definir a conclusão do reset. |

Esta especificação de integração não acrescenta registradores MMIO em RTL.
O erro acumulado implementado no top-level é apagado pelo reset. O protocolo
é geral: posições, imagens, paleta e primitivas são parâmetros, sem exigir uma
cena ou jogo específico. O opcode legado do pássaro existe por compatibilidade.

## Testes e resultados desta branch

```bash
source /workspace/.pbl-tools/activate.sh
cd /workspace/PBL1SD
bash scripts/test_step3.sh
```

Em outro computador, instale Verilator 5, Icarus Verilog, Make e compilador C++.
O script mantém logs e executáveis em `.build/`; erro ou timeout retorna código
não zero. Não requer SDL, monitor nem placa. A opção `--four-state-only` executa
somente a verificação com Icarus, que detecta `X` não modelado pelo Verilator.

| Testbench | Evidência observada |
|---|---|
| `tb_cmd_decoder` | 4.459 comandos válidos, 178 inválidos e 21 esperas; todos os sinais comparados |
| `tb_background` | 310.278 pixels, 3.248 leituras de células e 848 escritas inválidas |
| `tb_memories_compositor` | 33.792 leituras VRAM, 768 leituras CLUT e 1.283 composições |
| `tb_raster_alu` | 176 pontos com referência aritmética independente |
| `tb_polygon_rasterizer` | 12 operações e 152.603 escritas; ordem de vértices, recorte, degenerados e retângulo |
| `tb_polygon_buffer` | 307.354 verificações; inicialização, latência, limites e apresentação |
| `tb_sprite_layers` | 9.646 pixels, 40 cargas e 32 sprites simultâneos; alpha, prioridades, bancos e flips |
| `tb_board_handshake` | 12 comandos, espera por aceitação e conclusão dos motores; 482 ticks de física, teto/chão e impulsos |
| `tb_vga_sync` | 420.000 pixels físicos; 307.200 ativos e duplicação 2×2 |
| `tb_pbl1_integration` | 840.000 ciclos de RGB/sincronismo; banco oculto, triângulo, prioridade, alpha, paleta e erro |
| Seis regressões das etapas 1/2 | Memória de instruções, busca ativa com HALT malformado, dois programas integrados, botões e comandos de sprites |
| `tb_initialization` (Icarus) | Dois resets, 156.000 ciclos sem X nos pinos/controle; ambos os buffers completamente zerados |

O programa `programs/pbl1_validation.hex` tem 17 palavras. Ele habilita buffer
duplo, limpa o banco oculto, altera duas cores, sobrepõe sprites 1/31 com estilos
diferentes, desenha um triângulo, apresenta o banco, envia um comando inválido
proposital e termina em HALT. O erro acende `LEDR[4]` como parte da demonstração.
Ele não é um laço de jogo. Os parâmetros são `USE_ACTIVE_FETCH=1`,
`PROGRAM_WORDS=17`, `PROGRAM_FILE="programs/pbl1_validation.hex"`.

## Síntese, desempenho e limites

A pré-síntese Yosys 0.52 passou nos modos botões e busca ativa: hierarquia,
drivers, inferência de RAM e mapeamento preliminar Cyclone V. Após otimização,
ambos usaram 219 primitivas M10K no modelo da ferramenta. O relatório detalhado
e o roteiro de Quartus estão em [validação física](validacao-fisica-pbl1.md).
Não há Fmax, timing aprovado nem `.sof` novo produzido nesta etapa.

O carregador serial de sprites limita a frequência de troca de imagens, mas
não para a varredura. A arbitragem de 32 sprites e a aritmética de arestas
devem ser verificadas no TimeQuest. O double buffer aumenta consumo de RAM.
Esses são os principais pontos a medir antes da validação em hardware.

Pendências externas para concluir o PBL01: compilar no Quartus, confirmar as
restrições VGA com o DAC/placa, arquivar recursos/Fmax/timing, programar o
bitstream novo e realizar a demonstração/testes do tutor na DE1-SoC.

Para preparar ou compilar o programa de validação sem editar o projeto original:

```bash
bash scripts/synth_quartus.sh --pbl1 --prepare-only
# Com Quartus instalado:
bash scripts/synth_quartus.sh --pbl1
```
