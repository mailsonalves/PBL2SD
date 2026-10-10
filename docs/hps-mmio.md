# Interface de controle da GPU e integracao futura com o HPS

`gpu_mmio.v` implementa e testa um banco de registradores de 32 bits com sinais
de uma interface Avalon-MM simples. `gpu_core` recebe esses sinais no mesmo
dominio de `CLOCK_50`. O wrapper de placa `gpu_de1_soc_top` os desabilita.
**Este RTL nao estabelece uma conexao fisica com o HPS.** Nao ha endereco
fisico de CPU definido, sistema Platform Designer, ponte HPS-FPGA instanciada
ou programa Linux de acesso ao hardware nesta entrega.

## Contrato da interface RTL

| Sinal | Contrato |
|---|---|
| `address[5:0]` | Deslocamento em **bytes**, de 0 a 63; registradores alinhados em 4 bytes. |
| `read` / `readdata[31:0]` | Leitura combinacional com latencia zero; dados zero quando `read=0`. |
| `write` / `writedata[31:0]` | Escrita aceita na borda positiva de `clk`, quando fora de reset. |
| `byteenable[3:0]` | Cada bit habilita um byte; bit 0 corresponde a `writedata[7:0]`. |
| `waitrequest` | Sempre zero; cada ciclo de escrita constitui uma transacao aceita. |
| `rst_n` | Reset ativo baixo, assert assincrono; liberar sincronizado ao clock da interface. |
| `frame_boundary` | Evento no dominio da GPU; cada borda com valor 1 incrementa o contador. |

Nao existem `readdatavalid`, respostas com latencia variavel, interrupcoes,
DMA, FIFO de comandos ou escrita da memoria de instrucoes por este banco.
Os programas continuam sendo carregados por arquivo `.hex` na compilacao.
Enderecos desalinhados ou nao definidos retornam zero e ignoram escritas.
Escritas nos registradores RO tambem sao ignoradas. Leituras podem ocorrer
durante escritas e refletem o estado atual, sem snapshot de multiplos registros.

| Offset em bytes | Registro | Acesso | Conteudo |
|---|---|---|---|
| `0x00` | CONTROL | RW | Leitura: bit 0 = pause; demais bits zero. Escrita: bit 0 define pause, bit 1 solicita restart, bit 2 limpa erro. |
| `0x04` | STATUS | RO | Estado da GPU, conforme tabela abaixo. |
| `0x08` | PC | RO | Endereco da palavra de instrucao atual, estendido com zeros. |
| `0x0C` | IR | RO | Palavra de instrucao de 32 bits em execucao. |
| `0x10` | FRAME_COUNT | RO | Contador de 32 bits de eventos de quadro, com wrap modulo 2^32. |
| `0x14` | ID | RO | `0x50424C32`, identificador ASCII `PBL2`. |

Somente escritas em `0x00` com `byteenable[0]=1` alteram os controles.
Bits reservados da escrita sao ignorados. `restart` e `clear_error` sao pulsos
registrados de um ciclo; duas escritas consecutivas podem solicita-los em dois
ciclos consecutivos. Eles nao ficam armazenados para leitura posterior.
O controlador da GPU consome os pulsos na borda seguinte. `pause` fica no valor
da ultima escrita aceita ate outra escrita ou reset. O reset limpa a pausa,
os pulsos e o contador. Reiniciar apenas a CPU nao zera o contador de quadros
nem as memorias graficas; uma operacao grafica ja aceita termina antes de o
programa recomecar. Pausar impede novas instrucoes e deixa operacoes em curso
terminarem. A imagem e o VGA continuam funcionando.

| Bit STATUS | Significado |
|---|---|
| 0 | Decodificador grafico pronto para aceitar um comando. |
| 1 | CPU executando ou unidade grafica com operacao pendente. |
| 2 | Programa parado por HALT. |
| 3 | Erro persistente da CPU/decodificador grafico. |
| 4 | Buffers de poligonos inicializados. |
| 5 | Identidade do buffer frontal de poligonos. |
| 6 | Buffer duplo de poligonos habilitado. |
| 7 | Motor de sprites ocupado. |
| 8 | CPU aguardando o proximo evento de quadro. |
| 9 | Pulso de uma instrucao concluida; nao e um contador nem um latch. |
| 10, 11, 12, 13 | Flags Z, N, C e V, respectivamente. |
| 31:14 | Zero. |

