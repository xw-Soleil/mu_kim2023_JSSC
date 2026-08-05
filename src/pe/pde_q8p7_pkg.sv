// ============================================================================
// pde_q8p7_pkg.sv : Q8.7 datapath parameters and precision encoding
// ============================================================================
// Residues and solutions are both 16-bit two's complement.
//
// Precision encoding (Ser[1:0] in Mu & Kim, JSSC'23)
//   2'b00 -> 16 bits
//   2'b01 -> 12 bits
//   2'b10 ->  8 bits
//   2'b11 ->  4 bits
//
// Canonical value at the PE interface:
// a residue register stores its active B-bit word high-aligned in q[15:16-B].
// pe_top selects one bank and unpacks it to a fully sign-extended 16-bit
// value for accumulation.
// ============================================================================
package pde_q8p7_pkg;

  localparam int W = 16;                  // Q8.7 datapath width

  localparam logic [1:0] P16 = 2'b00;
  localparam logic [1:0] P12 = 2'b01;
  localparam logic [1:0] P8  = 2'b10;
  localparam logic [1:0] P4  = 2'b11;

  // Active bit count for a precision code.
  function automatic int prec_bits(input logic [1:0] p);
    case (p)
      P16    : prec_bits = 16;
      P12    : prec_bits = 12;
      P8     : prec_bits = 8;
      P4     : prec_bits = 4;
    endcase
  endfunction

  // Index of the active field's sign bit (3 / 7 / 11 / 15).
  function automatic int prec_msb(input logic [1:0] p);
    prec_msb = prec_bits(p) - 1;
  endfunction

  // The Fig. 8 adder emits Sum/MSB1/MSB0 in parallel on the MSB cycle,
  // so an N-bit operation takes exactly N clocks.
  function automatic int run_cycles(input logic [1:0] p);
    run_cycles = prec_bits(p);
  endfunction

  // Range check: does a sign-extended 16-bit value fit in `n` bits?
  function automatic logic fits_n(input logic [W-1:0] v, input int n);
    logic signed [W-1:0] sh;
    sh     = $signed(v) >>> (n-1);
    fits_n = (sh == {W{1'b0}}) || (sh == {W{1'b1}});
  endfunction

  // Symmetric convergence window. Deliberately not fits_n(v, 2): a 2-bit
  // two's complement field also holds -2, which would let negative problems
  // converge one precision step earlier than positive ones.
  function automatic logic residue_small(input logic [W-1:0] v);
    residue_small = (v == {W{1'b0}})
                  || (v == {{W-1{1'b0}}, 1'b1})
                  || (v == {W{1'b1}});
  endfunction

  // High-aligned <-> canonical (low-aligned, sign-extended) conversion.
  // One shift each way covers all four precisions, no per-precision case.
  function automatic logic [W-1:0] pack_high(input logic [W-1:0] v,
                                              input logic [1:0]   p);
    pack_high = v << (W - prec_bits(p));
  endfunction

  function automatic logic [W-1:0] unpack_high(input logic [W-1:0] v,
                                                input logic [1:0]   p);
    unpack_high = $signed(v) >>> (W - prec_bits(p));
  endfunction

endpackage
