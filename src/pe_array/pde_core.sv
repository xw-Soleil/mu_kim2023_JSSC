// ============================================================================
// pde_core.sv : structural core of the PDE accelerator
// ============================================================================
//   pde_tcu        global timing, precision and convergence control
//   pde_memcontrol boundary selection and serialisation
//   PE array       the folded pe_top lattice, neighbour wiring, scan chain
//                  and array-wide reduction, all held directly below
// ============================================================================
module pde_core #(
  parameter int NROW          = 20,
  parameter int NCOL_LOG      = 20,
  parameter bit USE_DSM       = 1'b1,
  parameter bit CONV_ON_SMALL = 1'b1,
  parameter bit DYN_PREC      = 1'b1,
  parameter int MAX_UPDATES   = 4096,
  parameter int NPE           = NCOL_LOG/2
)(
  input  logic                            clk,
  input  logic                            rst_n,

  input  logic                            start,
  input  logic                            read_start,

  input  logic [16*NCOL_LOG-1:0]          bnd_north_flat,
  input  logic [16*NCOL_LOG-1:0]          bnd_south_flat,
  input  logic [16*NROW-1:0]              bnd_west_flat,
  input  logic [16*NROW-1:0]              bnd_east_flat,

  input  logic                            load_en,
  input  logic [16*NROW*NPE-1:0]          load_red_flat,
  input  logic [16*NROW*NPE-1:0]          load_black_flat,

  input  logic                            scan_in,
  output logic                            scan_out,

  output logic                            busy,
  output logic                            done,
  output logic                            converged,
  output logic [1:0]                      prec_o,
  output logic [31:0]                     update_cnt,
  output logic [31:0]                     cycle_cnt,

  output logic [16*NROW*NPE-1:0]          u_red_flat,
  output logic [16*NROW*NPE-1:0]          u_black_flat
);

  localparam int NPEALL = NROW*NPE;

  logic phase, run_en, commit, read_en, first_update;
  logic [1:0] prec, src_prec;
  logic [4:0] bit_cnt;
  logic all_fit12, all_fit8, all_fit4, all_small, any_nonzero;

  logic [NPE-1:0] north_bit, south_bit;
  logic [NROW-1:0] west_bit, east_bit;

  assign prec_o = prec;

  // Simulation/elaboration guardrails. The checks remain active in RTL
  // verification but are hidden from older synthesis front ends.
  // synopsys translate_off
  initial begin
    if (NROW <= 0)             $fatal(1, "NROW must be positive");
    if ((NCOL_LOG <= 0) ||
        ((NCOL_LOG % 2) != 0)) $fatal(1, "NCOL_LOG must be positive and even");
    if (NPE != NCOL_LOG/2)     $fatal(1, "NPE must equal NCOL_LOG/2");
    if (MAX_UPDATES <= 0)      $fatal(1, "MAX_UPDATES must be positive");
  end
  // synopsys translate_on

  pde_tcu #(
    .CONV_ON_SMALL(CONV_ON_SMALL),
    .DYN_PREC(DYN_PREC),
    .MAX_UPDATES(MAX_UPDATES)
  ) u_tcu (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .read_start(read_start),
    .read_len(32'(16*2*NROW*NPE)),
    .all_fit12(all_fit12),
    .all_fit8(all_fit8),
    .all_fit4(all_fit4),
    .all_small(all_small),
    .any_nonzero(any_nonzero),
    .phase(phase),
    .prec(prec),
    .src_prec(src_prec),
    .bit_cnt(bit_cnt),
    .run_en(run_en),
    .commit(commit),
    .read_en(read_en),
    .first_update(first_update),
    .busy(busy),
    .done(done),
    .converged(converged),
    .update_cnt(update_cnt),
    .cycle_cnt(cycle_cnt)
  );

  pde_memcontrol #(
    .NROW(NROW),
    .NCOL_LOG(NCOL_LOG)
  ) u_boundary (
    .prec(prec),
    .bit_cnt(bit_cnt),
    .phase(phase),
    .first_update(first_update),
    .bnd_north_flat(bnd_north_flat),
    .bnd_south_flat(bnd_south_flat),
    .bnd_west_flat(bnd_west_flat),
    .bnd_east_flat(bnd_east_flat),
    .north_bit(north_bit),
    .south_bit(south_bit),
    .west_bit(west_bit),
    .east_bit(east_bit)
  );

  // Folded PE lattice, neighbour wiring, scan chain and reduction.
  logic [NROW-1:0][NPE-1:0] tx;
  logic [NPEALL-1:0] f12, f8, f4, sm, nz;
  logic [NPEALL:0] chain;

  assign chain[0]  = scan_in;
  assign scan_out  = chain[NPEALL];

  assign all_fit12   = &f12;
  assign all_fit8    = &f8;
  assign all_fit4    = &f4;
  assign all_small   = &sm;
  assign any_nonzero = |nz;

  genvar r, c;
  generate
    for (r = 0; r < NROW; r++) begin : g_row
      for (c = 0; c < NPE; c++) begin : g_col
        localparam int IDX = r*NPE + c;
        localparam bit R_ODD = bit'(r % 2);

        logic n_i, s_i, w_i, e_i;

        if (r == 0) begin : g_north_edge
          assign n_i = north_bit[c];
        end else begin : g_north_inner
          assign n_i = tx[r-1][c];
        end

        if (r == NROW-1) begin : g_south_edge
          assign s_i = south_bit[c];
        end else begin : g_south_inner
          assign s_i = tx[r+1][c];
        end

        if (c == 0) begin : g_west_edge
          assign w_i = west_bit[r];
        end else begin : g_west_inner
          assign w_i = tx[r][c-1];
        end

        if (c == NPE-1) begin : g_east_edge
          assign e_i = east_bit[r];
        end else begin : g_east_inner
          assign e_i = tx[r][c+1];
        end

        pe_top #(
          .ROW_ODD(R_ODD),
          .USE_DSM(USE_DSM)
        ) u_pe (
          .clk(clk),
          .rst_n(rst_n),
          .phase(phase),
          .prec(prec),
          .src_prec(src_prec),
          .bit_cnt(bit_cnt),
          .run_en(run_en),
          .commit(commit),
          .read_en(read_en),
          .n_bit_i(n_i),
          .s_bit_i(s_i),
          .e_bit_i(e_i),
          .w_bit_i(w_i),
          .tx_bit_o(tx[r][c]),
          .load_en(load_en),
          .load_red(load_red_flat[16*IDX +: 16]),
          .load_black(load_black_flat[16*IDX +: 16]),
          .fit12_o(f12[IDX]),
          .fit8_o(f8[IDX]),
          .fit4_o(f4[IDX]),
          .nonzero_o(nz[IDX]),
          .small_o(sm[IDX]),
          .scan_in(chain[IDX]),
          .scan_out(chain[IDX+1]),
          .u_red_o(u_red_flat[16*IDX +: 16]),
          .u_black_o(u_black_flat[16*IDX +: 16])
        );
      end
    end
  endgenerate

endmodule
