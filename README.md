# Coprocessador gráfico 2D — PBL2SD

Projeto em Verilog para a DE1-SoC, desenvolvido por **Lucca Coutinho, Mailson Alves e Ramon Santos**, do curso de Engenharia de Computação da Universidade Estadual de Feira de Santana (UEFS).

A branch atual, `pbl2/etapa5-correcao-memorias-quartus`, continua a partir da etapa 4 e corrige o carregamento dos arquivos gráficos no Quartus. O [relatório da correção](docs/pbl2-etapa5.md) registra os avisos encontrados na compilação da placa e a alteração. A arquitetura programável do Problema 2 e a **galeria interativa de oito telas** são preservadas. A `main` permanece intacta.

O programa da galeria é escrito em Assembly da ISA do projeto e armazenado na memória interna. Registradores, ULA, saltos e sincronização de quadros controlam a demonstração. **A compilação no Quartus, os relatórios de timing e a validação desta versão na DE1-SoC ainda precisam ser registrados.** A simulação não substitui essa etapa.

## Começar na placa

1. Abra **`gpu.qpf` desta branch** no Quartus, mantendo todas as pastas do projeto. O modo padrão agora é a galeria; não precisa editar parâmetros para selecioná-la.
2. Execute **Processing → Start Compilation**. Isso produz `output_files/gpu.sof` no computador.
3. Abra **Tools → Programmer**, selecione USB-Blaster em **Hardware Setup**, adicione esse `.sof`, marque **Program/Configure** e clique em **Start**.
4. Depois de gravar, conecte o monitor VGA e pressione e solte **KEY0**. O programa inicia sozinho na FPGA.

**Compilar produz o arquivo; gravar faz a FPGA executar o circuito novo.** O `.sof` não é um programa Linux: copiar o arquivo por SSH não muda a configuração da FPGA. Esta branch usa busca ativa e não inclui uma ponte HPS ou um carregador pelo Linux da placa.

| Controle | Função na galeria |
|---|---|
| `SW[2:0]` | Seleciona a tela de 0 a 7 no modo manual. |
| `SW[9]=0` | Modo manual. |
| `SW[9]=1` | Modo automático: percorre as telas. |
| `SW[8]=1` | Pausa a animação. |
| `KEY1` | Avança um passo quando pausado. |
| `KEY2` | Solicita a próxima tela no modo automático. |
| `KEY3` | Reinicia a animação da tela. |
| `KEY0` | Reinicia o circuito e o programa. |

As telas demonstram background/scroll X/Y; os 32 sprites; flips H/V; transparência/prioridades; paleta/bancos; triângulos/retângulos/recorte; buffer duplo; e status/erros. O [guia para demonstrar na placa](docs/demonstracao-na-placa.md) explica o que observar em cada uma.

![Oito telas da galeria capturadas na simulação](docs/galeria-simulada.png)

Esta imagem reúne **capturas da simulação**, obtidas dos pinos RGB/VGA pelo `tb_showcase_video`, com animação pausada na fase 0. Não é uma foto da FPGA. As imagens individuais ficam em `.build/showcase/painel0.ppm` até `painel7.ppm`.

## Arquitetura

```text
Memória de instruções → busca/PC/IR → controle → registradores ↔ ULA geral
                                         ↓                     ↓
                                  comandos imediatos ou calculados
                                         ↓
                         decoder → background / sprites / polígonos
                                                    ↓
VGA e controle de quadro contínuos → compositor → paleta → RGB e sincronismo
```

O processador executa instruções de 32 bits com busca ativa. Há 16 registradores de 32 bits, com R0 fixo em zero, flags Z/N/C/V, status dos motores e erro acumulado. `WAIT_FRAME` aguarda um novo intervalo vertical; saltos e condições permitem laços. `CMD` envia um comando montado em um registrador ao decoder gráfico. O núcleo mantém comandos estáveis até a aceitação e aguarda operações ocupadas, sem interromper a varredura VGA.

