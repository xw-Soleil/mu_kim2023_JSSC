// ============================================================================
// r_dsm.sv : first-order delta-sigma error feedback
// ============================================================================
// Dividing the four-neighbour sum by 4 discards the bottom two bits.
// This block replays them into the next update of the same point, so the
// truncation error integrates to zero instead of biasing the solution.
//
//   run    : rem_q captures the two discarded bits (they arrive on bit 0/1)
//   commit : rem_q moves into the error register of the colour just written
//   next   : that error is fed back through the ALU's spare input
//
// USE_DSM=0 ties d_bit_o low and the whole block optimises away.
// ============================================================================
module r_dsm #(
  parameter bit USE_DSM = 1'b1
)(
  input  logic clk,
  input  logic rst_n,

  input  logic shift_en,
  input  logic dsm_sel0,      // bit 0 of the run
  input  logic dsm_sel1,      // bit 1 of the run
  input  logic dsm_commit,
  input  logic dst_black,     // which colour is being written
  input  logic sum_bit,       // serial sum out of r_alu

  output logic d_bit_o        // error bit fed back into r_alu
);

  logic [1:0] err_red_q, err_black_q;
  logic [1:0] err_dst;
  logic [1:0] rem_q, rem_d;

  assign err_dst = dst_black ? err_black_q : err_red_q;

  assign d_bit_o = !USE_DSM ? 1'b0
                            : (dsm_sel0 ? err_dst[0]
                                        : (dsm_sel1 ? err_dst[1] : 1'b0));

  assign rem_d = dsm_sel0 ? {rem_q[1], sum_bit}
               : dsm_sel1 ? {sum_bit, rem_q[0]}
                          : rem_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)        rem_q <= 2'd0;
    else if (shift_en) rem_q <= rem_d;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      err_red_q   <= 2'd0;
      err_black_q <= 2'd0;
    end else if (dsm_commit && USE_DSM) begin
      if (dst_black) err_black_q <= rem_q;
      else           err_red_q   <= rem_q;
    end
  end

endmodule
