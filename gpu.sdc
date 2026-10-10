# Clock externo da DE1-SoC: 50 MHz. Nao usar o periodo automatico de 1 ns.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Nome real do divisor no RTL. Falhar se nao encontrado evita analise enganosa.
set pixel_divider [get_registers {*|clk_25m}]
if {[get_collection_size $pixel_divider] != 1} {
    error "gpu.sdc: esperado um registro clk_25m; confira o netlist e o nome do divisor."
}
create_generated_clock -name CLK_25M -source [get_ports {CLOCK_50}] \
    -divide_by 2 $pixel_divider

# Clock encaminhado para a interface VGA, relacionado ao mesmo CLOCK_50.
create_generated_clock -name VGA_FORWARD -source [get_ports {CLOCK_50}] \
    -divide_by 2 [get_ports {VGA_CLK}]
derive_clock_uncertainty

# KEY[0] e reset externo assincrono. Esta excecao nao garante liberacao
# segura: verificar reset/recovery/removal na bancada (ver docs).
set_false_path -from [get_ports {KEY[0]}]

# Os botoes do modo demonstracao entram no primeiro estagio dos
# sincronizadores. Nao excluir o caminho entre primeiro e segundo estagio.
# No modo de busca ativa esses registradores nao sao instanciados.
set first_key_sync [get_registers {*|key1_sync[0] *|key2_sync[0] *|key3_sync[0]}]
if {[get_collection_size $first_key_sync] > 0} {
    set_false_path -from [get_ports {KEY[1] KEY[2] KEY[3]}] -to $first_key_sync
}

# SW atualmente participa somente de indicacao por LED (sem receptor
# sincrono externo). Rever caso as chaves sejam usadas por novo datapath.
set_false_path -from [get_ports {SW[*]}]
set_false_path -to [get_ports {LEDR[*]}]

# RESTRICOES EXTERNAS PROVISORIAS: analisar os caminhos de saida sem
# false_path, mas nao declarar signoff fisico com estes valores.
# 0 ns assume amostragem ideal no pino FPGA; deve ser substituido pelos
# requisitos setup/hold e diferenca das trilhas da placa/receptor real.
# Veja docs/validacao-fisica-pbl1.md para as equacoes e evidencias requeridas.
set vga_outputs [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N}]
set_output_delay -clock VGA_FORWARD -max 0.000 $vga_outputs
set_output_delay -clock VGA_FORWARD -min 0.000 $vga_outputs