| Módulo | Responsabilidade |
|---|---|
| `gpu_de1_soc_top` | Integração, origem de comandos, entradas da placa, reset, clocks, alinhamento e pinos. |
| `instruction_memory` / `gpu_program_core` | Memória interna, busca, PC/IR, controle, datapath e execução do programa. |
| `gpu_register_file` / `gpu_alu` | Banco de 16×32 bits e operações gerais com operandos de registradores/imediatos. |
| `gpu_status_register` / `gpu_frame_control` | Flags/erro registrados, estados observáveis e contador de quadros independente. |
| `cmd_decoder` | Validação e envio aos motores; comando inválido gera erro sem alterar a cena. |
| `vga_sync` | Coordenadas, área visível, sincronismo e início do intervalo vertical. |
| `bg_engine` / `tilemap_ram` / `pattern_vram` | Mapa 40×30 de tiles 8×8, 256 padrões, atualização de células e scroll X/Y. |
| `sprite_engine` | 32 sprites 16×16, posição, imagem, enable, flips, prioridade, transparência e banco de paleta. |
| `polygon_rasterizer` / `raster_alu` | Rasterização inteira de triângulos; retângulos por dois triângulos. |
| `polygon_buffer` | Inicialização e dois buffers de polígonos, com apresentação no intervalo vertical. |
| `compositor` / `color_palette` | Prioridade sprite → polígono → background e CLUT de 256 cores RGB. |

`gpu_alu` é a ULA geral das instruções; `raster_alu` calcula arestas de polígonos. Essa separação preserva o motor gráfico e torna os cálculos do programa independentes da rasterização.

O clock de entrada é 50 MHz; o VGA usa 25 MHz, 800 períodos por linha e 525 linhas por quadro, aproximadamente **59,52 Hz**. A cena lógica 320×240 é ampliada em 2×2 para 640×480. Quadro, compositor e VGA continuam ativos durante espera, desenho e `HALT`.

## Requisitos e decisões

| Requisito | Implementação / decisão | Evidência necessária |
|---|---|---|
| ISA de 32 bits e Assembly da equipe | [ISA documentada](docs/pbl2-isa.md), assembler Python e `programs/showcase.asm`. | Codificação e execução do programa. |
| Busca, IR, controle, datapath e banco | Memória interna, núcleo programável, R0–R15 e ULA geral. | Testes por módulo e integração. |
| Registrador de status | Flags, erro acumulado e estado dos motores/quadros. | Operações aritméticas, erros e esperas. |
| Sincronização com VGA | `WAIT_FRAME`, contador de quadros e apresentação de polígonos no intervalo vertical. | Simulação e demonstração física. |
| Background, sprites, polígonos, compositor e VGA | Motores da etapa 3 preservados e controlados pela ISA. | Regressões e galeria na placa. |
| Inicialização definida e comunicação valid/busy | Reset de controles, validade dos caches, limpeza de buffers e espera por conclusão. | Simulação em quatro estados e testes de espera. |
| Projeto reproduzível | QPF/QSF/SDC, arquivos HEX, programas, scripts e documentação. | Compilação Quartus com fontes atuais. |
| Recursos, Fmax e timing | Scripts de pré-síntese/compilação e clocks de 20/40 ns no SDC. | Relatórios novos do Quartus/TimeQuest. |
| Demonstração obrigatória na DE1-SoC | Galeria e roteiro de observação. | Execução na placa e casos do tutor. |

A busca ativa permite trabalhar sem driver ARM, fila MMIO ou aplicação C nesta entrega. As operações demonstradas são consequências de instruções da ISA. As entradas físicas são lidas pelo programa; não acionam diretamente os motores.

## Assembly e testes no Linux

Use Python 3, Verilator 5, Icarus Verilog, Make e compilador C++ no `PATH`. Os testes dispensam placa e SDL. No Ubuntu/Debian:

```bash
sudo apt update
sudo apt install python3 verilator iverilog make g++
```

Na pasta desta branch:

```bash
bash scripts/test_step4.sh
# Somente o conjunto da arquitetura programável:
bash scripts/test_step4.sh --cpu-only
# Somente a galeria, comandos e vídeo:
bash scripts/test_step4.sh --gallery-only
```

O conjunto completo reúne 25 testbenches RTL distintos, incluindo as 17 regressões da etapa 3, e 11 testes Python do assembler. Quatro testes da CPU também executam com Icarus em quatro estados; a inicialização do top-level é verificada nos modos legado e programável. Cada teste concluído imprime `PASS`; erro ou timeout retorna código diferente de zero. Logs/executáveis ficam em `.build/`. O [relatório da etapa 4](docs/pbl2-etapa4.md) registra cobertura e resultados medidos.

A suíte completa passou: 25 testbenches RTL e 11 testes do assembler, incluindo as regressões e as verificações em quatro estados. A integração da galeria verificou comandos/controles nas oito telas e comparou RGB/sincronismo em 6.720.000 ciclos simulados com a temporização VGA do projeto. Isso prepara a demonstração física, que continua pendente.

