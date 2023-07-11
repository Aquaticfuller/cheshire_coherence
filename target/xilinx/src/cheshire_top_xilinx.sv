// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Nicole Narr <narrn@student.ethz.ch>
// Christopher Reinwardt <creinwar@student.ethz.ch>
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>

`include "cheshire/typedef.svh"
`include "phy_definitions.svh"

module cheshire_top_xilinx
  import cheshire_pkg::*;
(
`ifdef USE_RESET
  input logic         cpu_reset,
`endif
`ifdef USE_RESETN
  input logic         cpu_resetn,
`endif

`ifdef USE_SWITCHES
  input logic         testmode_i,
  input logic [1:0]   boot_mode_i,
`endif

`ifdef USE_JTAG
  input logic         jtag_tck_i,
  input logic         jtag_tms_i,
  input logic         jtag_tdi_i,
  output logic        jtag_tdo_o,
`ifdef USE_JTAG_TRSTN
  input logic         jtag_trst_ni,
`endif
`ifdef USE_JTAG_VDDGND
  output logic        jtag_vdd_o,
  output logic        jtag_gnd_o,
`endif
`endif

`ifdef USE_I2C
  inout wire          i2c_scl_io,
  inout wire          i2c_sda_io,
`endif

`ifdef USE_SD
  input logic         sd_cd_i,
  output logic        sd_cmd_o,
  inout wire  [3:0]   sd_d_io,
  output logic        sd_reset_o,
  output logic        sd_sclk_o,
`endif

`ifdef USE_FAN
  input logic [3:0]   fan_sw,
  output logic        fan_pwm,
`endif

`ifdef USE_VGA
  // VGA Colour signals
  output logic [4:0]  vga_b,
  output logic [5:0]  vga_g,
  output logic [4:0]  vga_r,
  // VGA Sync signals
  output logic        vga_hs,
  output logic        vga_vs,
`endif

`ifdef USE_SERIAL
  // DDR Link
  output logic [4:0]  ddr_link_o,
  output logic        ddr_link_clk_o,
`endif

  // Phy interface for DDR4
`ifdef USE_DDR4
  `DDR4_INTF
`endif

`ifdef USE_DDR3
  `DDR3_INTF
`endif

  output logic        uart_tx_o,
  input logic         uart_rx_i

);

  // Configure cheshire for FPGA mapping
  localparam cheshire_cfg_t FPGACfg = '{
    // CVA6 parameters
    Cva6RASDepth      : ariane_pkg::ArianeDefaultConfig.RASDepth,
    Cva6BTBEntries    : ariane_pkg::ArianeDefaultConfig.BTBEntries,
    Cva6BHTEntries    : ariane_pkg::ArianeDefaultConfig.BHTEntries,
    Cva6NrPMPEntries  : 0,
    Cva6ExtCieLength  : 'h2000_0000,
    // Harts
    DualCore          : 0,  // Only one core, but rest of config allows for two
    CoreMaxTxns       : 8,
    CoreMaxTxnsPerId  : 4,
    // Interconnect
    AddrWidth         : 48,
    AxiDataWidth      : 64,
    AxiUserWidth      : 2,  // Convention: bit 0 for core(s), bit 1 for serial link
    AxiMstIdWidth     : 2,
    AxiMaxMstTrans    : 8,
    AxiMaxSlvTrans    : 8,
    AxiUserAmoMsb     : 1,
    AxiUserAmoLsb     : 0,
    RegMaxReadTxns    : 8,
    RegMaxWriteTxns   : 8,
    RegAmoNumCuts     : 1,
    RegAmoPostCut     : 1,
    // RTC
    RtcFreq           : 1000000,
    // Features
    Bootrom           : 1,
    Uart              : 1,
    I2c               : 1,
    SpiHost           : 1,
    Gpio              : 1,
    Dma               : 1,
    SerialLink        : 0,
    Vga               : 1,
    // Debug
    DbgIdCode         : CheshireIdCode,
    DbgMaxReqs        : 4,
    DbgMaxReadTxns    : 4,
    DbgMaxWriteTxns   : 4,
    DbgAmoNumCuts     : 1,
    DbgAmoPostCut     : 1,
    // LLC: 128 KiB, up to 2 GiB DRAM
    LlcNotBypass      : 1,
    LlcSetAssoc       : 8,
    LlcNumLines       : 256,
    LlcNumBlocks      : 8,
    LlcMaxReadTxns    : 8,
    LlcMaxWriteTxns   : 8,
    LlcAmoNumCuts     : 1,
    LlcAmoPostCut     : 1,
    LlcOutConnect     : 1,
    LlcOutRegionStart : 'h8000_0000,
    LlcOutRegionEnd   : 'h1_0000_0000,
    // VGA: RGB332
    VgaRedWidth       : 5,
    VgaGreenWidth     : 6,
    VgaBlueWidth      : 5,
    VgaHCountWidth    : 24, // TODO: Default is 32; is this needed?
    VgaVCountWidth    : 24, // TODO: See above
    // Serial Link: map other chip's lower 32bit to 'h1_000_0000
    SlinkMaxTxnsPerId : 4,
    SlinkMaxUniqIds   : 4,
    SlinkMaxClkDiv    : 1024,
    SlinkRegionStart  : 'h1_0000_0000,
    SlinkRegionEnd    : 'h2_0000_0000,
    SlinkTxAddrMask   : 'hFFFF_FFFF,
    SlinkTxAddrDomain : 'h0000_0000,
    SlinkUserAmoBit   : 1,  // Upper atomics bit for serial link
    // DMA config
    DmaConfMaxReadTxns  : 4,
    DmaConfMaxWriteTxns : 4,
    DmaConfAmoNumCuts   : 1,
    DmaConfAmoPostCut   : 1,
    // GPIOs
    GpioInputSyncs    : 1,
    // All non-set values should be zero
    default: '0
  };

  localparam cheshire_cfg_t CheshireFPGACfg = FPGACfg;
  `CHESHIRE_TYPEDEF_ALL(, CheshireFPGACfg)

  axi_llc_req_t axi_llc_mst_req;
  axi_llc_rsp_t axi_llc_mst_rsp;

  `ifdef USE_RESET
  logic cpu_resetn;
  assign cpu_resetn = ~cpu_reset;
  `elsif USE_RESETN
  logic cpu_reset;
  assign cpu_reset  = ~cpu_resetn;
  `endif
  logic sys_rst;

  (* dont_touch = "yes" *) wire dram_clock_out; // 200 MHz
  (* dont_touch = "yes" *) wire dram_sync_reset;
  (* dont_touch = "yes" *) wire soc_clk;
  (* dont_touch = "yes" *) wire rst_n;

  ///////////////////
  // VIOs          // 
  ///////////////////
  
