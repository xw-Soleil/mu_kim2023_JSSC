// ============================================================================
// sol_acc.sv : solution accumulators and scan chain for one PE
// ============================================================================
// The residue is what the bit-serial datapath works on; the solution is just
// its running total.
//
// Each commit adds the residue just computed to the accumulator of the colour
// that was written. The two commits never coincide, so one adder is enough.
//
// The same two registers double as the readout path: in scan mode they chain
// into a 32-bit shift register and join the array-wide chain.
// HEAD_IS_RED follows the checkerboard -- Red leads on even rows, Black on odd.
// ============================================================================
module sol_acc #(
  parameter bit HEAD_IS_RED = 1'b1
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        scan_mode,
  input  logic        u_red_we,
  input  logic        u_black_we,
  input  logic        dst_black,      // which accumulator the adder feeds
  input  logic [15:0] add_value,      // canonical residue being committed

  input  logic        scan_in,
  output logic        scan_out,
  output logic [15:0] u_red_o,
  output logic [15:0] u_black_o
);

  localparam int DW = 16;

  logic [DW-1:0] u_red_q, u_black_q;

  // Shared accumulate adder.
  logic [DW-1:0] acc_fb, acc_sum;
  assign acc_fb  = dst_black ? u_black_q : u_red_q;
  assign acc_sum = acc_fb + add_value;

  // Scan. Head takes the incoming chain bit, tail takes the head's LSB,
  // and the tail's LSB leaves for the next PE.
  logic          tail_shift_in;
  logic [DW-1:0] shift_red, shift_black;
  logic [DW-1:0] d_red, d_black;

  assign tail_shift_in = HEAD_IS_RED ? u_red_q[0] : u_black_q[0];
  assign scan_out      = HEAD_IS_RED ? u_black_q[0] : u_red_q[0];
  assign shift_red     = {(HEAD_IS_RED ? scan_in : tail_shift_in),
                          u_red_q[DW-1:1]};
  assign shift_black   = {(HEAD_IS_RED ? tail_shift_in : scan_in),
                          u_black_q[DW-1:1]};

  assign d_red   = scan_mode ? shift_red   : acc_sum;
  assign d_black = scan_mode ? shift_black : acc_sum;

  assign u_red_o   = u_red_q;
  assign u_black_o = u_black_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      u_red_q   <= '0;
      u_black_q <= '0;
    end else begin
      if (u_red_we)   u_red_q   <= d_red;
      if (u_black_we) u_black_q <= d_black;
    end
  end

endmodule
