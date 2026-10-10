# Adaptado da referencia DE1-SoC FPGAacademy (MIT).
# Design_Examples, commit 13010c09f4863447994f0435fef80e162a40d24b.
# Parametros comuns primeiro; ajustes DDR/GPIO da DE1-SoC depois.
# Consulte reference.json e LICENSE.fpgacademy.

set_instance_parameter_value ARM_A9_HPS CTL_ENABLE_BURST_INTERRUPT						true
set_instance_parameter_value ARM_A9_HPS CTL_ENABLE_BURST_TERMINATE						true
set_instance_parameter_value ARM_A9_HPS EMAC1_Mode										"RGMII"
set_instance_parameter_value ARM_A9_HPS EMAC1_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS F2SCLK_COLDRST_Enable							false
set_instance_parameter_value ARM_A9_HPS F2SCLK_DBGRST_Enable							false
set_instance_parameter_value ARM_A9_HPS F2SCLK_WARMRST_Enable							false
set_instance_parameter_value ARM_A9_HPS F2SDRAM_Type									""
set_instance_parameter_value ARM_A9_HPS F2SDRAM_Width									""
set_instance_parameter_value ARM_A9_HPS F2SINTERRUPT_Enable								true
set_instance_parameter_value ARM_A9_HPS FPGA_PERIPHERAL_OUTPUT_CLOCK_FREQ_EMAC0_GTX_CLK	100.0
set_instance_parameter_value ARM_A9_HPS FPGA_PERIPHERAL_OUTPUT_CLOCK_FREQ_EMAC1_GTX_CLK	100.0
set_instance_parameter_value ARM_A9_HPS FPGA_PERIPHERAL_OUTPUT_CLOCK_FREQ_EMAC0_MD_CLK	100.0
set_instance_parameter_value ARM_A9_HPS FPGA_PERIPHERAL_OUTPUT_CLOCK_FREQ_EMAC1_MD_CLK	100.0
set_instance_parameter_value ARM_A9_HPS I2C0_Mode										"I2C"
set_instance_parameter_value ARM_A9_HPS I2C0_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS I2C1_Mode										"I2C"
set_instance_parameter_value ARM_A9_HPS I2C1_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS MAX_PENDING_RD_CMD								16
set_instance_parameter_value ARM_A9_HPS MAX_PENDING_WR_CMD								8
set_instance_parameter_value ARM_A9_HPS MEM_CLK_FREQ									400.0
set_instance_parameter_value ARM_A9_HPS MEM_CLK_FREQ_MAX								800.0
set_instance_parameter_value ARM_A9_HPS MEM_COL_ADDR_WIDTH								10
set_instance_parameter_value ARM_A9_HPS MEM_DQ_WIDTH									32
set_instance_parameter_value ARM_A9_HPS MEM_DRV_STR										"RZQ/6"
set_instance_parameter_value ARM_A9_HPS MEM_ROW_ADDR_WIDTH								15
set_instance_parameter_value ARM_A9_HPS MEM_RTT_NOM										"RZQ/6"
set_instance_parameter_value ARM_A9_HPS MEM_RTT_WR										"Dynamic ODT off"
set_instance_parameter_value ARM_A9_HPS MEM_TINIT_US									500
set_instance_parameter_value ARM_A9_HPS MEM_TMRD_CK										4
set_instance_parameter_value ARM_A9_HPS MEM_TREFI_US									7.8
set_instance_parameter_value ARM_A9_HPS MEM_TWTR										4
set_instance_parameter_value ARM_A9_HPS MEM_WTCL										7
set_instance_parameter_value ARM_A9_HPS MPU_EVENTS_Enable								false
set_instance_parameter_value ARM_A9_HPS REF_CLK_FREQ									25
set_instance_parameter_value ARM_A9_HPS SDIO_Mode										"4-bit Data"
set_instance_parameter_value ARM_A9_HPS SDIO_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS SPIM1_Mode										"Single Slave Select"
set_instance_parameter_value ARM_A9_HPS SPIM1_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS STM_Enable										true
set_instance_parameter_value ARM_A9_HPS UART0_Mode										"No Flow Control"
set_instance_parameter_value ARM_A9_HPS UART0_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS USB1_Mode										"SDR"
set_instance_parameter_value ARM_A9_HPS USB1_PinMuxing									"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS desired_mpu_clk_mhz								800.0
set_instance_parameter_value ARM_A9_HPS use_default_mpu_clk								true
set_instance_parameter_value ARM_A9_HPS GPIO_Enable [list No No No No No No No No No Yes No No No No No No No No No No No No No No No No No No No No No No No No No Yes No No No No Yes Yes No No No No No No Yes No No No No Yes Yes No No No No No No Yes No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No No]
set_instance_parameter_value ARM_A9_HPS MEM_TCL								7
set_instance_parameter_value ARM_A9_HPS MEM_TFAW_NS							45.0
set_instance_parameter_value ARM_A9_HPS MEM_TRAS_NS							36.0
set_instance_parameter_value ARM_A9_HPS MEM_TRCD_NS							13.125
set_instance_parameter_value ARM_A9_HPS MEM_TRFC_NS							300.0
set_instance_parameter_value ARM_A9_HPS MEM_TRP_NS							13.125
set_instance_parameter_value ARM_A9_HPS MEM_VENDOR							"Micron"
set_instance_parameter_value ARM_A9_HPS QSPI_Mode							"1 SS"
set_instance_parameter_value ARM_A9_HPS QSPI_PinMuxing						"HPS I/O Set 0"
set_instance_parameter_value ARM_A9_HPS S2F_Width							3
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_AC_SKEW				0.02
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_AC_TO_CK_SKEW			0.01
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_DQ_TO_DQS_SKEW			0.05
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_MAX_CK_DELAY			0.03
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_MAX_DQS_DELAY			0.02
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_SKEW_BETWEEN_DIMMS		0.05
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_SKEW_BETWEEN_DQS		0.06
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_SKEW_CKDQS_DIMM_MAX	0.12
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_SKEW_CKDQS_DIMM_MIN	0.06
set_instance_parameter_value ARM_A9_HPS TIMING_BOARD_SKEW_WITHIN_DQS		0.01
set_instance_parameter_value ARM_A9_HPS TIMING_TDH							65
set_instance_parameter_value ARM_A9_HPS TIMING_TDQSCK						255
set_instance_parameter_value ARM_A9_HPS TIMING_TDQSQ						125
set_instance_parameter_value ARM_A9_HPS TIMING_TDS							30
set_instance_parameter_value ARM_A9_HPS TIMING_TIH							140
set_instance_parameter_value ARM_A9_HPS TIMING_TIS							190
set_instance_parameter_value ARM_A9_HPS TIMING_TQSH							0.4
