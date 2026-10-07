# Coprocessador gráfico 2D — PBL2SD

Projeto em Verilog para a DE1-SoC, desenvolvido por **Lucca Coutinho, Mailson Alves e Ramon Santos**, do curso de Engenharia de Computação da Universidade Estadual de Feira de Santana (UEFS).

O desenvolvimento é organizado em branches encadeadas. A etapa atual, `pbl2/etapa3-conclusao-pbl1`, trata das pendências gráficas do Problema 1 sobre a busca ativa e os sprites genéricos das etapas anteriores. A `main` permanece no ponto já publicado, até autorização para integrar as alterações.

O RTL possui background por tiles, 32 sprites, rasterização de polígonos, composição e paleta de cores. Os testes de simulação e os procedimentos de síntese são reproduzíveis. **A compilação final no Quartus, a análise de timing e a demonstração desta versão na placa continuam necessárias.** Consulte o [guia da etapa 3](docs/pbl1-etapa3.md) e o [roteiro de validação física](docs/validacao-fisica-pbl1.md).

## Arquitetura

```text
Botões OU memória de instruções → controle de comandos → motores gráficos
                                                            ↓
VGA: coordenadas e evento de quadro → composição → paleta → RGB e sincronismo
```

| Módulo | Responsabilidade |
|---|---|
| `gpu_de1_soc_top` | Integração, seleção da origem de comandos, reset, clocks, alinhamento dos pixels e pinos da placa. |
| `board_input_controller` | Demonstração por botões, com espera pela aceitação dos comandos. |
| `instruction_memory` / `active_fetch_controller` | Programa interno, PC, IR, execução sequencial, espera por conclusão e `HALT`. |
| `cmd_decoder` | Validação dos campos e envio de operações aos motores; comando inválido gera erro sem alterar as unidades gráficas. |
| `vga_sync` | Contadores, sincronismo, área visível, coordenadas lógicas e intervalo vertical. |
| `bg_engine` / `tilemap_ram` | Mapa 40×30 de tiles 8×8, atualização de células e rolagem nos dois eixos. |
| `pattern_vram` | Padrões indexados de 256 tiles, carregados de `tiles.hex`. |
| `sprite_engine` | 32 sprites 16×16, posição, imagem, habilitação, espelhamentos, prioridade, transparência e banco de paleta. |
| `polygon_rasterizer` / `raster_alu` | Controle de varredura e datapath inteiro de funções de aresta para preencher triângulos. Retângulos usam dois triângulos. |
| `polygon_buffer` | Inicialização sequencial e dois buffers para a camada de polígonos, com troca no intervalo vertical. |
| `compositor` / `color_palette` | Prioridade sprite → polígono → background e tradução do índice para RGB de 24 bits. |

A entrada é 50 MHz e o clock VGA é 25 MHz. Com 800 períodos por linha e 525 linhas por quadro, a frequência real é aproximadamente **59,52 Hz**. A área física é 640×480; a cena lógica é 320×240, ampliada em 2×2.

A `raster_alu` é uma **ULA gráfica especializada**, usada pelo rasterizador. Ela não substitui o banco de registradores, a ULA geral e o datapath de execução de instruções que ainda serão desenvolvidos para o Problema 2. O registrador de status, o controle programável de quadros e a ISA/Assembly completos também permanecem para os próximos checkpoints.

## Renderização e memória

