# Validacao fisica e sintese do Problema 1

Os testes RTL podem ser executados sem a placa. A conclusao da entrega do
Problema 1 ainda exige compilacao no Quartus, analise dos relatorios e
demonstracao na DE1-SoC. Este documento prepara essas verificacoes; nao e um
relatorio de hardware aprovado.

## Plataforma e clocks

O projeto `gpu.qsf` seleciona a FPGA Cyclone V `5CSEMA5F31C6`, usada na
DE1-SoC. Registre a revisao real da placa e a versao do Quartus no relatorio
de bancada; esses dados nao podem ser inferidos de uma simulacao.

`gpu.sdc` define `CLOCK_50` com periodo de 20 ns. O registro `clk_25m`
produz um clock dividido por dois, com periodo de 40 ns, encaminhado tambem
para `VGA_CLK`. Os clocks sao relacionados: os caminhos internos de 50 MHz
para 25 MHz continuam sob analise, sem excecao de dominio assincrono.

O video usa 800 periodos por linha e 525 linhas por quadro. Com 25 MHz,
a frequencia e aproximadamente 59,52 Hz. A area ativa e 640x480, ampliando
uma cena logica 320x240 por um fator 2x2.

## Restricoes externas: provisao e limites

A fase inicial de `gpu.sdc` usa delays externos de 0 ns para os sinais
VGA em relacao ao clock encaminhado `VGA_CLK`. Isso permite analisar
esses caminhos, em vez de exclui-los com `set_false_path`. **Zero nao e
uma caracterizacao do DAC nem uma prova conservadora de setup/hold.**
E uma hipotese provisoria de amostragem no pino da FPGA, sem atraso da
placa. Ela deve ser substituida antes de aprovar o timing externo.

Para encerrar essa analise, consulte o manual/esquema da revisao da
DE1-SoC e o datasheet do DAC da placa. Confirme o componente e a borda de
amostragem de RGB, BLANK e SYNC, o caminho dos sinais HS/VS, setup/hold
do receptor, atrasos minimo e maximo das trilhas e diferenca entre as
trilhas de dados e clock. Para um receptor sincrono ao clock encaminhado:

```text
output_delay_max = setup_receptor + atraso_dados_max - atraso_clock_min
output_delay_min = -hold_receptor + atraso_dados_min - atraso_clock_max
```

A borda de referencia deve refletir a amostragem real. Nao use valores
genericos para obter artificialmente slack positivo. Se HS/VS seguirem
um caminho diferente do DAC, use restricoes correspondentes a esse
caminho, sem aplicar automaticamente a caracterizacao do DAC.

