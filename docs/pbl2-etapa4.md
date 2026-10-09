# Etapa 4 — arquitetura programável e demonstração de recursos

Branch: `pbl2/etapa4-arquitetura-demonstracao`, baseada no commit `57516dd` de `pbl2/etapa3-conclusao-pbl1`. A `main` permanece preservada.

O objetivo é completar os componentes programáveis do Problema 2 e tornar os recursos gráficos acessíveis na bancada. A aplicação padrão passa a ser uma galeria interativa de oito telas. A demonstração anterior por botões continua disponível no modo legado.

Esta análise usa os requisitos dos enunciados PBL01/PBL02 e a opção de busca ativa com memória interna.

## Requisitos do Problema 2

| Requisito | Implementação | Situação |
|---|---|---|
| ISA de 32 bits | [Contrato da ISA](pbl2-isa.md) e assembler Python; comandos gráficos preservados e novas instruções de cálculo/controle. | Implementado e validado nos testes novos. |
| Busca e IR | `instruction_memory`, PC e IR em `gpu_program_core`. | Implementado e validado nos testes novos. |
| Unidade de controle | Estados de busca, execução, emissão, conclusão, espera de quadro e parada em `gpu_program_core`. | Implementado e validado nos testes novos. |
| Banco de registradores | `gpu_register_file`, 16×32 bits; R0 é zero, R1–R15 resetados. | Implementado e validado nos testes novos. |
| ULA geral | `gpu_alu`: aritmética, lógica, deslocamentos, comparação e flags Z/N/C/V. | Implementado e validado nos testes novos. |
| Datapath | Operandos, imediatos, entrada, status, resultado da ULA e comandos calculados em `gpu_program_core`. | Implementado e validado nos testes novos. |
| Registrador de status | `gpu_status_register`, flags/erro registrados e estados observáveis. | Implementado e validado nos testes novos. |
| Sincronização VGA e quadro | WAIT_FRAME, `gpu_frame_control` e PRESENT no intervalo vertical. | Validado em simulação; comprovação física pendente. |
| Motores como unidades funcionais | Decoder ready/valid e espera de background, sprites e polígonos. | Integração e regressões validadas em simulação. |
| Compositor/quadro/VGA contínuos | Vídeo independente do avanço de PC, inclusive em espera e HALT. | Validado em simulação; demonstração física pendente. |
| Busca ativa com programa interno | `programs/showcase.hex` na memória de instruções. | Implementado. |
| Assembly da ISA da equipe | `programs/showcase.asm`, com cálculos, condições, laços e comandos gráficos. | Codificação e execução validadas. |
| Testes por módulo e integração | `scripts/test_step4.sh` e regressões da etapa 3. | Suíte completa aprovada: 25 bancadas RTL e 11 testes Python. |
| Projeto Quartus/reprodução | QPF/QSF/SDC, programas, assets e scripts. | Preparado; compilação final pendente neste ambiente. |
| Recursos/Fmax/timing | Scripts de pré-síntese/compilação e análise física. | Relatórios definitivos pendentes. |
| DE1-SoC e testes do tutor | Galeria e [roteiro de bancada](demonstracao-na-placa.md). | Preparado; execução física pendente. |

A entrega mínima só fica comprovada com testes, compilação/avaliação de timing e demonstração obrigatória da versão atual na placa.

## Execução, datapath e status

A memória usa endereços em palavras. A busca captura a instrução em IR e o controle seleciona operandos/operação. Instruções internas escrevem registradores/flags ou alteram PC. Instruções gráficas entregam comandos ao decoder e aguardam aceitação/conclusão. WAIT_FRAME aguarda um evento posterior à entrada no estado de espera, sem reiniciar os contadores VGA. HALT mantém PC/IR e vídeo.

CMD envia um comando construído em um registrador. O decoder gráfico valida a palavra; não a reinterpreta como instrução da CPU. Assim, ULA e registradores produzem movimentos e atualizações no mesmo formato gráfico da etapa 3. O controle segura PC/IR e comandos enquanto os motores estiverem ocupados e protege o início registrado antes de consultar busy.

Saltos são absolutos e usam índices de instruções. Destinos fora do programa e instruções inválidas acumulam erro e avançam sem efeitos gráficos ou escrita indevida. R0 é zero; a aritmética usa complemento de dois, módulo 2³². ADD/SUB e operações lógicas/deslocamentos atualizam flags. C na subtração significa ausência de empréstimo; BLT/BGE usam N XOR V.

Status reúne Z, N, C, V, ERROR, HALTED, GRAPHICS_BUSY, WAITING_FRAME, BUFFER_INITIALIZED, FRONT_BUFFER, DOUBLE_BUFFERED e CMD_READY. STATUS captura essa palavra; CLRE limpa erro acumulado. Um novo erro tem precedência na mesma borda. IN lê chaves, botões ou contador de quadros; OUT fornece diagnóstico do programa. Entradas físicas são sincronizadas e botões filtrados.

