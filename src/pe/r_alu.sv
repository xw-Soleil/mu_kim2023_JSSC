// ============================================================================
// r_alu.sv : bit-serial four-operand adder (paper Fig. 8)
// ============================================================================
//   top row    : four bit-serial adders + four carry DFFs
//   middle row : first sign-extension correction, combinational
//   bottom row : second sign-extension correction, combinational
//
// Outputs on the MSB cycle:
//   sum_bit  = bit B-1 of the result
//   msb1_bit = bit B
//   msb0_bit = bit B+1 (sign)
//
// All three come out in parallel, so an N-bit op costs exactly N clocks.
// r_reg latches {msb0_bit, msb1_bit, sum_bit} in one go.
// ============================================================================
module r_alu (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clr,        // sync clear of all four carry DFFs
  input  logic       en,
  input  logic       in_n,       // north neighbour residue bit
  input  logic       in_s,       // south neighbour residue bit
  input  logic       in_hl,      // local horizontal neighbour
  input  logic       in_hr,      // remote horizontal neighbour
  input  logic       in_d,       // unsigned DSM error bit
  output logic       sum_bit,
  output logic       msb1_bit,
  output logic       msb0_bit
);

  // One carry per top-row adder: the four DFFs of Fig. 8.
  logic [3:0] carry_q;
  logic [3:0] carry_d;

  // Two-bit temporaries are {carry, sum}. Widened to keep simulators agreeing.
  logic [1:0] top0_t, top1_t, top2_t, top3_t;
  logic [1:0] ext1_0_t, ext1_1_t, ext1_2_t, ext1_3_t;
  logic       ext2_0_s, ext2_1_s, ext2_2_s, ext2_3_s;

  // Top row. The DSM enters at column 0, turning that half adder into a full
  // adder; it needs no carry DFF of its own.
  assign top0_t = {1'b0, in_n } + {1'b0, in_d      }
                + {1'b0, carry_q[0]};
  assign top1_t = {1'b0, in_s } + {1'b0, top0_t[0]}
                + {1'b0, carry_q[1]};
  assign top2_t = {1'b0, in_hl} + {1'b0, top1_t[0]}
                + {1'b0, carry_q[2]};
  assign top3_t = {1'b0, in_hr} + {1'b0, top2_t[0]}
                + {1'b0, carry_q[3]};

  assign carry_d = {top3_t[1], top2_t[1], top1_t[1], top0_t[1]};
  assign sum_bit = top3_t[0];

  // Middle row: one sign-extension cycle unrolled.
  // On the MSB cycle in_n/in_s/in_hl/in_hr are the four operands' sign bits.
  assign ext1_0_t = {1'b0, in_n     } + {1'b0, carry_d[0]};
  assign ext1_1_t = {1'b0, in_s     } + {1'b0, ext1_0_t[0]}
                  + {1'b0, carry_d[1]};
  assign ext1_2_t = {1'b0, in_hl    } + {1'b0, ext1_1_t[0]}
                  + {1'b0, carry_d[2]};
  assign ext1_3_t = {1'b0, in_hr    } + {1'b0, ext1_2_t[0]}
                  + {1'b0, carry_d[3]};

  assign msb1_bit = ext1_3_t[0];

  // Bottom row: the second sign-extension cycle unrolled.
  // Only its sum is observable, so the carries are dropped.
  assign ext2_0_s = in_n  ^ ext1_0_t[1];
  assign ext2_1_s = in_s  ^ ext2_0_s ^ ext1_1_t[1];
  assign ext2_2_s = in_hl ^ ext2_1_s ^ ext1_2_t[1];
  assign ext2_3_s = in_hr ^ ext2_2_s ^ ext1_3_t[1];

  assign msb0_bit = ext2_3_s;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)   carry_q <= 4'b0000;
    else if (clr) carry_q <= 4'b0000;
    else if (en)  carry_q <= carry_d;
  end

endmodule
