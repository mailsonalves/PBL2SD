# Componente customizado para Platform Designer / Quartus Prime.
# Nao define HPS, DDR, pinout ou endereco fisico: isso pertence ao sistema da placa.
package require qsys

set_module_property NAME pbl2_gpu
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "GPU PBL2 (active fetch and program upload)"
set_module_property GROUP "PBL2SD"
set_module_property AUTHOR "PBL2SD"
set_module_property DESCRIPTION "32-bit graphics coprocessor with a 64-byte Avalon-MM control/program interface"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false
set_module_property ANALYZE_HDL false

set pbl2_source_root [file normalize [file join [file dirname [info script]] ..]]

# Um callback comum preserva os caminhos dos assets usados por $readmemh.
proc pbl2_gpu_files {fileset_name} {
    global pbl2_source_root
    set sources {
        gpu_avalon.v gpu_core.v gpu_mmio.v instruction_memory.v
        active_fetch_controller.v gpu_instruction_decoder.v gpu_register_file.v
        gpu_alu.v gpu_datapath.v board_input_controller.v cmd_decoder.v
        bg_engine.v tilemap_ram.v pattern_vram.v sprite_engine.v
        polygon_rasterizer.v raster_alu.v polygon_buffer.v compositor.v
        color_palette.v vga_sync.v
    }
    foreach source $sources {
        set path [file join $pbl2_source_root $source]
        if {$source eq "gpu_avalon.v"} {
            add_fileset_file $source VERILOG PATH $path TOP_LEVEL_FILE
        } else {
            add_fileset_file $source VERILOG PATH $path
        }
    }
    foreach asset {
        tiles.hex tilemap_data.hex palette.hex
        programs/background_motion.hex programs/background_sprites.hex programs/polygons_motion.hex
        programs/program_a.hex programs/program_b.hex
        programs/fetch_demo.hex programs/sprites_demo.hex programs/pbl1_validation.hex
    } {
        add_fileset_file $asset OTHER PATH [file join $pbl2_source_root $asset]
    }
}

add_fileset synthesis QUARTUS_SYNTH pbl2_gpu_files
set_fileset_property synthesis TOP_LEVEL gpu_avalon
add_fileset simulation SIM_VERILOG pbl2_gpu_files
set_fileset_property simulation TOP_LEVEL gpu_avalon

add_parameter PROGRAM_WORDS INTEGER 256
set_parameter_property PROGRAM_WORDS DISPLAY_NAME "Instruction-memory capacity (words)"
set_parameter_property PROGRAM_WORDS ALLOWED_RANGES {1:256}
set_parameter_property PROGRAM_WORDS HDL_PARAMETER true
add_parameter PROGRAM_FILE STRING "programs/background_motion.hex"
set_parameter_property PROGRAM_FILE DISPLAY_NAME "Initial program HEX (relative to project)"
set_parameter_property PROGRAM_FILE HDL_PARAMETER true

add_interface clock clock end
add_interface_port clock clk clk Input 1
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface control avalon end
set_interface_property control associatedClock clock
set_interface_property control associatedReset reset
set_interface_property control addressUnits SYMBOLS
set_interface_property control bitsPerSymbol 8
set_interface_property control explicitAddressSpan 64
set_interface_property control readLatency 0
set_interface_property control maximumPendingReadTransactions 0
set_interface_property control readWaitTime 0
set_interface_property control writeWaitTime 0
set_interface_property control setupTime 0
set_interface_property control holdTime 0
set_interface_property control timingUnits Cycles
add_interface_port control address address Input 6
add_interface_port control read read Input 1
add_interface_port control write write Input 1
add_interface_port control writedata writedata Input 32
add_interface_port control byteenable byteenable Input 4
add_interface_port control readdata readdata Output 32
add_interface_port control waitrequest waitrequest Output 1

add_interface board conduit end
set_interface_property board associatedClock clock
set_interface_property board associatedReset reset
add_interface_port board KEY key Input 4
add_interface_port board SW switches Input 10
add_interface_port board LEDR leds Output 10

add_interface vga conduit end
set_interface_property vga associatedClock clock
set_interface_property vga associatedReset reset
add_interface_port vga VGA_HS hs Output 1
add_interface_port vga VGA_VS vs Output 1
add_interface_port vga VGA_R r Output 8
add_interface_port vga VGA_G g Output 8
add_interface_port vga VGA_B b Output 8
add_interface_port vga VGA_BLANK_N blank_n Output 1
add_interface_port vga VGA_SYNC_N sync_n Output 1
add_interface_port vga VGA_CLK pixel_clk Output 1
