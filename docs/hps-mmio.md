# MMIO, carregamento de programas e integração HPS–FPGA

O núcleo oferece um banco Avalon-MM para controlar a CPU e **carregar outro programa na RAM de instruções sem ressintetizar o RTL**. A FPGA continua buscando e executando internamente: o HPS escreve a memória enquanto a CPU está pausada, verifica a carga e solicita execução em PC=0. O HEX permanece como programa inicial ao configurar a FPGA.

`gpu_avalon.v` expõe essa interface ao Platform Designer; [gpu_mmio_hw.tcl](../platform/gpu_mmio_hw.tcl) empacota RTL e recursos. O wrapper independente `gpu_de1_soc_top` mantém o MMIO externo desabilitado. **O componente fornecido não é um sistema HPS pronto:** faltam instanciação/conexão no sistema específico da placa, base física real, integração com o boot e validação em hardware. Não foi gerado ou testado um bitstream com ponte HPS neste ambiente.

## Contrato Avalon-MM

| Sinal | Contrato |
|---|---|
| `clk` / `CLOCK_50` | Clock de 50 MHz compartilhado pela interface e pelo núcleo. |
| `reset_n` / `rst_n` | Assert ativo baixo; o núcleo sincroniza a liberação. O wrapper combina reset da interface e KEY[0]. |
| `address[5:0]` | Deslocamento em **bytes**; span de 64 bytes, registros alinhados em quatro bytes. |
| `read`, `readdata[31:0]` | Leitura combinacional quando a transação é aceita; zero com read=0. PROG_DATA pode aguardar pela RAM síncrona. |
| `write`, `writedata[31:0]` | Escrita na borda com write=1 e waitrequest=0, fora de reset. |
| `byteenable[3:0]` | Um bit por byte; bit 0 seleciona writedata[7:0]. |
| `waitrequest` | Um durante reset interno, inclusive os dois clocks de liberação; normalmente zero após isso. Uma leitura válida de PROG_DATA aguarda dois ciclos após mudança do ponteiro/modo ou escrita com autoincremento. |

Não há readdatavalid, pipeline de leituras, DMA, FIFO de comandos ou interrupção. O master deve manter address/read/dados estáveis enquanto waitrequest estiver ativo. readLatency=0 significa resposta no ciclo de aceitação; os ciclos necessários à RAM são tratados por waitrequest. Endereços indefinidos/desalinhados retornam zero e ignoram escritas. Escritas RO são ignoradas. Bytes não habilitados não alteram os registros.

## Mapa de registradores

Todos os endereços abaixo são **offsets do componente**, não endereços físicos ARM.

| Offset | Registro | Acesso | Conteúdo |
|---|---|---|---|
| 0x00 | CONTROL | RW | Escrita: bit0=pause solicitado, bit1=restart, bit2=clear_error, bit3=load_mode. Leitura: bit0=pause efetivo, bit3=load_mode; demais zero. |
| 0x04 | STATUS | RO | Estado de CPU/gráficos, tabela abaixo. |
| 0x08 | PC | RO | Endereço da palavra de instrução, estendido com zeros. |
| 0x0C | IR | RO | Instrução atual de 32 bits. |
| 0x10 | FRAME_COUNT | RO | Contador de eventos de quadro de 32 bits, wrap módulo 2³². |
| 0x14 | ID | RO | 0x50424C32, ASCII PBL2. |
| 0x18 | PROG_ADDR | RW | Ponteiro de **palavra** de nove bits; valores de zero até a capacidade, inclusive a sentinela final. |
| 0x1C | PROG_DATA | RW | Dados da palavra no ponteiro; escrita aceita incrementa o ponteiro em uma palavra; leitura não incrementa. |
| 0x20 | PROG_LENGTH | RW | Comprimento efetivo, de 1 até PROGRAM_WORDS; default igual à capacidade. |
| 0x24 | LOAD_STATUS | RO | bit0=LOAD_READY, bit1=erro persistente de carga, [31:16]=capacidade em palavras; [15:2]=0. |

