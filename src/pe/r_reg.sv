// ============================================================================
// r_reg.sv : residue bank for one colour (Red or Black)
// ============================================================================
// 16-bit register holding the paper's high-aligned residue.
// The active B-bit word sits in q[15:16-B].
//
//   load      : take an initial residue from the host
//   compute   : CK_A, q[15:13] <= {MSB0, MSB1, Sum}, rest shifts right
//   serialise : rotate right, streaming the word out LSB first
//
// Serialisation taps the bit at the stored precision (1-bit 4:1 mux) and
// rotates the whole word, so B clocks leave the bank untouched.
// No unpack-then-repack is needed, because precision only ever narrows.
// ============================================================================
module r_reg (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [1:0]  src_prec,      // precision this bank is stored at
  input  logic        load_en,
  input  logic [15:0] load_value,    // already packed high-aligned
  input  logic        shift_en,
  input  logic        compute,       // 1: take ALU result, 0: serialise
  input  logic [2:0]  calc_bits,     // {MSB0, MSB1, Sum} from r_alu

  output logic [15:0] q_o,
  output logic        ser_bit_o
);

  import pde_q8p7_pkg::*;

  localparam int DW = 16;

  logic [DW-1:0] q;
  logic [DW-1:0] compute_nxt, serialize_nxt;

  assign ser_bit_o     = q[DW - prec_bits(src_prec)];
  assign serialize_nxt = {ser_bit_o, q[DW-1:1]};
  assign compute_nxt   = {calc_bits, q[DW-3:1]};

  assign q_o = q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q <= '0;
    end else if (load_en) begin
      q <= load_value;
    end else if (shift_en) begin
      q <= compute ? compute_nxt : serialize_nxt;
    end
  end

endmodule
