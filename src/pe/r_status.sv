// ============================================================================
// r_status.sv : dynamic-precision and convergence flags for one PE
// ============================================================================
// The range checks ride on read_value, the shared canonical read path, so
// they cost no extra precision muxing.
//
// That path shows only one bank at a time, so the two colours are merged
// across the two commit cycles:
//   Red commit   : overwrite the flags
//   Black commit : merge in its own live result (AND to fit, OR for nonzero)
//
// Latching is not optional. By the time the TCU samples these in S_CHECK the
// read path no longer points at Black, so a combinational Black term would
// sample Red twice.
// ============================================================================
module r_status (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        commit,
  input  logic        dst_black,      // 0: Red commit, 1: Black commit
  input  logic [15:0] read_value,     // canonical value of the bank committed

  output logic        fit12_o,
  output logic        fit8_o,
  output logic        fit4_o,
  output logic        small_o,
  output logic        nonzero_o
);

  import pde_q8p7_pkg::*;

  logic fit12_live, fit8_live, fit4_live, small_live, nonzero_live;
  assign fit12_live   = fits_n(read_value, 12);
  assign fit8_live    = fits_n(read_value, 8);
  assign fit4_live    = fits_n(read_value, 4);
  assign small_live   = residue_small(read_value);
  assign nonzero_live = |read_value;

  logic fit12_q, fit8_q, fit4_q, small_q, nonzero_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fit12_q   <= 1'b0;
      fit8_q    <= 1'b0;
      fit4_q    <= 1'b0;
      small_q   <= 1'b0;
      nonzero_q <= 1'b0;
    end else if (commit) begin
      if (!dst_black) begin
        fit12_q   <= fit12_live;
        fit8_q    <= fit8_live;
        fit4_q    <= fit4_live;
        small_q   <= small_live;
        nonzero_q <= nonzero_live;
      end else begin
        fit12_q   <= fit12_q   & fit12_live;
        fit8_q    <= fit8_q    & fit8_live;
        fit4_q    <= fit4_q    & fit4_live;
        small_q   <= small_q   & small_live;
        nonzero_q <= nonzero_q | nonzero_live;
      end
    end
  end

  assign fit12_o   = fit12_q;
  assign fit8_o    = fit8_q;
  assign fit4_o    = fit4_q;
  assign small_o   = small_q;
  assign nonzero_o = nonzero_q;

endmodule
