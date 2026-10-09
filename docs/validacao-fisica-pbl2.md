# Validacao fisica do Problema 2

A galeria programavel substitui a dependencia de um jogo especifico por
oito paginas de demonstracao. O programa em Assembly e executado pelo
nucleo com busca ativa, registradores, ULA e status. O video continua
funcionando enquanto o programa calcula, desenha ou espera um quadro.

Simulacao e precheck verificam o RTL; a entrega fisica ainda exige uma
compilacao nova no Quartus, revisao de recursos e timing e execucao desta
versao na DE1-SoC. A imagem da versao anterior na placa e os arquivos de
`output_files/` do repositorio nao comprovam a galeria atual.

## Preparar e compilar a galeria

No Linux, abra um terminal na pasta do projeto. Instale Python 3 e Quartus
Prime com suporte Cyclone V, deixando `python3` e `quartus_sh` no PATH.
O script verifica se `programs/showcase.hex` corresponde ao Assembly antes
de criar uma compilacao isolada:

```bash
python3 scripts/assemble.py programs/showcase.asm --check
python3 scripts/generate_showcase_assets.py --check
bash scripts/synth_quartus.sh
# --showcase e --pbl2 selecionam o mesmo modo padrao:
bash scripts/synth_quartus.sh --showcase
```

Se o Assembly tiver sido editado, gere novamente o programa antes de
compilar:

```bash
python3 scripts/assemble.py programs/showcase.asm
# Se os padroes ou a paleta gerados forem alterados:
python3 scripts/generate_showcase_assets.py
```

Cada compilacao usa `.build/quartus/run.XXXXXX`, copiando RTL, QSF, QPF,
SDC, memorias, `programs/` e `assets/`. O QSF da copia recebe
`USE_PROGRAMMABLE_CORE=1`, `SHOWCASE=1`, `USE_ACTIVE_FETCH=0`, o numero
real de palavras e `PROGRAM_FILE="programs/showcase.hex"`. A selecao do
nucleo programavel tem prioridade sobre o controlador de busca antigo.
O arquivo `mode.txt` registra a selecao; os resultados antigos permanecem
preservados. O programa deve conter entre 1 e 4096 palavras de 32 bits.

Para conferir a copia e os parametros sem Quartus:

```bash
bash scripts/synth_quartus.sh --showcase --prepare-only
```

Este comando nao produz `.sof`, fitting ou timing. Uma compilacao normal
sem Quartus disponivel retorna 127 e informa que nenhum resultado novo
foi produzido.

## Gravar na FPGA e executar

Depois de a compilacao e a revisao dos relatorios terminarem:

1. Ligue a DE1-SoC e conecte o monitor VGA e a interface USB-Blaster.
2. Abra **Tools > Programmer** no Quartus. Em **Hardware Setup**,
   selecione o USB-Blaster e use o modo JTAG.
3. Em **Add File**, escolha exclusivamente o arquivo novo
   `.build/quartus/run.XXXXXX/output_files/gpu.sof` da execucao revisada.
4. Marque **Program/Configure**, clique em **Start** e espere 100%.
5. Pressione e solte **KEY0** para reiniciar a galeria.

A programacao carrega o circuito na FPGA e a execucao comeca sozinha.
Nao ha um arquivo para abrir dentro da placa. Copiar o `.sof` por SSH,
pendrive ou cartao SD nao configura a FPGA. A gravacao por `.sof` e
volatil: ao desligar, sera necessario programar novamente ou preparar
separadamente um metodo persistente suportado pela plataforma.

Se USB-Blaster nao aparecer, verifique a porta correta da placa, cabo de
dados, deteccao via `lsusb` e resultado de `jtagconfig`. Este roteiro nao
pressupoe um gerenciador FPGA configurado no Linux do HPS nem promete
carregamento por SSH; esse caminho exige identificar e preparar o sistema
real da placa.

## Controles da galeria