CONTROL só aceita escritas com byteenable[0]. restart/clear_error são pulsos de um ciclo; pause solicitado fica armazenado. **load_mode força pause efetivo**, independentemente do bit0 escrito. Cada escrita CONTROL define os bits 0/3; preserve o modo desejado ao solicitar outro controle. Entrar ou sair de load_mode também solicita restart automaticamente. Entrada zera PROG_ADDR e limpa erro de carga.

PROG_ADDR e PROG_LENGTH mesclam apenas os nove bits dos bytes 0/1 habilitados; bytes 2/3 são ignorados. Escritas nesses registros exigem LOAD_READY; comprimento zero ou maior que capacidade gera erro e não altera o comprimento. PROG_ADDR pode receber a sentinela igual à capacidade; nessa posição não existe palavra válida. Com capacidade 256, após escrever a palavra 255 o ponteiro é 256, sem voltar à palavra 0.

Escrita PROG_DATA exige LOAD_READY, PROG_ADDR<capacidade e algum byte habilitado. Byteenable parcial modifica somente os bytes selecionados, mas **cada escrita aceita incrementa uma palavra**. Para alterar dois bytes da mesma palavra em transações separadas, reposicione o ponteiro antes da segunda. Byteenable=0 é uma operação sem efeito, sem erro/autoincremento. Escrita antes de LOAD_READY, fora de load_mode ou em endereço inválido é rejeitada com erro de carga; não há waitrequest para essas escritas. O software deve aguardar LOAD_READY antes de carregar.

Leitura PROG_DATA só consulta RAM quando LOAD_READY e endereço válido; nas outras situações retorna F0000000 sem esperar. Depois de reposicionar o ponteiro, a resposta síncrona pode levar dois ciclos e waitrequest mantém a transação pendente. Não leia um dado antes da aceitação. PROG_ADDR/PROG_LENGTH podem ser consultados fora de load_mode. Erro de carga é separado do erro de execução; CONTROL bit2 ou nova entrada no modo de carga o limpa.

| Bit STATUS | Significado |
|---|---|
| 0 | Decodificador gráfico pronto. |
| 1 | CPU executando ou gráfico com operação pendente. |
| 2 | Programa parado por HALT. |
| 3 | Erro persistente de execução/decodificação. |
| 4 | Buffers de polígonos inicializados. |
| 5 | Identidade do buffer frontal. |
| 6 | Buffer duplo de polígonos habilitado. |
| 7 | Motor de sprites ocupado. |
| 8 | CPU aguardando evento de quadro. |
| 9 | Pulso done de uma instrução concluída. |
| 10,11,12,13 | Flags Z,N,C,V. |
| 31:14 | Zero. |

O pulso done pode passar entre leituras de software. HALT fornece a indicação persistente de término da sequência; após iniciar um programa finito, aguarde STATUS[2]=1, STATUS[1]=0 e confira STATUS[3]=0. FRAME_COUNT permite comprovar que VGA continua durante carga/pausa/HALT.

## Carregar e executar com segurança

1. Confira ID e capacidade em LOAD_STATUS. O programa deve conter de 1 até a capacidade de palavras; a capacidade padrão é 256.
2. Escreva CONTROL=8 para entrar em load_mode. A CPU reinicia/pausa e **drena operações gráficas anteriormente aceitas**. Aguarde LOAD_STATUS[0]=1 antes de acessar a RAM. Esse estado garante que a CPU não disputa a memória durante carga.
3. Escreva PROG_ADDR=0. Escreva cada instrução em PROG_DATA com quatro bytes habilitados; o ponteiro avança automaticamente.
4. Escreva PROG_LENGTH com o número de palavras carregadas. O comprimento impede buscar conteúdo antigo após uma carga menor; endereços além dele resultam em HALT. Inclua HALT explícito no programa para término no ponto desejado.
5. Confira LOAD_STATUS[1]=0 e o comprimento. Para readback, escreva PROG_ADDR=i e leia PROG_DATA; o Avalon aguarda a leitura síncrona. Compare todas as palavras com o arquivo.
6. Escreva CONTROL=2: sai da carga, solicita restart e executa a partir de PC=0. Aguarde HALT e confira erro/PC/IR. Outra carga repete o mesmo procedimento, usando **o mesmo bitstream**.