## Programa e compatibilidade

A galeria é padrão do top-level, inclusive pela interface do Quartus. Usa `assets/showcase_tiles.hex`, `assets/showcase_palette.hex`, `assets/showcase_tilemap.hex` e o programa `programs/showcase.asm`/`.hex`, de 2.626 palavras. Os parâmetros padrão são `USE_PROGRAMMABLE_CORE=1`, `SHOWCASE=1`, `PROGRAM_WORDS=2626` e `PROGRAM_FILE="programs/showcase.hex"`.

| Tela | Recursos |
|---|---|
| 0 | Scroll X/Y, repetição e escrita no tilemap. |
| 1 | Posição, imagem e enable dos 32 sprites. |
| 2 | Flips H, V e H+V. |
| 3 | Transparência entre sprites e prioridades 0–3. |
| 4 | CLUT programável e bancos de paleta. |
| 5 | Triângulo, retângulo por dois triângulos e recorte. |
| 6 | Buffer oculto e apresentação no intervalo vertical. |
| 7 | STATUS, comando inválido, erro acumulado e CLRE. |

O programa usa cabeçalhos/símbolos próprios e não depende do Flappy Bird. As entradas são consultadas pela ISA, sem caminho direto aos motores.

O caminho de vídeo e os motores da etapa 3 continuam responsáveis pelos pixels. O novo núcleo produz comandos; opcodes antes livres 2, 4 e E passam a fornecer cálculos, comandos por registrador e fluxo/quadro. F0000000 continua HALT. `gpu_alu` é geral; `raster_alu` continua especializada no desenho.

Os modos antigos usam memórias históricas e permanecem testados. Na cópia isolada do Quartus, `--legacy` seleciona botões, `--active` o programa de nove palavras, `--pbl1` o de 17 palavras. Padrão, `--showcase` e `--pbl2` selecionam galeria.

Não há busca passiva, ponte HPS/MMIO, driver ARM ou programa C. A busca ativa é permitida pelo enunciado; essas integrações ficam para etapas posteriores. Copiar o compilado por SSH não programa a FPGA.

## Testes reproduzíveis

```bash
cd /caminho/para/PBL2SD
bash scripts/test_step4.sh
# Conjunto da arquitetura, sem a galeria e a regressão completa:
bash scripts/test_step4.sh --cpu-only
# Conjunto da galeria:
bash scripts/test_step4.sh --gallery-only
```

Dependências: Python 3, Verilator 5, Icarus Verilog, Make e compilador C++. O script completo reúne 25 testbenches distintos: oito novos e 17 regressões da etapa 3. Inclui 11 testes Python do assembler; os quatro módulos de CPU também são verificados com Icarus em quatro estados. A bancada de inicialização é executada nos modos legado e programável com as memórias da galeria. Logs/executáveis ficam em `.build/`; erro/timeout retorna código diferente de zero.

`--cpu-only` executa os seis novos testes de banco, ULA, quadro, núcleo, entradas e GPU integrada, com as quatro repetições Icarus e a inicialização do top-level programável em quatro estados. `--gallery-only` executa os dois testes de comandos e vídeo da galeria. Ambos mantêm os testes Python e as conferências Assembly/HEX/assets. Os logs novos ficam em `.build/step4/`.

Cobertura nova: formatos/labels/imediatos e rejeição de Assembly inválido; R0/reset; operações/flags; PC/IR, saltos e espera de quadro; comandos por registrador; erros/status; controles e recursos das oito telas. A regressão cobre o comportamento gráfico do checkpoint anterior.

### Resultados medidos dos testes novos

| Teste | Resultado observado |
|---|---|
| `tests/test_assembler.py` | 11 testes passaram; formatos, expansão/labels e rejeição de entradas inválidas. |
| `tb_gpu_register_file` / `tb_gpu_alu` / `tb_gpu_program_core` / `tb_gpu_frame_control` | Passaram com Verilator e Icarus: banco, ULA, controle/datapath/status e contador de quadros. |
| `tb_showcase_inputs` | Passou: sincronização das chaves, polaridade dos botões, filtro de pressão/soltura e reset. |
| `tb_programmable_gpu` | Passou com Assembly de 54 palavras: saída `12345678`, dois comandos, scroll `(10,20)`, CLUT255 `F80000`, espera de quadro e vídeo após HALT. |
| `tb_showcase_commands` | Passou no top-level: 23.809 comandos, 53 apresentações, oito telas, 40 fases e controles. O evento de quadro foi acelerado para um a cada 2.048 clocks. |
| `tb_showcase_video` | Passou nas oito telas: 6.720.000 ciclos de RGB/sincronismo simulados com a temporização de 50/25 MHz. Capturas em `.build/showcase/painel0.ppm` até `painel7.ppm`. |
| `tb_initialization`, modos legado/programável | Passou em Icarus nos dois modos: dois resets e 156.000 ciclos por modo sem sinais indefinidos nos pinos/controle, com os dois buffers inicializados. |

