module cheshire_top_xilinx 
  import cheshire_pkg::*;
(
  input logic         sysclk_p,
  input logic         sysclk_n,
  input logic         cpu_resetn,

  input logic         testmode_i,

  input logic [1:0]   boot_mode_i,

  output logic        uart_tx_o,
  input logic         uart_rx_i,

  input logic         jtag_tck_i,
  input logic         jtag_trst_ni,
  input logic         jtag_tms_i,
  input logic         jtag_tdi_i,
  output logic        jtag_tdo_o,

  inout wire          i2c_scl_io,
  inout wire          i2c_sda_io,

  input logic         sd_cd_i,
  output logic        sd_cmd_o,     
  inout wire  [3:0]   sd_d_io,
  output logic        sd_reset_o,
  output logic        sd_sclk_o,

  input logic [3:0]   fan_sw,
  output logic        fan_pwm,

  // DDR3 DRAM interface
  output wire [14:0]  ddr3_addr,
  output wire [2:0]   ddr3_ba,
  output wire         ddr3_cas_n,
  output wire [0:0]   ddr3_ck_n,
  output wire [0:0]   ddr3_ck_p,
  output wire [0:0]   ddr3_cke,
  output wire [0:0]   ddr3_cs_n,
  output wire [3:0]   ddr3_dm,
  inout wire  [31:0]  ddr3_dq,
  inout wire  [3:0]   ddr3_dqs_n,
  inout wire  [3:0]   ddr3_dqs_p,
  output wire [0:0]   ddr3_odt,
  output wire         ddr3_ras_n,
  output wire         ddr3_reset_n,
  output wire         ddr3_we_n,

  // VGA Colour signals
  output logic [4:0]  vga_b,
  output logic [5:0]  vga_g,
  output logic [4:0]  vga_r,

  // VGA Sync signals
  output logic        vga_hs,
  output logic        vga_vs
);
  wire dram_clock_out;
  wire dram_sync_reset;
  wire soc_clk;

  logic rst_n;

  axi_a48_d64_slv_u0_req_t soc_req, dram_req;
  axi_a48_d64_slv_u0_resp_t soc_resp, dram_resp;

  // Statically assign the response user signals
  // B Channel user
  assign dram_resp.b.user      = '0;

  // R Channel user
  assign dram_resp.r.user      = '0;


  ///////////////////
  // Clock Divider // 
  ///////////////////

  clk_int_div #(
    /// The with
    .DIV_VALUE_WIDTH          ( 4             ),
    /// The default divider value which is used right after reset
    .DEFAULT_DIV_VALUE        ( 4'h4          ),
    /// If 1'b1, the output clock is enabled during async reset assertion
    .ENABLE_CLOCK_IN_RESET    ( 1'b0          )
  ) i_sys_clk_div (
    .clk_i                ( dram_clock_out    ),
    .rst_ni               ( ~dram_sync_reset  ),
    /// Active-high output clock enable. Controls a glitch-free clock gate so the
    /// enable signal may be driven by combinational logic without introducing
    /// glitches.
    .en_i                 ( 1'b1              ),
    /// If asserted (active-high) bypass the clock divider and drive clk_o
    /// directly with clk_i.
    .test_mode_en_i       ( 1'b0              ),
    /// Divider select value. The output clock has a frequency of f_clk_i/div_i.
    /// For div_i == 0 or  div_i == 1, the output clock has the same frequency as
    /// th input clock.
    .div_i                ( 4'h4              ),
    /// Valid handshake signal. Must not combinationally depend on `div_ready_o`.
    /// Once asserted, the valid signal must not be deasserted until it is
    /// accepted with `div_ready_o`.
    .div_valid_i          ( 1'b1              ),
    .div_ready_o          (                   ),
    /// Generated output clock. Given a glitch free input clock, the output clock
    /// is guaranteed to be glitch free with 50% duty cycle, regardless the timing
    /// of reconfiguration requests or en_i de/assetion. During the
    /// reconfiguration, the output clock is gated with its next falling edge and
    /// remains gated (idle-low) for at least one period of the new target output
    /// period to filter out any glitches during the config transition.
    .clk_o                ( soc_clk           ),
    /// Current value of the internal cycle counter. Might be usefull if you need
    /// to do some phase shifting relative to the generated clock.
    .cycl_count_o         (                   )
  );

  /////////////////////
  // Reset Generator //
  /////////////////////

  rstgen i_rstgen_main (
    .clk_i        ( soc_clk                  ),
    .rst_ni       ( ~dram_sync_reset         ),
    .test_mode_i  ( test_en                  ),
    .rst_no       ( rst_n                    ),
    .init_no      (                          ) // keep open
  );

  //////////////////////
  // Protocol Checker //
  //////////////////////

  logic [159:0] pc_status;
  logic pc_asserted;

  xlnx_protocol_checker i_xlnx_protocol_checker (
    .pc_status        ( pc_status           ),
    .pc_asserted      ( pc_asserted         ),
    .aclk             ( dram_clock_out      ),
    .aresetn          ( rst_n               ),
    .pc_axi_awid      ( dram_req.aw.id      ),
    .pc_axi_awaddr    ( dram_req.aw.addr    ),
    .pc_axi_awlen     ( dram_req.aw.len     ),
    .pc_axi_awsize    ( dram_req.aw.size    ),
    .pc_axi_awburst   ( dram_req.aw.burst   ),
    .pc_axi_awlock    ( dram_req.aw.lock    ),
    .pc_axi_awcache   ( dram_req.aw.cache   ),
    .pc_axi_awprot    ( dram_req.aw.prot    ),
    .pc_axi_awqos     ( dram_req.aw.qos     ),
    .pc_axi_awregion  ( dram_req.aw.region  ),
    .pc_axi_awuser    ( dram_req.aw.user    ),
    .pc_axi_awvalid   ( dram_req.aw_valid   ),
    .pc_axi_awready   ( dram_resp.aw_ready  ),
    .pc_axi_wlast     ( dram_req.w.last     ),
    .pc_axi_wdata     ( dram_req.w.data     ),
    .pc_axi_wstrb     ( dram_req.w.strb     ),
    .pc_axi_wuser     ( dram_req.w.user     ),
    .pc_axi_wvalid    ( dram_req.w_valid    ),
    .pc_axi_wready    ( dram_resp.w_ready   ),
    .pc_axi_bid       ( dram_resp.b.id      ),
    .pc_axi_bresp     ( dram_resp.b.resp    ),
    .pc_axi_buser     ( dram_resp.b.user    ),
    .pc_axi_bvalid    ( dram_resp.b_valid   ),
    .pc_axi_bready    ( dram_req.b_ready    ),
    .pc_axi_arid      ( dram_req.ar.id      ),
    .pc_axi_araddr    ( dram_req.ar.addr    ),
    .pc_axi_arlen     ( dram_req.ar.len     ),
    .pc_axi_arsize    ( dram_req.ar.size    ),
    .pc_axi_arburst   ( dram_req.ar.burst   ),
    .pc_axi_arlock    ( dram_req.ar.lock    ),
    .pc_axi_arcache   ( dram_req.ar.cache   ),
    .pc_axi_arprot    ( dram_req.ar.prot    ),
    .pc_axi_arqos     ( dram_req.ar.qos     ),
    .pc_axi_arregion  ( dram_req.ar.region  ),
    .pc_axi_aruser    ( dram_req.ar.user    ),
    .pc_axi_arvalid   ( dram_req.ar_valid   ),
    .pc_axi_arready   ( dram_resp.ar_ready  ),
    .pc_axi_rid       ( dram_resp.r.id      ),
    .pc_axi_rlast     ( dram_resp.r.last    ),
    .pc_axi_rdata     ( dram_resp.r.data    ),
    .pc_axi_rresp     ( dram_resp.r.resp    ),
    .pc_axi_ruser     ( dram_resp.r.user    ),
    .pc_axi_rvalid    ( dram_resp.r_valid   ),
    .pc_axi_rready    ( dram_req.r_ready    )
  );

  ///////////////////////////////////////////
  // AXI Clock Domain Crossing SoC -> DRAM //
  ///////////////////////////////////////////

  axi_cdc #(
    .aw_chan_t  ( axi_a48_d64_slv_u0_aw_chan_t    ), // AW Channel Type
    .w_chan_t   ( axi_a48_d64_slv_u0_w_chan_t     ), //  W Channel Type
    .b_chan_t   ( axi_a48_d64_slv_u0_b_chan_t     ), //  B Channel Type
    .ar_chan_t  ( axi_a48_d64_slv_u0_ar_chan_t    ), // AR Channel Type
    .r_chan_t   ( axi_a48_d64_slv_u0_r_chan_t     ), //  R Channel Type
    .axi_req_t  ( axi_a48_d64_slv_u0_req_t        ), // encapsulates request channels
    .axi_resp_t ( axi_a48_d64_slv_u0_resp_t       ), // encapsulates request channels
    /// Depth of the FIFO crossing the clock domain, given as 2**LOG_DEPTH.
    .LogDepth   ( 1                               )
  ) i_axi_cdc_mig (
    // slave side - clocked by `src_clk_i`
    .src_clk_i    ( soc_clk           ),
    .src_rst_ni   ( rst_n             ),
    .src_req_i    ( soc_req           ),
    .src_resp_o   ( soc_resp          ),
    // master side - clocked by `dst_clk_i`
    .dst_clk_i    ( dram_clock_out    ),
    .dst_rst_ni   ( rst_n             ),
    .dst_req_o    ( dram_req          ),
    .dst_resp_i   ( dram_resp         )
  );

  //////////////
  // DRAM MIG //
  //////////////

  xlnx_mig_7_ddr3 i_dram (
    .sys_clk_p       ( sysclk_p               ),
    .sys_clk_n       ( sysclk_n               ),
    .ddr3_dq,
    .ddr3_dqs_n,
    .ddr3_dqs_p,
    .ddr3_addr,
    .ddr3_ba,
    .ddr3_ras_n,
    .ddr3_cas_n,
    .ddr3_we_n,
    .ddr3_reset_n,
    .ddr3_ck_p,
    .ddr3_ck_n,
    .ddr3_cke,
    .ddr3_cs_n,
    .ddr3_dm,
    .ddr3_odt,
    .mmcm_locked     (                        ), // keep open
    .app_sr_req      ( '0                     ),
    .app_ref_req     ( '0                     ),
    .app_zq_req      ( '0                     ),
    .app_sr_active   (                        ), // keep open
    .app_ref_ack     (                        ), // keep open
    .app_zq_ack      (                        ), // keep open
    .ui_clk          ( dram_clock_out         ),
    .ui_clk_sync_rst ( dram_sync_reset        ),
    .aresetn         ( rst_n                  ),
    .s_axi_awid      ( dram_req.aw.id         ),
    .s_axi_awaddr    ( dram_req.aw.addr[29:0] ),
    .s_axi_awlen     ( dram_req.aw.len        ),
    .s_axi_awsize    ( dram_req.aw.size       ),
    .s_axi_awburst   ( dram_req.aw.burst      ),
    .s_axi_awlock    ( dram_req.aw.lock       ),
    .s_axi_awcache   ( dram_req.aw.cache      ),
    .s_axi_awprot    ( dram_req.aw.prot       ),
    .s_axi_awqos     ( dram_req.aw.qos        ),
    .s_axi_awvalid   ( dram_req.aw_valid      ),
    .s_axi_awready   ( dram_resp.aw_ready     ),
    .s_axi_wdata     ( dram_req.w.data        ),
    .s_axi_wstrb     ( dram_req.w.strb        ),
    .s_axi_wlast     ( dram_req.w.last        ),
    .s_axi_wvalid    ( dram_req.w_valid       ),
    .s_axi_wready    ( dram_resp.w_ready      ),
    .s_axi_bready    ( dram_req.b_ready       ),
    .s_axi_bid       ( dram_resp.b.id         ),
    .s_axi_bresp     ( dram_resp.b.resp       ),
    .s_axi_bvalid    ( dram_resp.b_valid      ),
    .s_axi_arid      ( dram_req.ar.id         ),
    .s_axi_araddr    ( dram_req.ar.addr[29:0] ),
    .s_axi_arlen     ( dram_req.ar.len        ),
    .s_axi_arsize    ( dram_req.ar.size       ),
    .s_axi_arburst   ( dram_req.ar.burst      ),
    .s_axi_arlock    ( dram_req.ar.lock       ),
    .s_axi_arcache   ( dram_req.ar.cache      ),
    .s_axi_arprot    ( dram_req.ar.prot       ),
    .s_axi_arqos     ( dram_req.ar.qos        ),
    .s_axi_arvalid   ( dram_req.ar_valid      ),
    .s_axi_arready   ( dram_resp.ar_ready     ),
    .s_axi_rready    ( dram_req.r_ready       ),
    .s_axi_rid       ( dram_resp.r.id         ),
    .s_axi_rdata     ( dram_resp.r.data       ),
    .s_axi_rresp     ( dram_resp.r.resp       ),
    .s_axi_rlast     ( dram_resp.r.last       ),
    .s_axi_rvalid    ( dram_resp.r_valid      ),
    .init_calib_complete (                    ), // keep open
    .device_temp         (                    ), // keep open
    .sys_rst             ( cpu_resetn         )
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


  //////////////////
  // SPI Adaption //
  //////////////////

  logic spi_sck_soc;
  logic [1:0] spi_cs_soc;
  logic [3:0] spi_sd_soc_out;
  logic [3:0] spi_sd_soc_in;

  logic spi_sck_en;
  logic [1:0] spi_cs_en;
  logic [3:0] spi_sd_en;

  // Assert reset low => Apply power to the SD Card
  assign sd_reset_o       = 1'b0;

  // SCK  - SD CLK signal
  assign sd_sclk_o        = spi_sck_en ? spi_sck_soc : 1'b1;

  // CS   - SD DAT3 signal
  assign sd_d_io[3]       = spi_cs_en[0] ? spi_cs_soc[0] : 1'b1;

  // MOSI - SD CMD signal
  assign sd_cmd_o         = spi_sd_en[0] ? spi_sd_soc_out[0] : 1'b1;

  // MISO - SD DAT0 signal
  assign spi_sd_soc_in[1] = sd_d_io[0];

  // SD DAT1 and DAT2 signal tie-off - Not used for SPI mode
  assign sd_d_io[2:1] = 2'b11;

  // Bind input side of SoC low for output signals
  assign spi_sd_soc_in[0] = 1'b0;
  assign spi_sd_soc_in[2] = 1'b0;
  assign spi_sd_soc_in[3] = 1'b0;

  /////////////////////////
  // "RTC" Clock Divider //
  /////////////////////////

  logic rtc_clk_d, rtc_clk_q;
  logic [5:0] counter_d, counter_q;

  // Divide soc_clk (50 MHz) by 50 => 1 MHz RTC Clock
  always_comb begin
    counter_d = counter_q + 1;
    rtc_clk_d = rtc_clk_q;

    if(counter_q == 24) begin
      counter_d = 2'b0;
      rtc_clk_d = ~rtc_clk_q;
    end
  end

  always_ff @(posedge soc_clk, negedge rst_n) begin
    if(~rst_n) begin
      counter_q <= 2'b0;
      rtc_clk_q <= 0;
    end else begin
      counter_q <= counter_d;
      rtc_clk_q <= rtc_clk_d;
    end
  end

  ///////////////////
  // ILA Debugging //
  ///////////////////

  //xlnx_ila i_xlnx_ila (
  //  .clk (dram_clock_out),
  //  .probe0(spi_sck_soc),
  //  .probe1(spi_sd_soc_in),
  //  .probe2(spi_sd_soc_out),
  //  .probe3(spi_cs_soc[0]),
  //  .probe4(spi_cs_soc[1])
  //);


  /////////////////
  // Fan Control //
  /////////////////

  fan_ctrl i_fan_ctrl (
    .clk_i         ( soc_clk    ),
    .rst_ni        ( rst_n      ),
    .pwm_setting_i ( fan_sw     ),
    .fan_pwm_o     ( fan_pwm    )
  );

  /////////////////////////
  // Regbus Error Slaves //
  /////////////////////////

  reg_a48_d32_req_t dram_conf_req, fll_conf_req, pad_conf_req;
  reg_a48_d32_rsp_t dram_conf_rsp, fll_conf_rsp, pad_conf_rsp; 
   
  reg_err_slv #(
    .DW       ( 32                 ),
    .ERR_VAL  ( 32'hBADCAB1E       ),
    .req_t    ( reg_a48_d32_req_t  ),
    .rsp_t    ( reg_a48_d32_rsp_t  )
  ) i_reg_err_slv_dram (
    .req_i ( dram_conf_req  ),
    .rsp_o ( dram_conf_rsp  )
  );
   
  reg_err_slv #(
    .DW       ( 32                 ),
    .ERR_VAL  ( 32'hBADCAB1E       ),
    .req_t    ( reg_a48_d32_req_t  ),
    .rsp_t    ( reg_a48_d32_rsp_t  )
  ) i_reg_err_slv_fll (
    .req_i ( fll_conf_req  ),
    .rsp_o ( fll_conf_rsp  )
  );
   
  reg_err_slv #(
    .DW       ( 32                 ),
    .ERR_VAL  ( 32'hBADCAB1E       ),
    .req_t    ( reg_a48_d32_req_t  ),
    .rsp_t    ( reg_a48_d32_rsp_t  )
  ) i_reg_err_slv_pad (
    .req_i ( pad_conf_req  ),
    .rsp_o ( pad_conf_rsp  )
  );

  //////////////////
  // Cheshire SoC //
  //////////////////

  cheshire_soc i_cheshire_soc (
    .clk_i                ( soc_clk               ),
    .rst_ni               ( rst_n                 ),

    .testmode_i           ( testmode_i            ),

    .boot_mode_i,

    .boot_addr_i          ( 64'h00000000_01000000 ),

    .dram_req_o           ( soc_req               ),
    .dram_resp_i          ( soc_resp              ),
    .dram_conf_req_o      ( dram_conf_req         ),
    .dram_conf_rsp_i      ( dram_conf_rsp         ),
  
    .ddr_link_i           ( '0                    ),
    .ddr_link_o           (                       ),
    .ddr_link_clk_i       ( 1'b1                  ),
    .ddr_link_clk_o       (                       ),

    .jtag_tck_i,
    .jtag_trst_ni,
    .jtag_tms_i,
    .jtag_tdi_i,
    .jtag_tdo_o,

    .uart_tx_o,
    .uart_rx_i,

    .i2c_sda_o            ( i2c_sda_soc_out       ),
    .i2c_sda_i            ( i2c_sda_soc_in        ),
    .i2c_sda_en_o         ( i2c_sda_en            ),
    .i2c_scl_o            ( i2c_scl_soc_out       ),
    .i2c_scl_i            ( i2c_scl_soc_in        ),
    .i2c_scl_en_o         ( i2c_scl_en            ),

    .rtc_i                ( rtc_clk_q             ),

    .fll_reg_req_o        ( fll_conf_req          ),
    .fll_reg_rsp_i        ( fll_conf_rsp          ),
    .fll_lock_i           ( 1'b1                  ),

    .pad_config_req_o     ( pad_conf_req          ),
    .pad_config_rsp_i     ( pad_conf_rsp          ),

    .spim_sck_o           ( spi_sck_soc           ),
    .spim_sck_en_o        ( spi_sck_en            ),
    .spim_csb_o           ( spi_cs_soc            ),
    .spim_csb_en_o        ( spi_cs_en             ),
    .spim_sd_o            ( spi_sd_soc_out        ),
    .spim_sd_en_o         ( spi_sd_en             ),
    .spim_sd_i            ( spi_sd_soc_in         ),

    .vga_hsync_o          ( vga_hs                ),
    .vga_vsync_o          ( vga_vs                ),
    .vga_red_o            ( vga_r                 ),
    .vga_green_o          ( vga_g                 ),
    .vga_blue_o           ( vga_b                 )
  );

endmodule