`ifdef USE_VIO
  logic vio_reset;
  xlnx_vio (
    .clk(soc_clk),
    .probe_out0(vio_reset)
  );
  assign sys_rst = cpu_reset | vio_reset;
`else
  assign sys_rst = cpu_reset;
`endif

  ///////////////////
  // GPIOs         // 
  ///////////////////

  // Tie off signals if no switches on the board
`ifndef USE_SWITCHES
  logic         testmode_i;
  logic [1:0]   boot_mode_i;
  assign testmode_i  = '0;
  assign boot_mode_i = 2'b00;
`endif

  // Give VDD and GND to JTAG
`ifdef USE_JTAG_VDDGND
  assign jtag_vdd_o  = '1;
  assign jtag_gnd_o  = '0;
`endif
`ifndef USE_JTAG_TRSTN
  logic jtag_trst_ni;
  assign jtag_trst_ni = '1;
`endif

  ///////////////////
  // Clock Divider // 
  ///////////////////

  clk_int_div #(
    .DIV_VALUE_WIDTH       ( 4                ),
    .DEFAULT_DIV_VALUE     ( `DDR_CLK_DIVIDER ),
    .ENABLE_CLOCK_IN_RESET ( 1'b0             )
  ) i_sys_clk_div (
    .clk_i                 ( dram_clock_out ),
    .rst_ni                ( ~dram_sync_reset  ),
    .en_i                  ( 1'b1              ),
    .test_mode_en_i        ( testmode_i        ),
    .div_i                 ( `DDR_CLK_DIVIDER  ),
    .div_valid_i           ( 1'b0              ),
    .div_ready_o           (                   ),
    .clk_o                 ( soc_clk           ),
    .cycl_count_o          (                   )
  );

  /////////////////////
  // Reset Generator //
  /////////////////////

  rstgen i_rstgen_main (
    .clk_i        ( soc_clk                  ),
    .rst_ni       ( ~dram_sync_reset         ),
    .test_mode_i  ( testmode_i               ),
    .rst_no       ( rst_n                    ),
    .init_no      (                          ) // keep open
  );

  //////////////
  // DRAM MIG //
  //////////////

  dram_wrapper #(
    .axi_soc_aw_chan_t ( axi_llc_aw_chan_t ),
    .axi_soc_w_chan_t  ( axi_llc_w_chan_t ),
    .axi_soc_b_chan_t  ( axi_llc_b_chan_t ),
    .axi_soc_ar_chan_t ( axi_llc_ar_chan_t ),
    .axi_soc_r_chan_t  ( axi_llc_r_chan_t ),
    .axi_soc_req_t     (axi_llc_req_t),
    .axi_soc_resp_t    (axi_llc_rsp_t)
  ) i_dram_wrapper (
    // Rst
    .sys_rst_i                  ( sys_rst     ),
    .soc_resetn_i               ( rst_n       ),
    .soc_clk_i                  ( soc_clk     ),
    // Clk rst out
    .dram_clk_o                 ( dram_clock_out     ),
    .dram_rst_o                 ( dram_sync_reset    ),
    // Axi
    .soc_req_i                  ( axi_llc_mst_req  ),
    .soc_rsp_o                  ( axi_llc_mst_rsp  ),
    // Phy
    .*
  );

  //////////////////
  // I2C Adaption //
  //////////////////

  logic i2c_sda_soc_out;
  logic i2c_sda_soc_in;
  logic i2c_scl_soc_out;
  logic i2c_scl_soc_in;
  logic i2c_sda_en;
  logic i2c_scl_en;

`ifdef USE_I2C
  // Three state buffer for SCL
  IOBUF #(
    .DRIVE        ( 12        ),
    .IBUF_LOW_PWR ( "FALSE"   ),
    .IOSTANDARD   ( "DEFAULT" ),
    .SLEW         ( "FAST"    )
  ) i_scl_iobuf (
    .O  ( i2c_scl_soc_in      ),
    .IO ( i2c_scl_io          ),
    .I  ( i2c_scl_soc_out     ),
    .T  ( ~i2c_scl_en         )
  );

  // Three state buffer for SDA
  IOBUF #(
    .DRIVE        ( 12        ),
    .IBUF_LOW_PWR ( "FALSE"   ),
    .IOSTANDARD   ( "DEFAULT" ),
    .SLEW         ( "FAST"    )
  ) i_sda_iobuf (
    .O  ( i2c_sda_soc_in      ),
    .IO ( i2c_sda_io          ),
    .I  ( i2c_sda_soc_out     ),
    .T  ( ~i2c_sda_en         )
  );
`endif


  //////////////////
  // SPI Adaption //
  //////////////////

  logic                 spi_sck_soc;
  logic [SpihNumCs-1:0] spi_cs_soc;
  logic [3:0]           spi_sd_soc_out;
  logic [3:0]           spi_sd_soc_in;

  logic                 spi_sck_en;
  logic [SpihNumCs-1:0] spi_cs_en;
  logic [3:0]           spi_sd_en;

`ifdef USE_SD
  // Assert reset low => Apply power to the SD Card
  assign sd_reset_o       = 1'b0;
  // SCK  - SD CLK signal
  assign sd_sclk_o        = spi_sck_en    ? spi_sck_soc       : 1'b1;
  // CS   - SD DAT3 signal
  assign sd_d_io[3]       = spi_cs_en[0]  ? spi_cs_soc[0]     : 1'b1;
  // MOSI - SD CMD signal
  assign sd_cmd_o         = spi_sd_en[0]  ? spi_sd_soc_out[0] : 1'b1;
  // MISO - SD DAT0 signal
  assign spi_sd_soc_in[1] = sd_d_io[0];
  // SD DAT1 and DAT2 signal tie-off - Not used for SPI mode
  assign sd_d_io[2:1]     = 2'b11;
  // Bind input side of SoC low for output signals
  assign spi_sd_soc_in[0] = 1'b0;
  assign spi_sd_soc_in[2] = 1'b0;
  assign spi_sd_soc_in[3] = 1'b0;
`endif


`ifdef USE_QSPI
  logic                 qspi_clk;
  logic                 qspi_clk_ts;
  logic [3:0]           qspi_dqi;
  logic [3:0]           qspi_dqo_ts;
  logic [3:0]           qspi_dqo;
  logic [SpihNumCs-1:0] qspi_cs_b;
  logic [SpihNumCs-1:0] qspi_cs_b_ts;

  assign qspi_clk      = spi_sck_soc;
  assign qspi_cs_b     = spi_cs_soc;
  assign qspi_dqo      = spi_sd_soc_out;
  assign spi_sd_soc_in = qspi_dqi;
  // Tristate - Enable
  assign qspi_clk_ts  = ~(spi_sck_en);
  assign qspi_cs_b_ts = ~(spi_cs_en);
  assign qspi_dqo_ts  = ~(spi_sd_en);

  ///////////////
  // STARTUPE3 //
  ///////////////

  STARTUPE3 #(
     .PROG_USR("FALSE"),    // Activate program event security feature. Requires encrypted bitstreams.
     .SIM_CCLK_FREQ(0.0)    // Set the Configuration Clock Frequency (ns) for simulation.
  )
  STARTUPE3_inst (
     .CFGCLK    (),         // CONFIG 1-bit output: Configuration main clock output.
     .CFGMCLK   (),         // CONFIG 1-bit output: Configuration internal oscillator clock output.
     .DI        (qspi_dqi),
     .EOS       (),         // CONFIG 1-bit output: Active-High output signal indicating the End Of Startup.
     .PREQ      (),         // CONFIG 1-bit output: PROGRAM request to fabric output.
     .DO        (qspi_dqo),
     .DTS       (qspi_dqo_ts),
     .FCSBO     (qspi_cs_b[1]),
     .FCSBTS    (qspi_cs_b_ts[1]),
     .GSR       (1'b0),
     .GTS       (1'b0),
     .KEYCLEARB (1'b1),
     .PACK      (1'b0),
     .USRCCLKO  (qspi_clk),
     .USRCCLKTS (qspi_clk_ts),
     .USRDONEO  (1'b1),
     .USRDONETS (1'b1)
  );

`endif

  /////////////////////////
  // "RTC" Clock Divider //
  /////////////////////////

  logic rtc_clk_d, rtc_clk_q;
  logic [4:0] counter_d, counter_q;

  // Divide soc_clk (50 MHz) by 50 => 1 MHz RTC Clock
  always_comb begin
    counter_d = counter_q + 1;
    rtc_clk_d = rtc_clk_q;

    if(counter_q == 24) begin
      counter_d = 5'b0;
      rtc_clk_d = ~rtc_clk_q;
    end
  end

  always_ff @(posedge soc_clk, negedge rst_n) begin
    if(~rst_n) begin
      counter_q <= 5'b0;
      rtc_clk_q <= 0;
    end else begin
      counter_q <= counter_d;
      rtc_clk_q <= rtc_clk_d;
    end
  end


  /////////////////
  // Fan Control //
  /////////////////

`ifdef USE_FAN
  fan_ctrl i_fan_ctrl (
    .clk_i         ( soc_clk    ),
    .rst_ni        ( rst_n      ),
    .pwm_setting_i ( fan_sw     ),
    .fan_pwm_o     ( fan_pwm    )
  );
`endif

  ////////////////////////
  // Regbus Error Slave //
  ////////////////////////

  reg_req_t ext_req;
  reg_rsp_t ext_rsp;

  reg_err_slv #(
    .DW       ( 32                 ),
    .ERR_VAL  ( 32'hBADCAB1E       ),
    .req_t    ( reg_req_t  ),
    .rsp_t    ( reg_rsp_t  )
  ) i_reg_err_slv_ext (
    .req_i ( ext_req  ),
    .rsp_o ( ext_rsp  )
  );


  //////////////////
  // Cheshire SoC //
  //////////////////

  cheshire_soc #(
    .Cfg                ( FPGACfg ),
    .ExtHartinfo        ( '0 ),
    .axi_ext_llc_req_t  ( axi_llc_req_t ),
    .axi_ext_llc_rsp_t  ( axi_llc_rsp_t ),
    .axi_ext_mst_req_t  ( axi_mst_req_t ),
    .axi_ext_mst_rsp_t  ( axi_mst_rsp_t ),
    .axi_ext_slv_req_t  ( axi_slv_req_t ),
    .axi_ext_slv_rsp_t  ( axi_slv_rsp_t ),
    .reg_ext_req_t      ( reg_req_t ),
    .reg_ext_rsp_t      ( reg_req_t )
  ) i_cheshire_soc (
    .clk_i              ( soc_clk ),
    .rst_ni             ( rst_n   ),
    .test_mode_i        ( testmode_i ),
    .boot_mode_i,
    .rtc_i              ( rtc_clk_q       ),
    .axi_llc_mst_req_o  ( axi_llc_mst_req ),
    .axi_llc_mst_rsp_i  ( axi_llc_mst_rsp ),
    .axi_ext_mst_req_i  ( '0 ),
    .axi_ext_mst_rsp_o  ( ),
    .axi_ext_slv_req_o  ( ),
    .axi_ext_slv_rsp_i  ( '0 ),
    .reg_ext_slv_req_o  ( ),
    .reg_ext_slv_rsp_i  ( '0 ),
    .intr_ext_i         ( '0 ),
    .meip_ext_o         ( ),
    .seip_ext_o         ( ),
    .mtip_ext_o         ( ),
    .msip_ext_o         ( ),
    .dbg_active_o       ( ),
    .dbg_ext_req_o      ( ),
    .dbg_ext_unavail_i  ( '0 ),
// Serial Link may be disabled
`ifdef USE_SERIAL
    .ddr_link_i           ( '0                    ),
    .ddr_link_o,
    .ddr_link_clk_i       ( 1'b1                  ),
    .ddr_link_clk_o,
`endif
// External JTAG may be disabled
`ifdef USE_JTAG
    .jtag_tck_i,
    .jtag_trst_ni,
    .jtag_tms_i,
    .jtag_tdi_i,
    .jtag_tdo_o,
`endif
// I2C Uses internal signals that are always defined
    .i2c_sda_o            ( i2c_sda_soc_out       ),
    .i2c_sda_i            ( i2c_sda_soc_in        ),
    .i2c_sda_en_o         ( i2c_sda_en            ),
    .i2c_scl_o            ( i2c_scl_soc_out       ),
    .i2c_scl_i            ( i2c_scl_soc_in        ),
    .i2c_scl_en_o         ( i2c_scl_en            ),
// SPI Uses internal signals that are always defined
`ifdef USE_QSPI
    .spih_sck_o           ( spi_sck_soc           ),
    .spih_sck_en_o        ( spi_sck_en            ),
    .spih_csb_o           ( spi_cs_soc            ),
    .spih_csb_en_o        ( spi_cs_en             ),
    .spih_sd_o            ( spi_sd_soc_out        ),
    .spih_sd_en_o         ( spi_sd_en             ),
    .spih_sd_i            ( spi_sd_soc_in         ),
`endif
`ifdef USE_VGA
    .vga_hsync_o          ( vga_hs                ),
    .vga_vsync_o          ( vga_vs                ),
    .vga_red_o            ( vga_r                 ),
    .vga_green_o          ( vga_g                 ),
    .vga_blue_o           ( vga_b                 ),
`endif
    .uart_tx_o,
    .uart_rx_i
  );

endmodule