O teste de comandos acelera quadros para cobrir interações sem esperar tempo de bancada. O teste de vídeo usa a temporização VGA do projeto e compara os pinos com uma referência da cena. As capturas ajudam a observar o resultado da simulação; não são fotos de hardware.

A execução conjunta passou com código de saída zero: 25 bancadas RTL distintas, incluindo as 17 regressões anteriores, e 11 testes Python. Os quatro testes da CPU foram repetidos no Icarus, além da inicialização do top-level nos modos legado e programável. A execução final durou aproximadamente 4 min 56 s neste ambiente; log em `.build/step4-suite-final.log`. Os checks confirmaram a reprodução de ambos os programas e dos assets. Não há resultado novo de hardware neste documento.

## Síntese, desempenho e pendências externas

```bash
# Preparar fontes, programa e memórias, sem exigir Quartus:
bash scripts/synth_quartus.sh --prepare-only
# Com Quartus e suporte Cyclone V instalados:
bash scripts/synth_quartus.sh
```

O script prepara uma cópia em `.build/quartus/run.XXXXXX`. `--prepare-only` não gera bitstream nem executa síntese/fitting. Pela interface, abra `gpu.qpf`, compile e grave `output_files/gpu.sof`. O [guia de placa](demonstracao-na-placa.md) detalha execução e evidências. O dispositivo é `5CSEMA5F31C6`; revisão real e versão Quartus da bancada devem ser informadas.

O preparo da cópia passou para todos os modos: fontes, parâmetros, Assembly/HEX e assets coerentes. Sem Quartus, a compilação retorna 127 e informa que nenhum `.sof` foi produzido.

A pré-síntese Yosys concluiu o mapeamento preliminar Cyclone V com zero problemas em `check -assert`, antes e depois do mapeamento. O resultado final da galeria foi 226 M10K, 2.582 FF, 4.015 LUTs de 2–6 entradas, 2.981 células aritméticas e 8 `MISTRAL_MUL27X27`. Os M10K se distribuem em 152 nos polígonos, 46 nos sprites, 14 nos padrões, 11 no programa, dois no tilemap e um na paleta. Esses valores não são ALMs nem recursos físicos definitivos do Quartus.

Veja detalhes, logs e limites em [validação física da etapa 4](validacao-fisica-pbl2.md). Relatórios da etapa 3 são históricos e não incluem a CPU/galeria atuais. Obtenha novos valores de ALMs, registradores, M10K/RAM, DSP/PLL, Fmax, slack e caminhos não restringidos. O SDC define clocks relacionados de 50/25 MHz; atrasos VGA externos permanecem provisórios até caracterização.

### Desempenho e gargalos do RTL

Os tempos abaixo são calculados para os clocks nominais do projeto. Não são medidas de Fmax nem resultados físicos do Quartus.

| Operação | Custo no RTL / consequência |
|---|---|
| Cálculo, leitura de entrada/status e salto | Três clocks de 50 MHz: busca, captura do IR e execução; 60 ns sem espera. |
| Comando gráfico | Pelo menos seis clocks, incluindo emissão e proteção do start; busy e espera de apresentação aumentam esse custo. |
| Inicialização dos buffers | 76.800 clocks para limpar os dois bancos em paralelo, cerca de 1,536 ms. |
| Troca de imagem de sprite | 256 leituras mais pipeline, cerca de 5,1 µs; posição e estilo não recarregam a imagem. |
| Quadro VGA | 800×525 períodos de 25 MHz: 16,8 ms, aproximadamente 59,52 Hz. |

O núcleo executa uma instrução por vez e aguarda o motor ocupado antes do próximo comando. Rasterização e limpeza custam conforme a área percorrida; PRESENT e WAIT_FRAME podem dominar a duração da atualização. A tela 6 usa duas esperas de quadro por iteração, limitando sua animação a aproximadamente 29,76 atualizações/s. O vídeo continua independente dessas esperas.

A seleção entre 32 sprites, a ULA geral e as multiplicações das arestas são caminhos que precisam de avaliação no TimeQuest. A maior parcela de memória está nos dois buffers de polígonos. Possíveis etapas posteriores incluem diminuir esse custo, separar filas dos motores ou preparar atualizações atômicas das demais camadas, depois de medir o circuito atual.

Sprite/tilemap/CLUT têm atualização direta; somente polígonos têm buffer duplo. Esperar quadros organiza a animação, mas não torna todas as camadas atômicas.