Uma falha durante carga deve manter load_mode ativo, evitando executar um programa incompleto. Não iniciar a CPU se erro/readback/comprimento falhar. O utilitário fornecido mantém o modo de carga em erros anteriores ao START.

| Palavra CONTROL | Uso |
|---|---|
| 0 | Continuar fora do modo de carga. |
| 1 | Pausar novas instruções fora da carga. |
| 2 | Sair da carga/reiniciar CPU e executar. |
| 3 | Sair da carga/reiniciar e manter CPU pausada. |
| 4 | Limpar erro e continuar fora da carga. |
| 8 | Entrar/manter carga; pausa efetiva fica ativa. |
| 12 | Limpar erro mantendo carga. |

### Reset e persistência

Restart da CPU preserva RAM de instruções, comprimento, modo de carga e estado gráfico. Reset da GPU/KEY[0]/reset_n também **preserva RAM, PROG_LENGTH e load_mode**, mantendo esses metadados coerentes com o programa carregado. Reset limpa pause solicitado, PROG_ADDR, erro de carga, pulsos e FRAME_COUNT; se load_mode era 1, pause efetivo continua 1 e a CPU permanece impedida de executar a carga parcial. Reconfigurar a FPGA restaura o HEX inicial, comprimento igual à capacidade e load_mode=0.

Reset gráfico reinicializa CPU, sprites/buffers/controle/VGA, mas CLUT/tilemap preservam escritas, conforme a [arquitetura](pbl2-architecture.md). Restart não reconstrói a cena anterior. Cada programa deve configurar o estado que utiliza, inclusive desabilitar sprites de programas anteriores quando necessário.

## Integrar no sistema HPS da DE1-SoC

Use um projeto de referência **Terasic válido para a sua revisão da DE1-SoC**, com HPS DDR3, pinout, configuração de clocks/resets e fluxo de boot já funcionais. Não reconstruir o HPS apenas a partir de um exemplo genérico. O repositório atual contém o top FPGA/VGA, mas não possui .qsys/.sopcinfo nem os arquivos de um sistema HPS verificado.

