# Problema 2 — Etapa 1: busca ativa, PC e IR

O objetivo desta etapa e executar uma sequencia de comandos armazenada dentro
da FPGA, reaproveitando o decodificador e os motores existentes. A demonstracao
original por botoes continua sendo o modo padrao.

## Estrutura

```text
instruction_memory -> active_fetch_controller -> cmd_decoder -> motores
                          PC e IR                    ready/busy
```

- `instruction_memory.v`: memoria de palavras de 32 bits, carregada do arquivo
  `programs/fetch_demo.hex`. Sua leitura e sincrona: mudar o endereco nao muda
  imediatamente a saida; o resultado aparece apos uma borda de subida.
- `active_fetch_controller.v`: mantem o PC (endereco da instrucao) e o IR
  (instrucao atual), apresenta o comando ao decoder e espera sua conclusao.
- `gpu_de1_soc_top.v`: seleciona a fonte de comandos pelo parametro
  `USE_ACTIVE_FETCH`. `0` usa botoes; `1` usa o programa interno. A selecao ocorre
  na compilacao, e nao pelas chaves da placa.
- `LEDR[3]`: indica que o programa encontrou `HALT`. No modo original, permanece
  apagado. Os demais indicadores existentes foram preservados.

## Ciclo de execucao

| Estado | O que acontece |
|---|---|
| `FETCH` | A memoria recebe o endereco indicado pelo PC. |
| `LATCH` | O controlador captura a palavra lida no IR. |
| `ISSUE` | Mantem comando e `cmd_valid` ate o decoder aceitar com `cmd_ready`. |
| `SETTLE` | Aguarda um ciclo para o sinal registrado de inicio chegar ao rasterizador. |
| `WAIT_DONE` | Espera `execution_busy=0` e `cmd_ready=1`; depois incrementa o PC. |
| `HALTED` | Mantem PC e IR parados e deixa de enviar comandos. |

O ciclo `SETTLE` e necessario porque o rasterizador nao sinaliza `busy` na mesma
borda em que o decoder aceita o comando. Avancar imediatamente poderia iniciar
a proxima instrucao antes de a operacao anterior comecar.

O PC conta palavras, nao bytes: os enderecos sao 0, 1, 2... O reset ativo em zero
restaura PC=0 e reinicia a busca. Nesta etapa, nao existem desvios.

## Programa de demonstracao

Cada linha de `programs/fetch_demo.hex` contem oito digitos hexadecimais. Os
comandos existentes seguem os campos do RTL, agora corrigidos na tabela do
README principal.

| PC | Palavra | Acao esperada |
|---|---|---|
| 0 | `0F000000` | Limpar os 76.800 pixels da camada de poligonos. |
| 1 | `10FFF800` | Definir a cor 255 como vermelho RGB565 `F800`. |
| 2 | `30020305` | Escrever tile 5 na celula X=2, Y=3. |
| 3 | `50000804` | Definir rolagem X=8, Y=4. |
| 4 | `60000064` | Atualizar o sprite 0 para X=152, Y=100, tile inicial 1. |
| 5 | `70000A0A` | Definir o primeiro vertice: (10,10). |
| 6 | `8000140A` | Definir o segundo vertice: (20,10). |
| 7 | `9FF00A14` | Definir o terceiro vertice: (10,20), e desenhar com indice 255. |
| 8 | `F0000000` | Parar o programa. O video continua funcionando. |

A conversao RGB565 existente acrescenta zeros aos componentes, portanto
`F800` resulta em RGB24 `F80000`. O triangulo inclui suas bordas e ocupa 66
pixels logicos.

O opcode `0xF` esta reservado para `HALT` no controlador; use `F0000000` com os
demais campos zero. Esse comando nunca e enviado ao decoder grafico.

`PROGRAM_WORDS` deve corresponder ao numero de palavras do arquivo (9 neste
programa). Enderecos fora desse intervalo retornam `HALT`. O endereco padrao tem
8 bits; para esta etapa use programas de ate 255 palavras, incluindo o `HALT`,
para manter um endereco de parada fora do programa. O arquivo deve conter todas
as palavras declaradas e ser encontrado a partir do diretorio do projeto.

## Executar os testes

Sao necessarios Verilator 5, compilador C++ e Make. Os testes nao precisam de
SDL2, monitor, ARM ou placa fisica.

No ambiente em nuvem preparado nesta conversa:

```bash
cd /workspace/PBL1SD
source /workspace/.pbl-tools/activate.sh
bash scripts/test_step1.sh
```

Em outra maquina com as ferramentas no PATH, basta executar
`bash scripts/test_step1.sh` a partir do projeto. O script tambem encontra o
diretorio do projeto quando chamado de outra pasta.

| Teste | Verificacao |
|---|---|
| `tb_instruction_memory` | Conteudo, latencia da memoria e parada fora do programa. |
| `tb_active_fetch_controller` | Ordem dos oito comandos, PC/IR estaveis durante espera, `busy` atrasado, `HALT`, reset durante execucao e nova execucao apos reset. |
| `tb_active_fetch_integration` | Escrita na paleta, mapa, scroll e sprite; 76.800 escritas de limpeza; 66 pixels do triangulo; conferencia completa do framebuffer; dois quadros VGA apos `HALT`. |
| `tb_board_demo` | O modo padrao ainda envia os comandos originais de scroll e movimento do passaro. |

Os quatro testes devem imprimir `PASS`. Uma divergencia ou timeout interrompe o
script com codigo diferente de zero. Os binarios e logs ficam em
`.build/step1/`, ignorada pelo Git. `build.log` de cada teste conserva os avisos
do compilador; passar nesses testes nao significa que o projeto esteja livre
de avisos de HDL.

## Habilitar a busca ativa

O testbench de integracao ja instancia o top-level com `USE_ACTIVE_FETCH=1`.
Para outras simulacoes Verilator, passe `-GUSE_ACTIVE_FETCH=1` ao compilar o
top-level `gpu_de1_soc_top`. No projeto Quartus, configure o mesmo parametro
para 1 na instancia top-level antes de compilar; o padrao continua sendo 0.

Inclua `instruction_memory.v` e `active_fetch_controller.v` na compilacao e
execute a simulacao a partir da raiz do projeto. O arquivo `gpu.qsf` ja inclui
os novos modulos e o programa hexadecimal.

## Limites e proxima etapa

Esta etapa foi validada em simulacao, sem nova sintese Quartus ou demonstracao
fisica. A inicializacao por limpeza pertence ao programa de busca ativa;
a demonstracao antiga continua com a pendencia de inicializacao de seu buffer.
`HALT` nao espera um novo quadro nem realiza troca de buffers.

Ainda faltam banco de registradores, ULA/datapath, status arquitetural,
sincronizacao de quadro, Assembly/montador e acesso generico aos sprites para
completar o Problema 2. Esta sequencia inicial de comandos em hexadecimal nao
substitui o programa Assembly exigido pelo documento.

A proxima etapa recomendada e acrescentar banco de registradores e uma ULA
simples, com testes de carga de imediato e soma, usando o resultado para
controlar um parametro grafico. Os quatro testes atuais servirao como
regressao para verificar que a busca e os motores continuam funcionando.
