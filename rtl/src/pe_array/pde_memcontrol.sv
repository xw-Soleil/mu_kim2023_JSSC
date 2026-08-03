// ============================================================================
// pde_memcontrol.sv : boundary condition storage and serialisation
// ============================================================================
// Residue-based FDM applies the boundary values on the first grid update
// only. From update 1 on the boundary residue is zero and the initial
// excitation propagates through the array on its own. That is what the TCU's
// `first_update` gates.
//
// Every boundary value is serialised with the same protocol as a PE:
// exactly B cycles, LSB first, sign bit on cycle B-1.
//
// North/south indexing: one physical PE covers two logical columns, so the
// boundary driver has to present the right column for the current phase.
// The active offset is (ROW_ODD ^ phase), the same expression a PE uses to
// pick its remote horizontal direction.
// ============================================================================
module pde_memcontrol #(
  parameter int NROW     = 20,          // logical rows = physical rows
  parameter int NCOL_LOG = 20,          // logical columns, must be even
  parameter int NPE      = NCOL_LOG/2   // physical PE columns
)(
  input  logic [1:0]                prec,
  input  logic [4:0]                bit_cnt,
  input  logic                      phase,
  input  logic                      first_update,

  input  logic [16*NCOL_LOG-1:0]    bnd_north_flat,
  input  logic [16*NCOL_LOG-1:0]    bnd_south_flat,
  input  logic [16*NROW-1:0]        bnd_west_flat,
  input  logic [16*NROW-1:0]        bnd_east_flat,

  output logic [NPE-1:0]            north_bit,   // to row 0
  output logic [NPE-1:0]            south_bit,   // to row NROW-1
  output logic [NROW-1:0]           west_bit,    // to column 0
  output logic [NROW-1:0]           east_bit     // to column NPE-1
);

  import pde_q8p7_pkg::*;

  // Serialise a 16-bit value, LSB first. The fallback branch is defensive
  // only; the paper's controller never asks for k >= B.
  function automatic logic ser(input logic [15:0] v,
                               input logic [4:0]  k,
                               input logic [1:0]  p);
    ser = (k < 5'(prec_bits(p))) ? v[k[3:0]] : v[15];
  endfunction

  localparam bit ROW0_ODD  = 1'b0;
  localparam bit ROWN_ODD  = bit'((NROW-1) % 2);
  localparam int IDX_W     = (NCOL_LOG <= 1) ? 1 : $clog2(NCOL_LOG);

  genvar c, r;
  generate
    for (c = 0; c < NPE; c++) begin : g_ns
      logic [IDX_W-1:0] idx_n, idx_s;
      logic [15:0] vn, vs;
      logic active_n, active_s;
      // The logical column PE c has active in this phase.
      assign active_n = ROW0_ODD ^ phase;
      assign active_s = ROWN_ODD ^ phase;
      assign idx_n = IDX_W'(2*c) + IDX_W'(active_n);
      assign idx_s = IDX_W'(2*c) + IDX_W'(active_s);
      assign vn    = bnd_north_flat[16*idx_n +: 16];
      assign vs    = bnd_south_flat[16*idx_s +: 16];
      assign north_bit[c] = first_update ? ser(vn, bit_cnt, prec) : 1'b0;
      assign south_bit[c] = first_update ? ser(vs, bit_cnt, prec) : 1'b0;
    end
    for (r = 0; r < NROW; r++) begin : g_we
      logic [15:0] vw, ve;
      assign vw = bnd_west_flat[16*r +: 16];
      assign ve = bnd_east_flat[16*r +: 16];
      assign west_bit[r] = first_update ? ser(vw, bit_cnt, prec) : 1'b0;
      assign east_bit[r] = first_update ? ser(ve, bit_cnt, prec) : 1'b0;
    end
  endgenerate

endmodule
