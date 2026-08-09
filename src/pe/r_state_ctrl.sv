// ============================================================================
// r_state_ctrl.sv : local control decode for one folded Red/Black PE
// ============================================================================
// The array-wide FSM is in pde_tcu. This module has no wide data and no
// arithmetic: it turns the broadcast phase/run/commit/read into bank selects,
// modes and write enables for the datapath around it.
// ============================================================================
module r_state_ctrl #(
  parameter bit ROW_ODD = 1'b0
)(
  input  logic       phase_i,       // 0: update Red, 1: update Black
  input  logic [4:0] bit_cnt_i,
  input  logic       run_en_i,
  input  logic       commit_i,
  input  logic       read_en_i,

  output logic       shift_en_o,
  output logic       red_compute_o,
  output logic       black_compute_o,
  output logic       dst_black_o,
  output logic       read_black_o,
  output logic       remote_east_o,
  output logic       alu_en_o,
  output logic       alu_clear_o,
  output logic       dsm_sel0_o,
  output logic       dsm_sel1_o,
  output logic       dsm_commit_o,
  output logic       scan_mode_o,
  output logic       u_red_we_o,
  output logic       u_black_we_o
);

  // In each checkerboard phase the source and destination banks are opposite
  // colours.
  assign dst_black_o     =  phase_i;
  assign red_compute_o   = ~phase_i;
  assign black_compute_o =  phase_i;

  assign shift_en_o  = run_en_i;
  assign alu_en_o    = run_en_i;
  assign alu_clear_o = ~run_en_i;

  // read_black_o picks which bank the single shared read path looks at.
  //   CK_A (run)    : the source bank, the one streaming out to neighbours
  //   CK_B (commit) : the destination bank, so the new residue can be read
  //                   back into the accumulator
  // The name deliberately says only "which bank", not "source" or
  // "destination", because that role changes between the two phases.
  assign read_black_o = run_en_i ? ~phase_i : dst_black_o;

  assign remote_east_o = ROW_ODD ^ phase_i;

  assign dsm_sel0_o   = (bit_cnt_i == 5'd0);
  assign dsm_sel1_o   = (bit_cnt_i == 5'd1);
  assign dsm_commit_o = commit_i;

  assign scan_mode_o  = read_en_i;
  assign u_red_we_o   = read_en_i || (commit_i && !phase_i);
  assign u_black_we_o = read_en_i || (commit_i &&  phase_i);

endmodule