| Controle | Funcao |
|---|---|
| KEY0 | Reset do circuito e do programa. |
| SW9 = 0 | Selecao manual de pagina por SW[2:0], de 0 a 7. |
| SW9 = 1 | Alternancia automatica entre as oito paginas. |
| KEY2 | Proxima pagina no modo automatico. |
| SW8 = 1 | Pausa a fase de animacao e a contagem de alternancia automatica. |
| KEY1 | Avanca um passo de animacao quando pausado. |
| KEY3 | Reinicia a fase e a pagina da demonstracao. |

O modo automatico avanca apos 120 iteracoes ativas do programa, normalmente
cerca de dois segundos. A pagina de double buffer faz duas esperas de
quadro por iteracao e leva aproximadamente quatro segundos. Pausa e o
tempo gasto redesenhando uma pagina prolongam esses intervalos.

Use SW8 para manter um caso parado e comparar os objetos na tela. Use
KEY1 para inspecionar a transicao seguinte. Os botoes passam pela
sincronizacao do circuito; anote qualquer acionamento repetido ou perdido
na bancada. Os LEDs indicam:

| LED | Significado no nucleo programavel |
|---|---|
| LEDR[2:0] | Identificador da pagina, de 0 a 7. |
| LEDR[3] | Programa parado em HALT; a galeria normal permanece em laco. |
| LEDR[4] | Erro acumulado; a pagina 7 provoca e limpa esse estado de proposito. |
| LEDR[5] | Buffers inicializados. |
| LEDR[6] | Banco de poligonos atualmente visivel. |
| LEDR[7] | Modo de double buffer habilitado. |
| LEDR[8] | Algum motor grafico ocupado. |
| LEDR[9] | Reset liberado. |

## O que observar em cada pagina

| Pagina | Recursos apresentados | Verificacao na placa |
|---|---|---|
| 0 | Scroll X/Y e escrita no tilemap | Rolagem nos dois eixos e repeticao nas bordas; alteracao das celulas selecionadas. |
| 1 | Os 32 IDs de sprite | Objetos em grade, mudanca de posicao/imagem e habilitacao individual. |
| 2 | Espelhamentos | Comparar original, horizontal, vertical e ambos com o mesmo padrao assimetrico. |
| 3 | Transparencia e prioridades 0 a 3 | Partes transparentes deixam ver o objeto de tras; maior prioridade vence; no empate, menor ID. |
| 4 | Bancos de paleta e CLUT RGB | Mesma imagem com cores de bancos diferentes e alteracao programada da cor. |
| 5 | Triangulo, retangulo e recorte | Formas preenchidas, composicao com sprites e escrita limitada a cena 320x240. |
| 6 | Dois buffers e PRESENT | Desenho animado aparece somente apos apresentacao no intervalo vertical. |
| 7 | Status e comando invalido | Erro registrado sem parar o VGA; comando de limpeza de erro permite continuar. |

O double buffer e da camada de poligonos. Tilemap, sprites e paleta
continuam sendo atualizados diretamente; a galeria nao demonstra uma
troca atomica de todas as camadas. Um comando invalido na pagina de
diagnostico faz parte do teste e nao deve provocar escritas graficas ou
perda de sincronismo.

Para comprovar os recursos, registre a pagina, as posicoes de chaves,
os LEDs e o resultado visual. Teste tambem reset durante atividade e
troca de pagina enquanto um motor esta ocupado. Uma imagem estavel e
necessaria, mas nao substitui a verificacao de prioridades, transparencia,
aceitacao dos comandos e sincronizacao de apresentacao.

## Modos anteriores para comparacao

```bash
# Controles antigos: pulo, triangulo e retangulo por botoes.
bash scripts/synth_quartus.sh --legacy
# Controlador de busca antigo e programa fetch_demo.hex.
bash scripts/synth_quartus.sh --active
# Cena finita do Problema 1, pbl1_validation.hex.
bash scripts/synth_quartus.sh --pbl1
```

Esses modos desabilitam `USE_PROGRAMMABLE_CORE` e `SHOWCASE`. `--legacy`
tambem desabilita `USE_ACTIVE_FETCH`; os outros dois habilitam a busca
antiga. Cada modo exige seu `.sof` correspondente, pois os parametros
sao selecionados na compilacao. As chaves da galeria nao mudam o modo
de circuito carregado.

## Sintese preliminar e relatorios finais

Com Yosys e Python 3 no PATH:

