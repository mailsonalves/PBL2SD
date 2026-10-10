# Executar com qsys-script, da raiz do projeto preparado.
# Parametros DDR/pinos: referencia DE1-SoC FPGAacademy, MIT (reference.json).
package require qsys

create_system pbl2_hps_system
set_project_property DEVICE_FAMILY "Cyclone V"
set_project_property DEVICE "5CSEMA5F31C6"

add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency 50000000
set_instance_parameter_value clk_0 clockFrequencyKnown true
set_instance_parameter_value clk_0 resetSynchronousEdges "NONE"

add_instance ARM_A9_HPS altera_hps
source [file join [file dirname [info script]] de1_soc_hps_parameters.tcl]
# A GPU requer somente a ponte lightweight. As outras pontes da referencia
# ficam sem masters/slaves conectados; seus clocks permanecem definidos.
set_instance_parameter_value ARM_A9_HPS LWH2F_Enable true
set_instance_parameter_value ARM_A9_HPS F2SINTERRUPT_Enable false

add_instance gpu pbl2_gpu 1.0
set_instance_parameter_value gpu PROGRAM_WORDS 256
set_instance_parameter_value gpu PROGRAM_FILE "programs/background_motion.hex"

foreach sink {ARM_A9_HPS.h2f_axi_clock ARM_A9_HPS.f2h_axi_clock ARM_A9_HPS.h2f_lw_axi_clock gpu.clock} {
    add_connection clk_0.clk $sink
}
# O reset externo e o reset enviado pelo HPS sao combinados/sincronizados
# pelo controlador de reset gerado pelo Platform Designer.
add_connection clk_0.clk_reset gpu.reset
add_connection ARM_A9_HPS.h2f_reset gpu.reset

add_connection ARM_A9_HPS.h2f_lw_axi_master gpu.control
set_connection_parameter_value ARM_A9_HPS.h2f_lw_axi_master/gpu.control baseAddress 0x00000000
set_connection_parameter_value ARM_A9_HPS.h2f_lw_axi_master/gpu.control arbitrationPriority 1
set_connection_parameter_value ARM_A9_HPS.h2f_lw_axi_master/gpu.control defaultConnection false

set_interface_property clk EXPORT_OF clk_0.clk_in
set_interface_property reset EXPORT_OF clk_0.clk_in_reset
set_interface_property memory EXPORT_OF ARM_A9_HPS.memory
set_interface_property hps_io EXPORT_OF ARM_A9_HPS.hps_io
set_interface_property gpu_board EXPORT_OF gpu.board
set_interface_property gpu_vga EXPORT_OF gpu.vga

save_system pbl2_hps_system.qsys
puts "Sistema salvo: pbl2_hps_system.qsys (GPU offset0 na ponte lightweight)"