- O background usa `tilemap_data.hex`; padrões e paleta usam `tiles.hex` e `palette.hex`. As escritas no mapa rejeitam coordenadas fora de 40×30 e a rolagem trata os campos completos sem truncar a soma antes da repetição.
- Cada sprite tem um cache de 256 pixels. Uma ROM de padrões abastece os caches por 256 leituras sequenciais, com latência adicional do pipeline. `busy` permanece ativo até o último pixel ser gravado; um cache inválido não é exibido. Isso evita replicar toda a ROM para cada sprite.
- Entre sprites opacos, vence o maior valor de prioridade, de 0 a 3; no empate, vence o menor ID. Pixels transparentes permitem ver os sprites atrás deles.
- Sem banco de paleta, o índice completo de oito bits é usado e zero é transparente. Com banco habilitado, o índice é `{banco[3:0], pixel[3:0]}` e o nibble inferior zero é transparente, independentemente do banco.
- O rasterizador captura os vértices e a cor ao iniciar. Arestas são inclusivas, as duas ordens de vértices são aceitas e triângulos de área zero não escrevem pixels. O recorte de escrita é 320×240.
- Os dois buffers de polígonos são limpos no reset. Com buffer duplo habilitado, os desenhos vão para o buffer de trás; uma solicitação de apresentação aguarda o evento de quadro e libera o próximo comando após a troca.

**O buffer duplo cobre somente os polígonos.** Escritas em sprites, tilemap e CLUT continuam diretas e não são atualizações atômicas do quadro inteiro. O VGA segue funcionando durante a inicialização, desenhos, carregamento de sprites e espera pela apresentação.

## Comandos de 32 bits

O opcode ocupa `[31:28]`. Campos reservados devem ser zero. Os comandos de sprites usam ID em `[27:23]`, de 0 a 31.

| Opcode / palavra | Comando | Campos e efeito |
|---|---|---|
| `0F000000` | `CLEAR_SCREEN` | Limpa o buffer de desenho de polígonos com índice zero. |
| `0x1` | `SET_PALETTE` | `[23:16]` endereço; `[15:0]` cor RGB565. |
| `0x3` | `WRITE_TILEMAP` | `[21:16]` X; `[12:8]` Y; `[7:0]` tile. |
| `0x5` | `SET_SCROLL` | `[16:8]` X; `[7:0]` Y. |
| `0x6` | `UPDATE_BIRD_Y` | `[7:0]` Y. Compatibilidade: sprite 0, X=152, tile=1, habilitado, sem flips e estilo padrão. |
| `0x7` | `DRAW_TRI_V1` | `[16:8]` X0; `[7:0]` Y0. |
| `0x8` | `DRAW_TRI_V2` | `[16:8]` X1; `[7:0]` Y1. |
| `0x9` | `DRAW_TRI_V3` | `[27:20]` cor; `[16:8]` X2; `[7:0]` Y2. Inicia o desenho. |
| `0xA` | `SET_SPRITE_POS` | `[27:23]` ID; `[22:14]` X; `[13:6]` Y. Preserva os atributos. |
| `0xB` | `SET_SPRITE_ATTR` | `[27:23]` ID; `[22:15]` tile inicial; `[14]` enable; `[13]` flip horizontal; `[12]` flip vertical. Preserva a posição e o estilo. |
| `0xC` | `SET_SPRITE_STYLE` | `[27:23]` ID; `[22:21]` prioridade; `[20]` habilitação de banco; `[19:16]` banco de paleta. |
| `D0000000` / `D0000001` | `BUFFER_CONFIG` | Desabilita / habilita buffer duplo de polígonos. |
| `D1000000` | `BUFFER_SWAP` | Solicita apresentação no intervalo vertical; exige buffer duplo habilitado. |
| `F0000000` | `HALT` | Encerra o programa da busca ativa, mantendo o VGA. |

`HALT` é tratado pelo controlador de busca, não pelo decodificador gráfico. Os formatos acima descrevem os comandos atuais; a ISA programável completa do Problema 2 será consolidada nas próximas etapas.

## Testes reproduzíveis

Use Verilator 5, compilador C++, Make e Icarus Verilog no `PATH`. Os testes RTL dispensam placa e SDL2. Neste ambiente em nuvem:

```bash
cd /workspace/PBL1SD
source /workspace/.pbl-tools/activate.sh
bash scripts/test_step3.sh
```

O script executa os testes da etapa 3, a regressão das etapas anteriores e a verificação de inicialização com Icarus Verilog. Para executar apenas a verificação em quatro estados (`0`, `1`, `X`, `Z`):

