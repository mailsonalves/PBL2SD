# Validação do coprocessador PBL2

Esta validação é de RTL em software. A base é o commit `57516dd` da branch
selecionada `pbl2/etapa3-conclusao-pbl1`; os motores gráficos existentes foram
preservados. Os testes não substituem Quartus, TimeQuest ou a demonstração na
DE1-SoC exigidos pelos enunciados.

## Reprodução

Ferramentas utilizadas: Verilator 5.032, Icarus Verilog 12.0, Yosys 0.52,
compilador C++, Make e Python 3. No ambiente preparado:

```bash
cd /workspace/PBL2SD
source /workspace/.pbl-tools/activate.sh
bash scripts/test_pbl2.sh
bash scripts/synth_precheck.sh
bash scripts/synth_precheck.sh --board
bash scripts/synth_quartus.sh --prepare-only
bash scripts/synth_quartus.sh --program programs/polygons_motion.hex --prepare-only
```

Em outra máquina, instale as ferramentas e execute os mesmos scripts a partir
da raiz do checkout; a ativação em `/workspace` é específica deste ambiente.
Os scripts propagam erros de montagem, compilação e execução. Resultados ficam
em `.build/`, caminho ignorado pelo Git. A montagem na suíte escreve cópias em
`.build/pbl2/` e compara com os HEX versionados, sem sobrescrever programas.

## Resultados observados

A execução completa de `scripts/test_pbl2.sh` terminou com código **0**.
Foram executados 12 testes Python e 22 testbenches RTL distintos: cinco novos
para o PBL2 e os 17 existentes do PBL1. Os testes de unidades CPU, controle CPU
e MMIO foram executados com ambos Verilator e Icarus; o teste de inicialização
VGA usa Icarus. Nenhum desses alvos foi omitido ou desabilitado.

| Alvo | Evidência e resultado |
|---|---|
| Montador, 12 testes | Encodings de referência, labels, limites, instruções inválidas, pseudo-instruções, erros com linha e reprodução dos dois HEX; PASS. |
| `tb_gpu_cpu_units` | ULA com 600 vetores ADD/SUB/CMP e limites de carry/overflow; três portas de leitura do banco, r0, reset/restart, gráficos por registradores e campos reservados; PASS nos dois simuladores. |
| `tb_gpu_cpu_control` | Programa com operações da ULA, desvios tomados/não tomados, STATUS, inválidas sem efeitos, espera de quadro, pausa, erro simultâneo a clear e drenagem no restart; PASS nos dois simuladores. |
| `tb_gpu_mmio` | 64 offsets, desalinhamento, registros RO, byteenables, pulsos de controle, contador e reset; PASS nos dois simuladores. |
| `tb_pbl2_programs`, background | Quatro esperas reais de quadro, 46 comandos gráficos, posição de sprites e scroll calculados pela ULA; mapas, paleta, SAT e um quadro VGA completo com referência independente; PASS. |
| `tb_pbl2_programs`, polígonos | Quatro esperas e quatro apresentações, 71 comandos gráficos, triângulo e sprite móveis, retângulo preenchido; framebuffer e um quadro VGA completo com referência independente; PASS. |
| `tb_pbl2_control` | MMIO integrado com CPU/VGA/motores reais; restart durante CLEAR, pausa atravessando quadro, PC/IR/status e retomada; restart durante PRESENT pendente, sem perder a troca; PASS. |
| 17 regressões PBL1 | Background, memórias/paleta/compositor, rasterização, buffers, 32 sprites/flips/alpha/prioridade, botões, VGA, busca ativa, comandos inválidos e inicialização em quatro estados; PASS. |

Cada demonstração é verificada por um modelo de geometria e composição separado
do RTL. Após HALT, o teste compara RGB em 840.000 ciclos de 50 MHz, além das
contagens do quadro, sincronismo e área visível. Os recursos HEX de tiles e
paleta são entradas do modelo; os pixels/caches produzidos pelo RTL não são
usados como resultado esperado.

O programa histórico `pbl1_validation.hex` usava `20000000` como comando inválido.
O opcode 2 agora pertence à ULA; essa palavra passou a significar `MOVI r0,0`.
Somente a palavra de diagnóstico foi migrada para `F0000001`, preservando um
erro deliberado, os 16 comandos gráficos aceitos e a cena histórica. O HALT
canônico continua sendo `F0000000`.

## Pré-síntese e hardware

Yosys concluiu estrutura, hierarquia, drivers, inferência de memória e mapeamento
preliminar Cyclone V em ambos os modos, com o programa padrão
`background_sprites.hex` no modo de busca ativa:

| Modo | M10K no modelo Yosys | Observação |
|---|---:|---|
| Busca ativa PBL2 | 220 | 219 dos motores + 1 da ROM de instruções; 2.419 primitivas `MISTRAL_FF` na execução registrada. |
| Demonstração histórica por botões | 219 | CPU e interface MMIO sem conexão ao HPS são removidas da lógica útil pela síntese. |

Essas contagens não são uma estimativa definitiva de ALMs do fitter, ocupação
final ou Fmax. Não há relatório de timing aprovado nem bitstream novo.
O wrapper de placa deixa MMIO desconectado; a verificação MMIO é do núcleo e
está descrita em [hps-mmio.md](hps-mmio.md).

A preparação isolada do projeto Quartus passou para os dois programas PBL2,
para `--active` (programa histórico de nove palavras) e para `--pbl1`.
A cópia inclui os novos módulos, memórias, QSF e SDC. O script valida o tamanho
do HEX antes de compilar para evitar memória de instruções parcialmente vazia.

Ainda necessários fora deste ambiente: Quartus Prime com Cyclone V, revisão de
restrições externas VGA, fitting/recursos, Fmax/setup/hold/caminhos não
restringidos, programação da placa e testes do tutor. A revisão física da PCB
não foi informada; o alvo configurado é `5CSEMA5F31C6`. A ponte HPS precisa ser
integrada em Platform Designer e verificada em hardware antes de afirmar
comunicação ARM-FPGA funcional.