`programs/showcase.asm` é a fonte do programa; `programs/showcase.hex` é o executável da memória interna. A [especificação da ISA](docs/pbl2-isa.md) define formatos, flags, labels e pseudoinstruções gráficas. Para gerar ou conferir o executável e as memórias gráficas:

```bash
python3 scripts/assemble.py programs/showcase.asm
python3 scripts/assemble.py programs/showcase.asm --check
python3 scripts/generate_showcase_assets.py --check
```

Ao alterar o Assembly, gere novamente o `.hex`; se o tamanho mudar, atualize `PROGRAM_WORDS` antes de compilar pela interface do Quartus. O script de compilação calcula esse tamanho automaticamente na cópia isolada.

Neste ambiente em nuvem, ative as ferramentas locais com:

```bash
source /workspace/.pbl-tools/activate.sh
```

## Compilar e escolher outros modos

O projeto aberto pela interface do Quartus usa a galeria como padrão. Pelo terminal, com Quartus e suporte Cyclone V instalados:

```bash
# Galeria atual: padrão; --showcase ou --pbl2 também selecionam este modo.
bash scripts/synth_quartus.sh
# Preparar a cópia e conferir arquivos, sem compilar:
bash scripts/synth_quartus.sh --prepare-only
# Demonstração histórica por botões:
bash scripts/synth_quartus.sh --legacy
# Busca ativa antiga, com nove palavras:
bash scripts/synth_quartus.sh --active
# Validação gráfica da etapa 3, com 17 palavras:
bash scripts/synth_quartus.sh --pbl1
```

O script compila uma cópia em `.build/quartus/run.XXXXXX`. Use o `.sof` de `output_files/` **dessa cópia**, indicado no terminal. Ao compilar pela interface diretamente na pasta do projeto, use o `.sof` recém-gerado em `output_files/`. Arquivos/relatórios históricos do repositório não comprovam esta versão.

O [guia de bancada](docs/demonstracao-na-placa.md) orienta gravação, controles e evidências. A [validação física da etapa 4](docs/validacao-fisica-pbl2.md) apresenta a pré-síntese e as evidências necessárias do Quartus. As restrições VGA ainda são provisórias: confirme-as com DAC e revisão da placa antes de aprovar timing externo.

## Limitações e entrega física

- O buffer duplo cobre polígonos. SAT, tilemap e CLUT recebem alterações diretas; não há atualização atômica de todas as camadas.
- Trocar a imagem de um sprite exige 256 leituras para seu cache, com latência de pipeline. Isso limita trocas de imagens, mas o VGA continua ativo.
- Não há ponte HPS/ARM ou driver Linux. Para mudar o programa na FPGA, compile e grave uma nova configuração.
- Uma gravação `.sof` é volátil: normalmente se perde ao desligar a placa.
- A pré-síntese Yosys da galeria passou nas verificações estruturais e no mapeamento preliminar Cyclone V, com 226 M10K. Ela não gera `.sof`, Fmax nem aprovação de timing. Recursos definitivos dependem de síntese, fitting e TimeQuest no Quartus.
- Registre a revisão física da DE1-SoC e a versão do Quartus da bancada. O dispositivo selecionado é Cyclone V `5CSEMA5F31C6`.

Os guias das [etapas 1](docs/pbl2-etapa1.md), [2](docs/pbl2-etapa2.md) e [3](docs/pbl1-etapa3.md) descrevem checkpoints anteriores. Seus resultados pertencem àquelas versões. O [relatório atual](docs/pbl2-etapa4.md) distingue implementação, simulação e pendências externas.

## Registro histórico

A foto abaixo pertence à versão original. Ela preserva o histórico dos autores e não comprova validação física das modificações atuais.

<img width="388" height="217" alt="Demonstração histórica da versão original em monitor VGA" src="https://github.com/user-attachments/assets/1fb03705-2e35-4b36-98c0-8fe2694bb123" />

## Referências

- Documentos dos Problemas 1 e 2 fornecidos no curso.
- Terasic, *DE1-SoC User Manual* e esquema da revisão utilizada.
- Intel, *Cyclone V Device Handbook* e documentação Quartus/TimeQuest.
- Pineda, Juan. *A Parallel Approach to Polygon Rasterization*. SIGGRAPH, 1988.
