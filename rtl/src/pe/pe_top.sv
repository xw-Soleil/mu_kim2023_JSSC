// ============================================================================
// pe_top.sv : one folded Red/Black processing element
// ============================================================================
// A physical PE holds two horizontally adjacent logical points.
// They share one bit-serial ALU and one solution adder.
//
//   phase = 0 : source is Black -> compute/commit Red
//   phase = 1 : source is Red   -> compute/commit Black
//
// This file is wiring only. The parts live next door:
//   r_state_ctrl : decode the broadcast control
//   r_reg        : one residue bank per colour
//   r_alu        : the Fig. 8 bit-serial adder
//   r_dsm        : truncation error feedback
//   sol_acc      : accumulate and scan out
//   r_status     : flags for the array reduction
//
// The banks carry no per-bank precision tag. pde_tcu decodes which precision
// the source bank is stored at and broadcasts it as src_prec, so a PE never
// needs to know how phase is encoded.
//
// Key invariant: precision may only narrow, never widen. pde_tcu clamps it.
// ============================================================================
module pe_top #(
  parameter bit ROW_ODD = 1'b0,
  parameter bit USE_DSM = 1'b1,
  // 0 (synthesis default): loads are always P16, so pack_high folds to wires.
  // 1: loads are packed at the current prec, for testing pe_top standalone at
  //    a non-16-bit precision (see tb/tb_pe.sv).
  parameter bit LOAD_ANY_PREC = 1'b0
)(
  input  logic        clk,
  input  logic        rst_n,

  // broadcast control from pde_tcu
  input  logic        phase,
  input  logic [1:0]  prec,
  input  logic [1:0]  src_prec,      // precision the source bank is stored at
  input  logic [4:0]  bit_cnt,
  input  logic        run_en,
  input  logic        commit,
  input  logic        read_en,

  // serial residues from the neighbours
  input  logic        n_bit_i,
  input  logic        s_bit_i,
  input  logic        e_bit_i,
  input  logic        w_bit_i,
  output logic        tx_bit_o,

  // initial residue load
  input  logic        load_en,
  input  logic [15:0] load_red,
  input  logic [15:0] load_black,

  // status bits for the array-wide reduction
  output logic        fit12_o,
  output logic        fit8_o,
  output logic        fit4_o,
  output logic        nonzero_o,
  output logic        small_o,

  // solution scan/readout
  input  logic        scan_in,
  output logic        scan_out,
  output logic [15:0] u_red_o,
  output logic [15:0] u_black_o
);

  import pde_q8p7_pkg::*;

  localparam int DW = 16;
  localparam bit HEAD_IS_RED = ~ROW_ODD;

  // Local control decode.
  logic shift_en;
  logic red_compute, black_compute;
  logic dst_black, read_black;
  logic remote_east;
  logic alu_en, alu_clear;
  logic dsm_sel0, dsm_sel1, dsm_commit;
  logic scan_mode;
  logic u_red_we, u_black_we;

  r_state_ctrl #(.ROW_ODD(ROW_ODD)) u_ctrl (
    .phase_i(phase),
    .bit_cnt_i(bit_cnt),
    .run_en_i(run_en),
    .commit_i(commit),
    .read_en_i(read_en),
    .shift_en_o(shift_en),
    .red_compute_o(red_compute),
    .black_compute_o(black_compute),
    .dst_black_o(dst_black),
    .read_black_o(read_black),
    .remote_east_o(remote_east),
    .alu_en_o(alu_en),
    .alu_clear_o(alu_clear),
    .dsm_sel0_o(dsm_sel0),
    .dsm_sel1_o(dsm_sel1),
    .dsm_commit_o(dsm_commit),
    .scan_mode_o(scan_mode),
    .u_red_we_o(u_red_we),
    .u_black_we_o(u_black_we)
  );

  logic [DW-1:0] r_red_q, r_black_q;
  logic          red_ser_bit, black_ser_bit;
  logic          sum_bit, msb1_bit, msb0_bit;
  logic [2:0]    calc_bits;
  logic [DW-1:0] load_red_packed, load_black_packed;

  assign calc_bits = {msb0_bit, msb1_bit, sum_bit};

  // With LOAD_ANY_PREC=0 pack_high(v, P16) is the identity and folds to wires.
  assign load_red_packed   = LOAD_ANY_PREC ? pack_high(load_red,   prec)
                                           : load_red;
  assign load_black_packed = LOAD_ANY_PREC ? pack_high(load_black, prec)
                                           : load_black;

  r_reg u_r_red (
    .clk(clk), .rst_n(rst_n),
    .src_prec(src_prec),
    .load_en(load_en), .load_value(load_red_packed),
    .shift_en(shift_en), .compute(red_compute), .calc_bits(calc_bits),
    .q_o(r_red_q), .ser_bit_o(red_ser_bit)
  );

  r_reg u_r_black (
    .clk(clk), .rst_n(rst_n),
    .src_prec(src_prec),
    .load_en(load_en), .load_value(load_black_packed),
    .shift_en(shift_en), .compute(black_compute), .calc_bits(calc_bits),
    .q_o(r_black_q), .ser_bit_o(black_ser_bit)
  );

  // The one shared read path.
  // During a run it points at the source bank, the one being serialised out.
  // During a commit it points at the destination bank, so the residue just
  // computed can be accumulated and range-checked.
  logic [DW-1:0] read_value;
  assign read_value = unpack_high(read_black ? r_black_q : r_red_q, src_prec);
  assign tx_bit_o   = read_black ? black_ser_bit : red_ser_bit;

  // Neighbour receive path.
  logic h_remote, h_local, d_bit;
  assign h_remote = remote_east ? e_bit_i : w_bit_i;
  assign h_local  = tx_bit_o;

  r_dsm #(.USE_DSM(USE_DSM)) u_dsm (
    .clk(clk), .rst_n(rst_n),
    .shift_en(shift_en),
    .dsm_sel0(dsm_sel0), .dsm_sel1(dsm_sel1), .dsm_commit(dsm_commit),
    .dst_black(dst_black), .sum_bit(sum_bit),
    .d_bit_o(d_bit)
  );

  r_alu u_alu (
    .clk(clk), .rst_n(rst_n),
    .clr(alu_clear), .en(alu_en),
    .in_n(n_bit_i), .in_s(s_bit_i),
    .in_hl(h_local), .in_hr(h_remote), .in_d(d_bit),
    .sum_bit(sum_bit), .msb1_bit(msb1_bit), .msb0_bit(msb0_bit)
  );

  sol_acc #(.HEAD_IS_RED(HEAD_IS_RED)) u_sol (
    .clk(clk), .rst_n(rst_n),
    .scan_mode(scan_mode),
    .u_red_we(u_red_we), .u_black_we(u_black_we),
    .dst_black(dst_black), .add_value(read_value),
    .scan_in(scan_in), .scan_out(scan_out),
    .u_red_o(u_red_o), .u_black_o(u_black_o)
  );

  r_status u_status (
    .clk(clk), .rst_n(rst_n),
    .commit(commit), .dst_black(dst_black), .read_value(read_value),
    .fit12_o(fit12_o), .fit8_o(fit8_o), .fit4_o(fit4_o),
    .small_o(small_o), .nonzero_o(nonzero_o)
  );

endmodule