```bash
bash scripts/test_step3.sh --four-state-only
```

Os testbenches conferem sprites, prioridades, transparência, paleta, background e limites, memórias e compositor, rasterização, reset, comandos inválidos, espera por aceitação, buffers e VGA. Erro ou timeout deve interromper a execução com código diferente de zero; cada teste concluído imprime `PASS`. Consulte o [guia da etapa 3](docs/pbl1-etapa3.md) para comandos, cobertura e resultados da execução desta branch.

## Executar os programas internos

O top-level mantém `USE_ACTIVE_FETCH=0` como padrão: `KEY[0]` é reset, `KEY[1]` aplica impulso ao pássaro, `KEY[2]` solicita triângulo e `KEY[3]` solicita retângulo.

Com busca ativa, os parâmetros padrão são `PROGRAM_WORDS=9` e `PROGRAM_FILE="programs/fetch_demo.hex"`. Para o programa de validação gráfica de 17 palavras, configure:

```verilog
gpu_de1_soc_top #(
    .USE_ACTIVE_FETCH(1),
    .PROGRAM_WORDS(17),
    .PROGRAM_FILE("programs/pbl1_validation.hex")
) instancia (...);
```

A seleção é feita na compilação, não por chave física. O programa é finito: configura a cena e termina em `HALT`; não implementa ainda um jogo completo nem um laço Assembly. `LEDR[3]` indica parada do programa, `LEDR[4]` registra erro de comando, `LEDR[5]` indica buffers inicializados e `LEDR[7]` indica buffer duplo habilitado.

Os guias históricos das [etapas 1](docs/pbl2-etapa1.md) e [2](docs/pbl2-etapa2.md) descrevem aqueles checkpoints. As limitações citadas neles devem ser interpretadas conforme a versão de cada etapa.

## Síntese e teste na DE1-SoC

O precheck usa Yosys para verificar estrutura e inferência preliminar de RAM. Não gera bitstream nem comprova frequência ou recursos definitivos:

```bash
bash scripts/synth_precheck.sh
bash scripts/synth_precheck.sh --active
# Apenas hierarquia, drivers e memórias:
bash scripts/synth_precheck.sh --structure-only
```

Com Quartus Prime e suporte Cyclone V instalados:

```bash
bash scripts/synth_quartus.sh
# Busca ativa com fetch_demo.hex, o programa padrão de nove palavras:
bash scripts/synth_quartus.sh --active
# Novo programa de validacao desta etapa (17 palavras):
bash scripts/synth_quartus.sh --pbl1
# Somente preparar uma copia revisavel, sem exigir Quartus:
bash scripts/synth_quartus.sh --pbl1 --prepare-only
```

A compilação usa uma cópia em `.build/quartus/`, preservando saídas históricas. `--pbl1` aplica os três parâmetros do programa novo apenas nessa cópia. Verifique recursos, inferência de RAM, clocks, setup/hold e caminhos não restringidos antes de programar a placa.

O projeto inclui `gpu.sdc` com clocks de 20/40 ns. As restrições externas VGA ainda precisam ser confirmadas com a placa e o DAC, conforme o [roteiro de validação física](docs/validacao-fisica-pbl1.md). Os arquivos `.sof` e relatórios antigos do repositório **não validam o RTL desta branch**.

## Registro histórico

A foto abaixo pertence à demonstração da versão original do projeto. Ela preserva o histórico do trabalho dos autores e não comprova a validação física das modificações atuais.

<img width="388" height="217" alt="Demonstração histórica da versão original em monitor VGA" src="https://github.com/user-attachments/assets/1fb03705-2e35-4b36-98c0-8fe2694bb123" />

## Referências

- Terasic, *DE1-SoC User Manual* e esquema da revisão utilizada.
- Intel, *Cyclone V Device Handbook* e documentação de Quartus/TimeQuest.
- Pineda, Juan. *A Parallel Approach to Polygon Rasterization*. SIGGRAPH, 1988.
- Documentos dos Problemas 1 e 2 fornecidos no curso.