Referencia tecnica a confirmar na bancada:
[ADV7123, Analog Devices](https://www.analog.com/media/en/technical-documentation/data-sheets/ADV7123.pdf).
A consulta deste arquivo oficial foi bloqueada pela rede do ambiente;
por isso nenhum valor de setup/hold do componente foi inventado.

Entradas de botoes/chaves nao possuem relacao de fase com `CLOCK_50`.
As excecoes de entrada precisam acompanhar os sincronizadores reais do
RTL, sem excluir caminhos internos entre os seus estagios. LEDs sao
indicadores sem receptor sincrono externo. Revise recovery/removal dos
resets, a liberacao sincronizada e a travessia entre os clocks no
TimeQuest; uma excecao SDC nao implementa um sincronizador.

## Compilar sem substituir resultados antigos

Instale Quartus Prime Lite/Standard com suporte a Cyclone V e coloque
`quartus_sh` no PATH. O projeto historico registra Quartus 25.1; registre
a versao efetivamente usada na nova compilacao.

```bash
cd /caminho/para/PBL2SD
bash scripts/synth_quartus.sh
# Alternativa: usar busca ativa e o programa padrao do top-level.
bash scripts/synth_quartus.sh --active
# Demonstracao dos recursos PBL1 com o programa de 17 palavras:
bash scripts/synth_quartus.sh --pbl1
# Preparar e inspecionar a copia sem precisar de Quartus:
bash scripts/synth_quartus.sh --pbl1 --prepare-only
```

Cada execucao copia RTL, projeto, memorias e SDC para
`.build/quartus/run.XXXXXX` e executa `quartus_sh --flow compile gpu`.
Os diretorios `db/`, `incremental_db/` e `output_files/` antigos ficam
preservados. A selecao de modo afeta apenas o QSF da copia isolada.
`--pbl1` define busca ativa, `PROGRAM_WORDS=17` e
`PROGRAM_FILE="programs/pbl1_validation.hex"` nessa copia. `--active`
mantem o programa padrao do top-level, de nove palavras. A preparacao sem
Quartus valida a copia e os parametros; nao executa sintese ou fitting.

O script retorna 127 quando Quartus esta ausente. Nesse caso nenhum
`.sof`, relatorio de recursos ou resultado de timing novo foi gerado.

## Evidencias necessarias no Quartus

- Conferir se os clocks aparecem com 20/40 ns e se nao existem erros de
  `get_registers`/collections vazias ao ler o SDC.
- Revisar mensagens de sintese, memoria inferida e avisos de largura,
  latches, CDC, multiplos drivers ou inicializacao nao implementada.
- Arquivar utilizacao de ALMs, registradores, blocos M10K, bits de RAM,
  multiplicadores/DSP e PLLs.
- Arquivar setup, hold, recovery/removal, minimum pulse width, Fmax e
  lista de caminhos nao restringidos; justificar cada excecao.
- Aprovar os clocks de 50/25 MHz e as interfaces externas com restricoes
  verificadas. Relatorios antigos nao aprovam o RTL desta branch.
- Programar exclusivamente o `.sof` produzido pela compilacao revisada.

Verifique se as memorias cabem na FPGA. O double buffer de poligonos,
as copias de memoria exigidas pelos sprites e a logica de arbitragem
podem consumir recursos relevantes. Se o fitting nao couber ou o timing
falhar, a etapa permanece aberta e requer ajuste antes da demonstracao.

## Roteiro de bancada

1. Programar a placa, conectar monitor VGA e conferir reset e imagem
   estavel. Anotar revisao da placa, ferramenta e hash do commit.
2. Demonstrar background, alteracao de tile e scroll nos dois eixos,
   incluindo repeticao nas bordas.
3. Demonstrar sprites com indices diferentes, prioridade, sobreposicao,
   transparencia, espelhamentos e selecao de paleta.
4. Demonstrar triangulo e retangulo preenchidos, transparencias e
   prioridade entre as tres camadas.
5. Demonstrar limpeza e troca de buffers sem quadro parcialmente
   desenhado; conferir que a apresentacao ocorre no evento de quadro.
6. Repetir reset durante atividade e comandos invalidos, confirmando
   que o VGA permanece sincronizado.
7. Executar os casos selecionados pelo tutor e registrar resultados,
   limitacoes e eventuais falhas, sem substituir a demonstracao por video
   ou simulacao.

## Ferramentas disponiveis no ambiente de simulacao

Em `/workspace/.pbl-tools`, o APT Debian 13 baixou pacotes assinados de
Icarus Verilog 12.0 e Yosys 0.52. Os pacotes foram extraidos localmente,
sem `sudo` nem alteracao do sistema. Verilator continua disponivel.

```bash
source /workspace/.pbl-tools/activate.sh
iverilog -V
yosys -V
```

O wrapper local de `iverilog` informa seu diretorio de backend via
`-B /workspace/.pbl-tools/root/usr/lib/x86_64-linux-gnu/ivl`.
Yosys pode realizar verificacoes estruturais e de inferencia de RAM;
isso nao produz o `.sof` nem substitui o fitter/TimeQuest do Quartus.

## Precheck estrutural e de memoria

```bash
source /workspace/.pbl-tools/activate.sh
bash scripts/synth_precheck.sh
bash scripts/synth_precheck.sh --active
# Verificacao mais rapida, sem mapeamento de tecnologia:
bash scripts/synth_precheck.sh --structure-only
```

O script verifica hierarquia, multiplos drivers e sinais sem origem via
`check -assert`, coleta memorias e realiza mapeamento preliminar Cyclone V
com Yosys. Os resultados ficam em `.build/synth/run.XXXXXX`, incluindo a
versao da ferramenta, netlists JSON e logs de cada fase.

Antes de expandir memorias em flip-flops, o script confere o mapeamento
para blocos de RAM. Se restar uma memoria maior que 8.192 bits ou mais
de 65.536 bits somados, interrompe e lista as memorias problematicas.
Esses limites protegem a verificacao contra uma sintese acidentalmente
enorme; nao representam a capacidade da FPGA. Memorias pequenas, como
tabelas de atributos, podem ser implementadas em registradores.

Uma passagem neste precheck indica consistencia estrutural e compatibilidade
preliminar com o mapeador do Yosys. Recursos definitivos, empacotamento de
ALMs, capacidade ocupada de M10K, Fmax e timing devem vir do Quartus.

### Resultado preliminar medido nesta etapa

Yosys 0.52 concluiu as fases estruturais e o mapeamento Cyclone V nos dois
modos. `check -assert` reportou zero problemas tanto antes quanto depois
do mapeamento. Os framebuffers foram ajustados para leitura sincrona sem
reset no bloco de RAM; a mascara de validade permanece no controle. Isso
permitiu mapear ambos os bancos em M10K, sem expansao em flip-flops.

| Recurso do netlist Yosys final | Demonstracao da placa | Busca ativa |
|---|---:|---:|
| Celulas `MISTRAL_M10K` | 219 | 219 |
| Celulas `MISTRAL_FF` | 1.971 | 1.952 |
| Celulas LUT de 2 a 6 entradas | 2.570 | 2.572 |
| Celulas `MISTRAL_ALUT_ARITH` | 2.876 | 2.773 |
| Celulas `MISTRAL_MUL27X27` | 8 | 8 |

Nos dois modos, a distribuicao final dos M10K e: 152 nos dois bancos de
poligonos, 48 no motor de sprites (32 caches e ROM de origem), 16 nos
padroes do background, dois no tilemap e um na paleta. A memoria pequena
do programa de busca ativa foi implementada em logica.

Antes da otimizacao final foram contabilizados 235 M10K; o valor final de
219 vem de `mapped.json`/`mapped-summary.txt`. Esses numeros sao unidades
do netlist preliminar Yosys. LUTs e celulas aritmeticas **nao devem ser
somadas ou convertidas diretamente em ALMs**; empacotamento, blocos DSP
fisicos, colocacao e roteamento podem resultar em uso diferente no Quartus.

O relatorio historico `output_files/gpu.fit.rpt` informa capacidade de
397 M10K para o dispositivo selecionado. Comparada a essa capacidade, a
contagem preliminar de 219 e viavel em quantidade de blocos, mas nao prova
que o fitter final passara nem que os clocks terao timing adequado.
Os relatorios historicos continuam pertencendo ao RTL anterior.

Logs da medicao no ambiente: `.build/synth/run.bClI6F` (demonstracao) e
`.build/synth/run.Hio2ri` (busca ativa). Gere novas medicoes com o script
ao alterar o RTL. Nenhum Fmax, slack ou teste na placa foi validado aqui.
