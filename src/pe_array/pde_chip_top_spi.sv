// ============================================================================
// pde_chip_top_spi.sv : full-chip top with SPI configuration interface
// ============================================================================
// Nine-signal chip boundary: clk, rst_n, SPI (sclk/cs_n/mosi/miso) and the
// dedicated serial result port (scan_out/scan_valid/scan_last).  The parallel
// cfg bus becomes chip-internal, driven solely by spi_cfg_bridge; the proven
// pde_chip_top_safe hierarchy is instantiated untouched.
//
// The scan stream still runs at one bit per clk with no backpressure; board
// readout uses the slow-clock mode from docs/spi_interface_spec.md section 6.

module pde_chip_top_spi #(
  parameter int NROW          = 20,
  parameter int NCOL_LOG      = 20,
  parameter bit USE_DSM       = 1'b1,
  parameter bit CONV_ON_SMALL = 1'b1,
  parameter bit DYN_PREC      = 1'b1,
  parameter int MAX_UPDATES   = 4096,
  parameter int NPE           = NCOL_LOG/2
)(
  input  logic clk,
  input  logic rst_n,
  input  logic sclk,
  input  logic cs_n,
  input  logic mosi,
  output logic miso,
  output logic scan_out,
  output logic scan_valid,
  output logic scan_last
);

  logic        cfg_valid;
  logic        cfg_write;
  logic [15:0] cfg_addr;
  logic [15:0] cfg_wdata;
  logic        cfg_ready;
  logic        cfg_rvalid;
  logic [15:0] cfg_rdata;

  spi_cfg_bridge u_spi (
    .clk(clk),
    .rst_n(rst_n),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso),
    .cfg_valid(cfg_valid),
    .cfg_write(cfg_write),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_ready(cfg_ready),
    .cfg_rvalid(cfg_rvalid),
    .cfg_rdata(cfg_rdata)
  );

  pde_chip_top_safe #(
    .NROW(NROW),
    .NCOL_LOG(NCOL_LOG),
    .USE_DSM(USE_DSM),
    .CONV_ON_SMALL(CONV_ON_SMALL),
    .DYN_PREC(DYN_PREC),
    .MAX_UPDATES(MAX_UPDATES),
    .NPE(NPE)
  ) u_chip (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_valid(cfg_valid),
    .cfg_write(cfg_write),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_ready(cfg_ready),
    .cfg_rvalid(cfg_rvalid),
    .cfg_rdata(cfg_rdata),
    .scan_out(scan_out),
    .scan_valid(scan_valid),
    .scan_last(scan_last)
  );

endmodule