```bash
bash scripts/synth_precheck.sh --structure-only
bash scripts/synth_precheck.sh
bash scripts/synth_precheck.sh --legacy
bash scripts/synth_precheck.sh --active
```

O script guarda logs, versao de Yosys, parametros e netlists em
`.build/synth/run.XXXXXX`. Ele verifica hierarquia, drivers, memorias e
o mapeamento preliminar Cyclone V. Uma memoria grande que nao mapear
em blocos interrompe a verificacao antes de expandir em flip-flops.
Isso nao gera bitstream, estima Fmax ou aprova o dispositivo.

Para fechar a entrega, arquive uma compilacao Quartus da galeria com:

- Hash do commit, versao do Quartus, revisao da placa e modo compilado.
- Recursos finais do fitter: ALMs, registradores, M10K/bits de RAM,
  DSP/multiplicadores e PLLs, comparados a capacidade do dispositivo.
- Clocks de 50 MHz e 25 MHz, setup/hold, recovery/removal, Fmax e
  caminhos sem restricao, justificando as excecoes.
- Mensagens de inferencia de memoria, inicializacao, latches, larguras,
  multiplos drivers e travessias de clock.
- Evidencias da execucao das oito paginas e resultados dos testes.

`gpu.sdc` mantem clocks de 20/40 ns e delays externos VGA provisoriamente
em 0 ns. Antes de aprovar timing externo, confirme DAC, borda de
amostragem, setup/hold e atrasos das trilhas. O procedimento e os limites
estao no [roteiro do Problema 1](validacao-fisica-pbl1.md). Uma passagem
no precheck ou slack baseado em restricoes provisorias nao encerra essa
validacao.

## Resultado medido

Yosys 0.52 concluiu estrutura e mapeamento Cyclone V nos tres modos abaixo.
`check -assert` reportou zero problemas antes e depois do mapeamento. Todas
as memorias grandes foram mapeadas em blocos; no modo antigo de busca,
a ROM pequena de nove palavras virou logica na otimizacao final.

| Celulas do netlist Yosys final | Galeria programavel | Botoes antigos | Busca antiga |
|---|---:|---:|---:|
| `MISTRAL_M10K` | 226 | 219 | 219 |
| `MISTRAL_FF` | 2.582 | 1.971 | 1.952 |
| LUTs de 2 a 6 entradas | 4.015 | 2.558 | 2.559 |
| `MISTRAL_ALUT_ARITH` | 2.981 | 2.885 | 2.783 |
| `MISTRAL_MUL27X27` | 8 | 8 | 8 |

Na galeria, os M10K finais se distribuem em 152 nos buffers de poligonos,
46 no motor de sprites, 14 nos padroes do background, 11 no programa,
dois no tilemap e um na paleta. O programa medido possui 2.626 palavras.
Antes da otimizacao final, o mapeador contou 240 M10K; a tabela usa
`mapped.json` e `mapped-summary.txt` da fase final. As imagens da galeria
permitem otimizar partes constantes das ROMs, por isso a distribuicao
nao e identica a dos assets antigos.

Essas contagens nao sao ALMs do fitter. LUTs, celulas aritmeticas e
multiplicadores do netlist nao devem ser somados ou convertidos diretamente
em ALMs/DSPs fisicos. Empacotamento, colocacao e roteamento definitivos
continuam a cargo do Quartus.

Logs desta medicao no ambiente: `.build/synth/run.wMwbVh` (galeria),
`.build/synth/run.ts6SqN` (botoes) e `.build/synth/run.Nu9R7K` (busca
antiga). Gere outra medicao ao alterar o RTL, programa ou assets.

A preparacao Quartus passou nos modos padrao, `--showcase`, `--pbl2`,
`--legacy`, `--active` e `--pbl1`; os parametros e as copias das memorias
foram conferidos. Os checks de Assembly e assets confirmaram os arquivos
gerados sem modifica-los. A ausencia de Quartus retorna 127, sem anunciar
uma compilacao concluida.

Quartus e placa nao estao disponiveis no ambiente de desenvolvimento em
nuvem; nenhum `.sof`, Fmax, slack ou teste fisico novo foi aprovado aqui.
