# Coprocessador Gráfico 2D utilizando a DE1-SoC - Desenvolvimento e projeção gráfica do Jogo Flappy Bird em Verilog.

O desenvolvimento do Problema 2 com busca ativa comecou pela
[Etapa 1: memoria de instrucoes, PC e IR](docs/pbl2-etapa1.md).
Essa etapa possui quatro testes automatizados e preserva a demonstracao por
botoes como modo padrao. Banco de registradores, ULA e sincronizacao de quadro
serao acrescentados nas proximas etapas.

A [Etapa 2: sprites genericos](docs/pbl2-etapa2.md) permite configurar os 32
sprites por comandos de posicao, imagem, habilitacao e espelhamento. Execute
`bash scripts/test_step2.sh` para testar essa etapa e repetir os quatro testes
da etapa 1.
  <h3>
    Lucca Coutinho, Mailson Alves, Ramon Santos
  
  </h3>


  <p>
    Engenharia de Computação – Universidade Estadual de Feira de Santana (UEFS)
    Av. Transnordestina, s/n, Novo Horizonte
    Feira de Santana – BA, Brasil – 44036-900
  </p>

---

## Sumário

1. [Definição do Problema](#1-definição-do-problema)
2. [Resumo da Solução Proposta](#2-resumo-da-solução-proposta)
3. [Requisitos do Sistema](#3-requisitos-do-sistema)
   - [3.1 Requisitos Funcionais](#31-requisitos-funcionais)
   - [3.2 Requisitos Não Funcionais](#32-requisitos-não-funcionais)
4. [Especificação do Hardware](#4-especificação-do-hardware)
5. [Arquitetura e Decisões de Projeto](#5-arquitetura-e-decisões-de-projeto)
   - [5.1 Visão Geral dos Módulos](#51-visão-geral-dos-módulos)
   - [5.2 Diagrama em Blocos](#52-diagrama-em-blocos)
   - [5.3 Conjunto de Instruções Customizado (ISA de 32 bits)](#53-conjunto-de-instruções-customizado-isa-de-32-bits)
   - [5.4 Justificativa das Decisões Adotadas](#54-justificativa-das-decisões-adotadas)
6. [Metodologia de Testes e Validação](#6-metodologia-de-testes-e-validação)
   - [6.1 Simulação em ModelSim e Testes Manuais](#61-simulação-em-modelsim-e-testes-manuais)
   - [6.2 Validação Visual da Saída VGA (Verilator)](#62-validação-visual-da-saída-vga-verilator)
7. [Apresentação dos Resultados](#7-apresentação-dos-resultados)
   - [7.1 Resultados de Simulação](#71-resultados-de-simulação)
   - [7.2 Demonstração em Hardware](#72-demonstração-em-hardware)
8. [Limitações, Gargalos e Itens Não Atendidos](#8-limitações-gargalos-e-itens-não-atendidos)
9. [Conclusão](#9-conclusão)
10. [Referências](#10-referências)

---

## 1. Definição do Problema

O projeto consiste no desenvolvimento e modelagem em Verilog HDL de um coprocessador gráfico 2D (GPU) dedicado para execução em FPGA. O circuito tem a finalidade de processar fluxos contínuos de instruções gráficas de 32 bits e compor múltiplos planos visuais em tempo real, gerando os sinais analógicos e de sincronismo exigidos pelo padrão de vídeo VGA (640×480 @ 60 Hz).

---

## 2. Resumo da Solução Proposta

A solução desenvolvida baseia-se na criação de um motor gráfico para simular a dinâmica de um jogo no estilo *Flappy Bird*. A aplicação utiliza uma arquitetura com renderização contínua de plano de fundo baseada em *Tilemap* com capacidade de rolagem (*scrolling* vertical/horizontal), além do posicionamento dinâmico de sprites representando elementos do jogo atualizados linha a linha conforme a interação do usuário e o fluxo de instruções enviadas ao coprocessador gráfico.

---

## 3. Requisitos do Sistema

### 3.1 Requisitos Funcionais
* **RF01 - Temporização VGA:** Gerar sinais `HSYNC`, `VSYNC` e controle de apagamento `BLANK_N` para padrão 640×480 a ~60 Hz.
* **RF02 - Decodificação de Instruções de 32 bits:** Decodificar e rotear palavras de comando baseadas em Opcode de 4 bits e parâmetros.
* **RF03 - Motor de Background :** Mapear matriz de 40×30 blocos de 8×8 pixels com suporte a registradores de rolagem .
* **RF04 - Motor de Sprites:** Processar objetos móveis de 16×16 pixels com controle de coordenadas lógicas e sobreposição.
* **RF05 - Rasterizador de Polígonos:** Preenchimento de triângulos e retângulos e limpeza de buffer através de funções aritméticas dedicadas.
* **RF06 - Composição e Paleta CLUT:** Multiplexar camadas respeitando a cor transparente fixa `0x00` e traduzir índices de 8 bits para padrão RGB de 24 bits.

### 3.2 Requisitos Não Funcionais
* **RNF01 - Estabilidade Temporal:** Manter sincronismo contínuo de varredura sem congelamentos do feixe analógico[cite: 1, 7].
* **RNF02 - Economia de Memória Interna:** Utilização de resolução lógica de 320×240 pixels (upscaling físico 2×2) para viabilizar armazenamento direto em blocos M10K.
* **RNF03 - Determinismo em Hardware:** Eliminação de blocos divisores e multiplicadores síncronos pesados nas rotinas de endereçamento.

---

## 4. Especificação do Hardware

* **Placa de Testes:** Terasic DE1-SoC (FPGA Intel Cyclone V SoC `5CSEMA5F31C6N`).
* **Conversor Digital-Analógico (DAC):** ADV7123 (Triplo DAC de vídeo RGB888).
* **Interface de Saída:** Conector analógico padrão VGA DB15.
* **Clock de Entrada:** Oscilador base de 50 MHz da placa (gerando clock interno de pixel de 25 MHz).

---

## 5. Arquitetura e Decisões de Projeto

### 5.1 Visão Geral dos Módulos

* **`gpu_de1_soc_top`:** Módulo integrador dos barramentos, divisores de clock e pinos externos.
* **`vga_sync`:** Gerador dos sinais de sincronismo (`HSYNC`/`VSYNC`) e das coordenadas de varredura lógicas $(X, Y)$.
* **`cmd_decoder`:** Unidade de controle e decodificação das palavras de 32 bits.
* **`bg_engine` / `tilemap_ram` / `pattern_vram`:** Subsistema de recuperação e cálculo de endereços do plano de fundo.
* **`polygon_rasterizer` / `polygon_buffer`:** ULA de funções de aresta com memória Dual-Port para primitivas geométricas.
* **`compositor` & `color_palette`:** Arbitragem de prioridade das três camadas e tabela de conversão CLUT para saída RGB.

### 5.2 Diagrama em Blocos

<!-- ESPAÇO PARA O DIAGRAMA ARQUITETURAL -->
> **Figura 1: Diagrama Estrutural do Coprocessador Gráfico**
> 
> ```
>        [ Instrução 32-bit (cmd_data) ]
>                       │
>                       ▼
>            ┌─────────────────────┐
>            │ cmd_decoder (FSM)   │
>            └──────────┬──────────┘
>                       │
>         ┌─────────────┼─────────────┬─────────────┐
>         ▼             ▼             ▼             ▼
>   ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
>   │  Pattern  │ │  Tilemap  │ │  Sprite   │ │Polygon    │
>   │   VRAM    │ │   VRAM    │ │   OAM     │ │Rasterizer │
>   └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
>         │             │             │             │
>         └──────┬──────┘             │             ▼
>                │                    │       ┌───────────┐
>                ▼                    │       │  Polygon  │
>         ┌─────────────┐             │       │  Buffer   │
>         │  bg_engine  │             │       └─────┬─────┘
>         └──────┬──────┘             │ (Pixel SP)  │ (Pixel Poly)
>                │ (Pixel BG)         │             │
>                └────────────┬───────┴─────────────┘
>                             ▼
>                     ┌───────────────┐     ┌──────────────┐
>                     │  compositor   │ ◄───┤   vga_sync   │
>                     └───────┬───────┘     └──────────────┘
>                             │ (Índice 8-bit)
>                             ▼
>                     ┌───────────────┐
>                     │ color_palette │
>                     └───────┬───────┘
>                             │ (RGB 24-bit)
>                             ▼
>                      [ DAC ADV7123 ] ──► Conector VGA
> ```
> *(Diagrama sequencial dos módulos do projeto)*

### 5.3 Conjunto de Instruções Customizado 

Formato: `[31:28]` Opcode. Os campos restantes dependem da instrucao, conforme
a tabela. Os comandos genericos de sprites usam ID de 5 bits em `[27:23]`.

| Opcode | Mnemônico | Formato dos Bits [27:0] | Descrição |
| :--- | :--- | :--- | :--- |
| `0x0` | `CLEAR_SCREEN` | `[27:24]=0xF`, `[23:0]=0` | Limpa a camada de polígonos com índice zero. |
| `0x1` | `SET_PALETTE` | `[23:16]=Addr`, `[15:0]=RGB565` | Carrega cor na tabela de paleta. |
| `0x3` | `WRITE_TILEMAP` | `[21:16]=X`, `[12:8]=Y`, `[7:0]=TileID` | Escreve uma célula no mapa de fundo. |
| `0x5` | `SET_SCROLL` | `[16:8]=Scroll_X`, `[7:0]=Scroll_Y` | Ajusta o deslocamento do fundo. |
| `0x6` | `UPDATE_BIRD_Y` | `[7:0]=Y` | Atualiza o sprite 0, com X=152, tile=1 e espelhamentos desativados. |
| `0x7` | `DRAW_TRI_V1` | `[16:8]=X0`, `[7:0]=Y0` | Grava vértice $V_0$ do triângulo. |
| `0x8` | `DRAW_TRI_V2` | `[16:8]=X1`, `[7:0]=Y1` | Grava vértice $V_1$ do triângulo. |
| `0x9` | `DRAW_TRI_V3` | `[27:20]=Cor`, `[16:8]=X2`, `[7:0]=Y2` | Grava vértice $V_2$ e dispara o rasterizador. |
| `0xA` | `SET_SPRITE_POS` | `[27:23]=ID`, `[22:14]=X`, `[13:6]=Y`, `[5:0]=0` | Altera a posicao de qualquer sprite, preservando seus atributos. |
| `0xB` | `SET_SPRITE_ATTR` | `[27:23]=ID`, `[22:15]=TileID`, `[14]=Enable`, `[13]=FlipH`, `[12]=FlipV`, `[11:0]=0` | Altera imagem, habilitacao e espelhamentos, preservando a posicao. |
| `0xF` | `HALT` | Campos restantes zero; palavra `F0000000` | Na busca ativa, para o programa sem interromper o VGA. |

Esta tabela descreve o RTL atual. `HALT` e interpretado pelo controlador de busca ativa e nao e
enviado ao decodificador grafico. A ISA completa do Problema 2 sera definida
gradualmente; os registradores de parametros atuais nao substituem seu futuro
banco de registradores.

### 5.4 Justificativa das Decisões Adotadas
Palavra de Instrução de 32 bits:**  
  Adotou-se uma ISA customizada orientada a comandos gráficos com largura fixa de 32 bits e opcode em `[31:28]`. Os outros campos variam por instrucao para acomodar coordenadas, cores e IDs. Para operações que excedem 32 bits, como os três vértices de um triângulo e sua cor, o protocolo utiliza instruções sequenciais com registradores internos que retêm os vértices parciais até a chegada da instrução de disparo.
* **Downscaling Lógico para 320×240:** Reduz a necessidade de armazenamento de quadros e buffers em 75%, permitindo o uso exclusivo de memória SRAM interna da FPGA.

* **Indexação por Deslocamento de Bits:** O mapeamento linear `Addr = Y * 320 + X` foi estruturado via somadores `(Y << 8) + (Y << 6) + X`, eliminando o consumo de blocos multiplicadores DSP dedicados.

* **Acesso Desacoplado no Framebuffer:** Memórias de porta dupla (Dual-Port) separam as operações assíncronas de escrita das rotinas contínuas de leitura do feixe de vídeo
## 6. Metodologia de Testes e Validação

### 6.1 Simulação do circuito e Testes Manuais
A validação e os testes realizados para verificar a sequência de instruções e operações realizadas foram feitas através de recursos da plana como botões e chaves.
Para simular uma entrada de comando 
* **Validação dos Sinais de Sincronismo:** Foram simuladas as contagens horizontais (0 a 799) e verticais (0 a 524) no `vga_sync`, comprovando a largura e polaridade dos pulsos de `HSYNC`, `VSYNC` e intervalos de *Blanking* em conformidade com o padrão VESA.
* **Testes Manuais do Decodificador:** Foram elaborados testbenches com injeção sequencial de palavras de 32 bits para verificar a extração de parâmetros dos opcodes (como `WRITE_TILEMAP`, `SET_SCROLL` e montagem de vértices geométricos), acompanhando a transição correta dos registradores de retenção (*hold registers*).
* **Composição de Camadas e Prioridade:** Vetores de teste com pixels simultâneos no fundo, sprites e polígonos validaram que o índice `0x00` mantém transparência e que elementos geométricos e sprites sobrepõem o cenário corretamente.

### 6.2 Validação Visual da Saída VGA (Verilator)
Para complementar os testes em formas de onda, foi utilizada uma rotina auxiliar de co-simulação baseada em **Verilator**. O módulo sintetizado foi compilado diretamente para ambiente C++, permitindo amostrar os sinais de saída analógica `VGA_R`, `VGA_G`, `VGA_B`, `HSYNC` e `VSYNC` ciclo a ciclo e reconstruir o quadro de vídeo visualmente antes da programação na placa de desenvolvimento[cite: 3].

---

## 7. Apresentação dos Resultados

### 7.1 Resultados de Simulação
O armazenamento dos elementos gráficos foi estruturado dividindo as matrizes visuais da lógica de posicionamento. Os padrões gráficos de $8\times8$ pixels para o cenário e os blocos de $16\times16$ pixels dos sprites foram desenhados em imagens indexadas de 8 bits e convertidos para o arquivo tiles.hex (ou sprites_data.hex), o qual é carregado na memória de padrões pattern_vram.v durante a síntese por meio da diretiva $readmemh. Em paralelo, o mapa de fundo é definido no arquivo tilemap_data.hex (ou tilemap_init.hex), contendo uma grade de $40\times30$ posições com os identificadores dos blocos (Tile IDs) inicializados na tilemap_ram.v. Durante a varredura VGA, o módulo bg_engine.v consulta a matriz de blocos e indexa a pattern_vram.v em tempo real (on-the-fly), enquanto os atributos dinâmicos dos objetos móveis (como coordenadas $X,Y$ e identificador do padrão) são gerenciados na tabela de controle da memória OAM (sprite_oam.v).
As simulações confirmaram a estabilidade do sincronismo e o correto acionamento dos módulos de renderização sob recepção de comandos de 32 bits. 

A mecânica do jogo já pôde ser implementada e a simulação do comando para ativar a sprite principal do jogo foi adaptada na placa. Dessa forma, foi possível simular a movimentação e renderização em tempo real mesmo sendo em nível de hardware.

### 7.2 Demonstração em Hardware
O circuito foi sintetizado no Intel Quartus Prime e a imagem gerada manteve sincronismo estável a 60 Hz, suficiente para visualização da movimentação das sprites e do background.
Os push buttons da placa foram utilizados com a finalidade de testar o funcionamento do circuito. O botão KEY1 é responsável pelo pulo do personagem, enquanto os botões KEY2 e KEY3 desenham um triângulo e um retângulo no centro da tela, respectivamente, para demonstrar o funcionamento do rasterizador de polígonos. Também há o botão KEY0, utilizado para representar um "reset" no jogo, preparando-o para a próxima etapa do produto.

<!-- ESPAÇO PARA FOTOS DO CIRCUITO FÍSICO -->
Imagem Exibida no Monitor VGA 

<img width="388" height="217" alt="image" src="https://github.com/user-attachments/assets/1fb03705-2e35-4b36-98c0-8fe2694bb123" /> 

  *Figura 1: Saída gráfica estável no monitor externo.* 


---

## 8. Limitações, Gargalos e Itens Não Atendidos

Com base no escopo e no ciclo de desenvolvimento, sintetizam-se as funcionalidades que não foram integralmente concluídas:

* **Validacao fisica dos sprites genericos:** Posicao, imagem, habilitacao e espelhamentos dos 32 sprites estao integrados e possuem testes de simulacao na etapa 2. A nova versao ainda precisa ser sintetizada e testada na placa.
* **Prioridade e transparencia entre sprites:** A prioridade permanece fixa pelo menor ID. A selecao ainda ocorre antes da leitura da cor; um pixel transparente do sprite escolhido nao revela outro sprite inferior. Esses ajustes pertencem a uma proxima etapa.
* **Mudança da paleta de cores das sprites:** A seleção e comutação dinâmica de sub-paletas de cores para instâncias específicas de sprites não foram conectadas ao estágio de composição final.
* **Validacao geral do rasterizador de polígonos:** O motor aceita vertices parametrizados, mas os testes automatizados atuais ainda nao cobrem todos os formatos, limites e casos degenerados de triangulos e retangulos.

---

## 9. Conclusão

O projeto atendeu aos objetivos centrais de implementação de um coprocessador gráfico dedicado em FPGA. A integração entre os geradores de sincronismo VGA, o decodificador de palavras de 32 bits, o motor de plano de fundo em *Tilemap* e o compositor de camadas com paleta CLUT permitiu a geração estável de sinal de vídeo analógico[cite: 1, 2, 7]. A metodologia apoiada em simulações manuais no ModelSim e validações complementares assegurou a consistência do circuito antes da síntese e validação física na placa de testes.

---

## 10. Referências

1. INTEL. *Cyclone V Device Handbook: Volume 1: Device Interfaces and Integration*, 2020.
2. TERASIC. *DE1-SoC User Manual*, Terasic Technologies Inc., Rev. F, 2019.
3. PINEDA, Juan. *A Parallel Approach to Polygon Rasterization*. In: ACM SIGGRAPH Computer Graphics, 1988.
4. VESA. *VESA and Industry Standards and Guidelines for Computer Display Monitor Timing (DMT)*, Version 1.0, Rev. 0.8, 1998.
