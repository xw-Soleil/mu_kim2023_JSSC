// ============================================================================
// pde_chip_top_safe.sv : protocol-hardening wrapper for pde_chip_top
// ============================================================================
// This wrapper leaves the existing implementation untouched. It atomically
// rejects CONTROL writes that would otherwise have unsafe side effects:
//   * any non-zero reserved bit [15:3]
//   * a second destructive read request after scan output has started
//
// STATUS keeps the pde_chip_top low-byte layout, except bit 6 reports the OR
// of the implementation and wrapper sticky errors. Bit 8 reports scan_used.
// ============================================================================
module pde_chip_top_safe #(
  parameter int NROW          = 20,
  parameter int NCOL_LOG      = 20,
  parameter bit USE_DSM       = 1'b1,
  parameter bit CONV_ON_SMALL = 1'b1,
  parameter bit DYN_PREC      = 1'b1,
  parameter int MAX_UPDATES   = 4096,
  parameter int NPE           = NCOL_LOG/2
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cfg_valid,
  input  logic        cfg_write,
  input  logic [15:0] cfg_addr,
  input  logic [15:0] cfg_wdata,
  output logic        cfg_ready,
  output logic        cfg_rvalid,
  output logic [15:0] cfg_rdata,
  output logic        scan_out,
  output logic        scan_valid,
  output logic        scan_last
);

  localparam logic [15:0] A_CONTROL = 16'h0000;
  localparam logic [15:0] A_STATUS  = 16'h0001;

  logic        impl_cfg_valid;
  logic        impl_cfg_ready;
  logic        impl_cfg_rvalid;
  logic [15:0] impl_cfg_rdata;
  logic        impl_scan_out;
  logic        impl_scan_valid;
  logic        impl_scan_last;

  logic control_write;
  logic control_reserved_bad;
  logic repeat_read_bad;
  logic control_reject;
  logic reject_accept;
  logic wrapper_clear;
  logic wrapper_error_q;
  logic scan_used_q;
  logic status_read_q;

  assign control_write       = cfg_write && (cfg_addr == A_CONTROL);
  assign control_reserved_bad = |cfg_wdata[15:3];
  assign repeat_read_bad     = cfg_wdata[1] && scan_used_q;
  assign control_reject      = control_write
                             && (control_reserved_bad || repeat_read_bad);

  // A rejected write is still accepted at the external bus boundary, but it
  // is removed atomically before reaching the implementation.
  assign impl_cfg_valid = cfg_valid && !control_reject;
  assign cfg_ready      = impl_cfg_ready;
  assign reject_accept  = cfg_valid && cfg_ready && control_reject;
  assign wrapper_clear  = cfg_valid && cfg_ready && control_write
                        && cfg_wdata[2] && !control_reject;

  pde_chip_top #(
    .NROW(NROW),
    .NCOL_LOG(NCOL_LOG),
    .USE_DSM(USE_DSM),
    .CONV_ON_SMALL(CONV_ON_SMALL),
    .DYN_PREC(DYN_PREC),
    .MAX_UPDATES(MAX_UPDATES),
    .NPE(NPE)
  ) u_impl (
    .clk(clk),
    .rst_n(rst_n),
    .cfg_valid(impl_cfg_valid),
    .cfg_write(cfg_write),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_ready(impl_cfg_ready),
    .cfg_rvalid(impl_cfg_rvalid),
    .cfg_rdata(impl_cfg_rdata),
    .scan_out(impl_scan_out),
    .scan_valid(impl_scan_valid),
    .scan_last(impl_scan_last)
  );

  // Delay the read-address classification by exactly the implementation's
  // one-cycle response latency. Reads are never filtered by this wrapper.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      status_read_q <= 1'b0;
    else
      status_read_q <= cfg_valid && cfg_ready && !cfg_write
                    && (cfg_addr == A_STATUS);
  end

  // Sticky wrapper error: a rejected transaction wins over a simultaneous
  // clear. In practice the two are mutually exclusive by construction.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wrapper_error_q <= 1'b0;
    end else begin
      if (wrapper_clear) wrapper_error_q <= 1'b0;
      if (reject_accept) wrapper_error_q <= 1'b1;
    end
  end

  // The first observed valid scan bit marks the destructive chain as used.
  // A request arriving before this flag sets is still forwarded; while a scan
  // is active, pde_chip_top rejects it using its own core_done/read_ok checks.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      scan_used_q <= 1'b0;
    else if (impl_scan_valid)
      scan_used_q <= 1'b1;
  end

  assign cfg_rvalid = impl_cfg_rvalid;

  always_comb begin
    cfg_rdata = impl_cfg_rdata;
    if (impl_cfg_rvalid && status_read_q) begin
      cfg_rdata[6] = impl_cfg_rdata[6] | wrapper_error_q;
      cfg_rdata[8] = scan_used_q;
    end
  end

  assign scan_out   = impl_scan_out;
  assign scan_valid = impl_scan_valid;
  assign scan_last  = impl_scan_last;

  // synopsys translate_off
  always_ff @(posedge clk) begin
    if (rst_n && reject_accept)
      $display("[pde_chip_top_safe] rejected CONTROL write data=%h",
               cfg_wdata);
  end
  // synopsys translate_on

endmodule