O bit 9 pode passar entre duas leituras de software. Observe HALT/PC ou use um
programa com espera/pausa para acompanhar progresso; este banco nao garante a
captura de todo pulso de conclusao pelo HPS.

Exemplos de palavras de CONTROL, apos a integracao fisica:

| Palavra | Efeito |
|---|---|
| `0` | Continuar execucao. |
| `1` | Pausar novas instrucoes. |
| `2` | Reiniciar CPU e continuar. |
| `3` | Reiniciar CPU e mante-la pausada. |
| `4` | Limpar erro e continuar. |
| `5` | Limpar erro e manter pausa. |

Uma escrita de controle sempre define o bit de pausa. Para preserva-lo ao
solicitar um pulso, ler CONTROL e incluir seu bit 0 na nova palavra. Concorrencia
entre escritores requer serializacao no software. Um erro novo no ciclo de
limpeza tem prioridade no controlador e pode manter o bit de erro ativo.

## O que falta para o HPS na DE1-SoC

1. Criar um sistema Platform Designer compativel com o Cyclone V da placa,
   configurar HPS, SDRAM, clocks/resets e habilitar uma ponte HPS-to-FPGA,
   normalmente a lightweight para este banco pequeno.
2. Empacotar a interface da GPU como slave de 32 bits, com span de 64 bytes,
   `addressUnits=SYMBOLS` (bytes de 8 bits), `readLatency=0` e os sinais da tabela.
   Se o componente usar enderecos em palavras, converter explicitamente para
   deslocamentos em bytes antes de conectar `gpu_core`. Endereco de palavra 1
   deve atingir STATUS (`0x04`), nunca um endereco desalinhado (`0x01`).
3. Conectar clock e reset da interface a `CLOCK_50`/reset da GPU. Se a ponte
   usar outro clock, inserir um Avalon-MM Clock Crossing Bridge apropriado,
   ou adaptar os clocks do sistema. Nao conectar o barramento multibit
   assincrono diretamente nem sincronizar cada bit independentemente.
   Coordenar reset da ponte e da GPU, com liberacao sincronizada em cada dominio.
4. Instanciar o sistema gerado em um top com os pinos HPS obrigatorios,
   acrescentar arquivos gerados ao Quartus e revisar QSF/SDC, clocks gerados,
   CDC, reset e timing. O top de placa fornecido atualmente tem apenas os
   pinos FPGA/VGA e nao instancia esse sistema.
5. Atribuir o offset/base no mapa do Platform Designer; gerar headers e
   configuracao de software a partir desse mapa. Habilitar as pontes na placa
   pelo fluxo HPS/boot apropriado. Nao assumir um endereco fisico fixo apenas
   pela identidade DE1-SoC.
6. Mapear o recurso com atributos de memoria de dispositivo, usar os acessos
   MMIO/barreiras apropriados ao sistema operacional e validar ID, pause,
   restart, STATUS e FRAME_COUNT na placa. Para Linux, implementar a exposicao
   via device tree/driver ou uma ferramenta de bancada compatível com o mapa
   e as permissoes existentes. Um ponteiro `volatile` sozinho nao configura
   atributos de memoria, pontes, clocks ou ordenacao de acessos.

Esses passos dependem de Quartus/Platform Designer, boot do HPS e placa real.
A simulacao do banco de registradores nao comprova essa integracao.

## Validacao reproduzivel do banco

```bash
source /workspace/.pbl-tools/activate.sh
cd /workspace/PBL2SD
mkdir -p .build/mmio
iverilog -g2012 -s tb_gpu_mmio -o .build/mmio/test.vvp \
  gpu_mmio.v tests/tb_gpu_mmio.sv
vvp .build/mmio/test.vvp
```

O teste percorre os 64 offsets, todas as byteenables e combinacoes de controle,
confere RO e enderecos desalinhados, read sem borda de clock, pulsos e escritas
consecutivas, contador com pause/restart, overflow e reset assincrono. Os
testes de integracao de `gpu_core` verificam a ligacao desses controles a CPU,
o status e a preservacao do VGA/estado grafico no restart.
