# Etapa 5 — inicialização das memórias no Quartus

Branch `pbl2/etapa5-correcao-memorias-quartus`, baseada na etapa 4 (`b9c57a9`).

## Falha observada e evidência

Na placa apareciam polígonos, mas textos e sprites não apareciam. O relatório
`gpu.map.rpt` enviado pelo usuário corresponde à galeria: núcleo programável e
SHOWCASE habilitados, programa de 2.626 palavras e Quartus Lite 25.1.

O relatório registra `Warning (10850): number of words (0) in memory file`
nas inicializações de tilemap, sprite ROM, pattern VRAM e paleta. Também registra
`Warning (127007)` substituindo valores indefinidos por zeros nos padrões e
sprites. A síntese terminou com zero erros, mas essas memórias não receberam
os dados esperados.

Textos e sprites usam `assets/showcase_tiles.hex`. Os polígonos são desenhados
pelo rasterizador; a galeria escreve a paleta durante a execução. Isso explica
por que polígonos coloridos podiam aparecer com a ROM de imagens vazia.

## Correção

O nome do arquivo era convertido para um vetor de 256 bytes, usado em
`$readmemh`. Essa adaptação passou no Icarus/Yosys, mas o Quartus não carregou
os dados. Agora apenas o Icarus, identificado por sua macro `__ICARUS__`, usa
essa conversão. Quartus, Verilator e Yosys recebem o parâmetro string original,
como já ocorre na memória de instruções.

A RAM do tilemap também passa a usar somente o HEX completo para sua
inicialização. Foi removido o loop que zerava a mesma memória: a nova conferência
do netlist encontrou os zeros prevalecendo sobre o arquivo na síntese Yosys.

`scripts/check_memory_init.py` compara todas as palavras das memórias de
padrões, sprites, tilemap, paleta e programa com os HEX de origem no netlist
estrutural Yosys. O precheck agora interrompe a execução se os dados estiverem
ausentes, indefinidos ou diferentes. Caches e framebuffers, inicializados em
execução, não entram nessa comparação.

O script de compilação Quartus também confere `gpu.map.rpt` usando
`scripts/check_quartus_memory.py`. Os avisos de zero palavras ou dados
indefinidos das memórias gráficas fazem o script retornar erro, mesmo quando
o comando de compilação do Quartus retorna sucesso. Isso não aprova timing
nem substitui a observação na placa. Pela interface gráfica, essa conferência
deve ser feita manualmente ou executando o verificador no relatório novo.

## Verificação e repetição na placa

Passaram os 25 testbenches RTL e 11 testes Python, incluindo a galeria de oito
telas, a comparação de RGB/sincronismo em 6.720.000 ciclos e as verificações
de inicialização em quatro estados com Icarus. A síntese Yosys da galeria
preservou exatamente as 36.850 palavras dos cinco arquivos de memória e
estimou 226 M10K, 2.582 flip-flops e 4.029 LUTs. A conferência estrutural das
memórias também passou nos modos legado e busca ativa.

Os verificadores rejeitaram dados alterados/indefinidos no netlist e o relatório
Quartus enviado, que contém as memórias vazias. Quartus não está instalado na
nuvem; a recompilação desta correção e a verificação física permanecem necessárias.

1. Abra `gpu.qpf` desta branch, mantendo `assets/` e `programs/` junto ao projeto.
2. Use **Project → Clean Project**, depois **Processing → Start Compilation**.
   Pelo script, `bash scripts/synth_quartus.sh` já cria uma cópia nova isolada.
3. Confira que não existem os avisos 10850 de **zero palavras** nem 127007
   relativos às ROMs de padrões/sprites. Arquivos completos esperados:
   padrões 16.384 bytes, tilemap 1.200 bytes e paleta 256 palavras de 24 bits.
4. Grave o novo `output_files/gpu.sof` no Programmer e pressione/solte KEY0.
5. Com SW9=0, selecione tela 1 (SW2:0=001): devem aparecer textos e 32 sprites.
   Selecione tela 2 (010): devem aparecer as quatro setas espelhadas.

Um novo relatório sem os avisos de memória e a presença dos textos/sprites na
placa são as evidências necessárias para aprovar esta correção no Quartus.