1. Abra o projeto de referência no Quartus com suporte Cyclone V 5CSEMA5F31C6. Mantenha seus pinos HPS/DDR e configuração de memória. Confirme a revisão PCB e o esquema antes de combinar as atribuições VGA da GPU.
2. No Platform Designer, configure o caminho de busca de componentes para a pasta `platform/` deste checkout e atualize o catálogo. Instancie o componente **GPU PBL2**, nome pbl2_gpu, uma vez. O Tcl aponta para os fontes do próprio checkout; não contém caminhos de uma instalação Quartus específica.
3. Habilite a ponte lightweight HPS-to-FPGA no componente HPS do projeto. Conecte seu master Avalon-MM ao slave `gpu.control`. O slave tem largura de 32 bits, addressUnits=SYMBOLS (bytes), span de 64 bytes, readLatency=0 e waitrequest dinâmico. Se criar um adaptador manual com endereço em palavras, converta para bytes: palavra 1 deve atingir offset 0x04.
4. Conecte `gpu.clock` a um clock de 50 MHz compatível com CLOCK_50. Conecte `gpu.reset` ao reset coordenado do sistema, com liberação sincronizada. Se o master da ponte estiver em outro domínio, use **Avalon-MM Clock Crossing Bridge** apropriado. Não cruzar o barramento multibit diretamente nem sincronizar seus bits isoladamente.
5. Exporte os conduits `gpu.board` e `gpu.vga`. No top do projeto HPS, ligue KEY/SW/LEDR e os pinos VGA exportados aos sinais de placa correspondentes. Preserve os pinos HPS obrigatórios. O núcleo combina KEY[0] e reset_n; KEY[1:3] não selecionam funcionalidades e SW não seleciona programas.
6. Atribua no editor o offset do slave na janela do master lightweight. Salve/gere o sistema e anote o mapa mostrado. Gere os arquivos de síntese e o .sopcinfo. Inclua o .qip gerado no projeto Quartus; não mantenha duas GPUs em paralelo com saídas VGA duplicadas.
7. Mantenha no diretório de compilação os HEX usados pelos caminhos relativos: tiles.hex, tilemap_data.hex, palette.hex e programs/*.hex. O componente inclui esses assets no fileset como OTHER; confira onde o gerador os exportou e se os caminhos do $readmemh resolvem. Se o projeto HPS for externo ao checkout, copie os assets preservando a pasta programs. Alterar um programa pelo HPS depois da configuração não exige repetir essa cópia ou compilar RTL.
8. Reaplique/revise as restrições de CLOCK_50 e pixel clock de 25 MHz no top integrado, incluindo o caminho hierárquico real. Verifique clocks gerados, CDC/reset, setup/hold, caminhos não restringidos, pinos e timing externo VGA/DAC. Não reutilize uma restrição de clock hierárquica que agora aponte para uma instância inexistente.
9. Compile, confira recursos/timing e programe o bitstream integrado. Use o fluxo do projeto Terasic para preloader/bootloader/device tree e configuração do HPS/DDR. Habilite a ponte no Linux pelo mecanismo suportado por esse fluxo. Confirme clocks/reset/bridge disponíveis antes de qualquer MMIO.

**Esses passos ainda precisam ser executados em Quartus/Platform Designer e na placa.** O catálogo Tcl, wrapper e simulação do slave não comprovam que o sistema físico foi gerado ou que HPS/Linux alcança a GPU.

### Obter a base física real

A base relativa escolhida no Platform Designer é apenas o offset do slave no espaço do master; não a use automaticamente como endereço de /dev/mem. Considere a janela da ponte definida para o HPS e a tradução descrita pelo sistema/boot/Linux.

Use o .sopcinfo **do sistema que gerou o bitstream atual**, os headers derivados e o device tree correspondente. No SoC EDS compatível com o projeto, por exemplo:

```bash
sopc-create-header-files <caminho/do/sistema.sopcinfo> \
  --single hps_0.h --module <nome_real_do_componente_hps>
```

Confirme os argumentos com `sopc-create-header-files --help` da versão instalada. Verifique a base do slave vista pelo master lightweight e a janela/tradução da ponte nos arquivos gerados e no device tree (`reg`/`ranges`). Se o slave for exposto por driver/UIO, use o recurso mapeado pelo kernel. **Este repositório não atribui uma base física ARM:** ela será determinada no projeto integrado. O ID PBL2 ajuda a conferir o mapa, mas não torna seguro acessar um endereço arbitrário.

## Compilar e executar o cliente C

[software/gpu_load.c](../software/gpu_load.c) é uma ferramenta de bancada para Linux do HPS; usa /dev/mem com O_SYNC, MMIO de 32 bits e barreiras de memória. Não é um driver Linux. O kernel/boot precisam permitir esse acesso e mapear a região com atributos de dispositivo adequados; o ponteiro volatile não configura a ponte ou atributos. Use somente a base confirmada do sistema atual.

### No computador de desenvolvimento

```bash
cd /workspace/PBL2SD
mkdir -p .build/hps
cc -std=c11 -O2 -Wall -Wextra -Werror \
  software/gpu_load.c -o .build/hps/gpu_load_host
.build/hps/gpu_load_host --check programs/program_a.hex
.build/hps/gpu_load_host --check programs/program_b.hex
```

--check valida apenas sintaxe/tamanho do HEX, sem abrir /dev/mem. Para gerar o executável ARM, use um compilador compatível com a ABI, libc e rootfs da placa; em um rootfs ARM Linux hard-float compatível, um exemplo é:

```bash
arm-linux-gnueabihf-gcc -std=c11 -O2 -Wall -Wextra -Werror \
  software/gpu_load.c -o .build/hps/gpu_load
file .build/hps/gpu_load
```

Se a ABI/rootfs forem diferentes, use o toolchain do projeto de referência. Alternativamente compile o mesmo fonte com cc diretamente no Linux da DE1-SoC, quando esse compilador estiver instalado.

### Transferir e executar na placa

Com endereço/nome do HPS e conta SSH existentes, transfira o binário ARM e os dois arquivos HEX; substitua os campos exemplificativos abaixo:

```bash
scp .build/hps/gpu_load programs/program_a.hex \
  programs/program_b.hex <usuario>@<host-da-placa>:/tmp/
ssh <usuario>@<host-da-placa>
cd /tmp
chmod +x gpu_load
./gpu_load --check program_a.hex
./gpu_load --check program_b.hex
```

Depois de configurar a FPGA, habilitar a ponte e confirmar a base, execute com privilégios de acesso à região:

```bash
# Substitua BASE_FISICA_CONFIRMADA pelo endereço numérico obtido do seu mapa:
sudo ./gpu_load --base BASE_FISICA_CONFIRMADA \
  --program program_a.hex --timeout-ms 10000
sudo ./gpu_load --base BASE_FISICA_CONFIRMADA \
  --program program_b.hex --timeout-ms 10000
```

A ferramenta confere ID/capacidade, escreve CONTROL=12 para entrar/manter carga e limpar erro de tentativa anterior, aguarda LOAD_READY, escreve cada palavra, define comprimento, compara readback e solicita START com CONTROL=2. Depois aguarda HALT sem erro e imprime PC/status. O Programa A desenha um triângulo e posiciona duas sprites sem flips; o Programa B desenha um retângulo em outra região e posiciona duas sprites com flips H/V. O segundo comando carrega a outra cena **sem mudar o Verilog ou o bitstream**. Programas infinitos não chegam a HALT e causarão timeout nesta ferramenta; os programas fornecidos são finitos. Em falha de ID, não prossiga: verifique mapa/ponte/reset antes de tentar outro endereço.

Para um programa novo:

```bash
python3 tools/assemble.py programs/meu_programa.asm --words 256
# Transferir meu_programa.hex para a placa e usar --program nesse arquivo.
```

O carregador suporta de 1 a 256 linhas com uma palavra HEX de oito dígitos cada, incluindo comentários # ou //. A capacidade configurada pode ser menor que 256; o arquivo precisa caber nela. Os programas publicados usam padding HALT até 256.

## Verificação disponível e limites físicos

Execute da raiz, com as ferramentas configuradas:

```bash
source /workspace/.pbl-tools/activate.sh
cd /workspace/PBL2SD
bash scripts/test_pbl2.sh
```

A suíte contém testes do banco MMIO e do carregamento integrado: endereços/byteenables, pausa/restart, espera da RAM, comprimento, erros e troca de programas preservando VGA. Consulte o [relatório de validação](pbl2-validation.md) para os alvos e resultados consolidados. O wrapper gpu_avalon passou na elaboração com Icarus e na análise Verilator; sintaxe Tcl, metadados da interface e caminhos dos arquivos foram conferidos localmente. A geração nativa do componente/sistema no Platform Designer ainda não foi realizada.

Também é necessário, na placa: conferir ID e mapa, LOAD_READY após operação em curso, readback integral, término/status, crescimento de FRAME_COUNT e execução dos dois programas com o mesmo bitstream. Comunicação física HPS, DDR/boot, permissões/atributos Linux e timing do top integrado permanecem sem validação neste ambiente.
