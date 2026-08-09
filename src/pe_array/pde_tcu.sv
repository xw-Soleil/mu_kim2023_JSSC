// ============================================================================
// pde_tcu.sv : timing and control unit (FSM, dynamic precision, convergence)
// ============================================================================
//   S_IDLE        wait for start, precision resets to 16 bits
//   S_RED_RUN     B cycles : Black serialises out, Red computes
//   S_RED_CMT     1 cycle  : u_red += r_red, DSM error latched
//   S_BLACK_RUN   B cycles : Red serialises out, Black computes
//   S_BLACK_CMT   1 cycle  : u_black += r_black
//   S_CHECK       1 cycle  : array reduction -> next precision / converged
//   S_DONE        idle, solution readable
//   S_READ        shift the accumulator chain out
//
//   Cycles per full grid update  C = 2*B + 3
//     B=16 -> 35 | B=12 -> 27 | B=8 -> 19 | B=4 -> 11
//
// Dynamic precision is the second departure from the reference paper.
// There Ser[1:0] follows a schedule computed offline. Here each PE reports
// whether its two residues still fit in 12/8/4 bits, the array ANDs those
// flags, and the controller narrows the datapath on its own. No offline
// characterisation of the residue decay is needed.
//
// src_prec tells every PE which precision the bank it is about to read is
// stored at. The answer is identical array-wide, so it is decoded once here
// instead of in 200 PEs, and a PE never has to know how phase is encoded.
// That removes the per-bank precision tag registers from every PE.
//
// Key invariant: precision may only narrow, never widen. See prec_next.
// ============================================================================
module pde_tcu #(
  parameter bit CONV_ON_SMALL = 1'b1,   // 1: stop at |r|<=1, 0: stop at r==0
  parameter bit DYN_PREC      = 1'b1,   // 0: fixed 16 bits (A/B baseline)
  parameter int MAX_UPDATES   = 4096
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        start,
  input  logic        read_start,
  input  logic [31:0] read_len,        // number of scan shifts

  // array reduction inputs
  input  logic        all_fit12,
  input  logic        all_fit8,
  input  logic        all_fit4,
  input  logic        all_small,
  input  logic        any_nonzero,

  // broadcast control
  output logic        phase,
  output logic [1:0]  prec,
  output logic [1:0]  src_prec,        // physical precision of the source bank
  output logic [4:0]  bit_cnt,
  output logic        run_en,
  output logic        commit,
  output logic        read_en,
  output logic        first_update,    // gates boundary injection

  // status
  output logic        busy,
  output logic        done,
  output logic        converged,
  output logic [31:0] update_cnt,
  output logic [31:0] cycle_cnt
);

  import pde_q8p7_pkg::*;

  typedef enum logic [2:0] {
    S_IDLE, S_RED_RUN, S_RED_CMT, S_BLACK_RUN, S_BLACK_CMT, S_CHECK, S_DONE, S_READ
  } state_e;

  state_e      state_q, state_d;
  logic [4:0]  bit_q;
  logic [1:0]  prec_q, prec_d, prec_prev_q;
  logic [31:0] upd_q, cyc_q, rd_q;
  logic        conv_q, first_q;

  logic [4:0]  run_len;
  logic        bit_terminal;
  assign run_len = 5'(run_cycles(prec_q) - 1);   // terminal count value

  counter_ce #(.WIDTH(5)) u_bit_counter (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .clear_i          (!run_en),
    .enable_i         (run_en),
    .terminal_count_i (run_len),
    .count_o          (bit_q),
    .terminal_o       (bit_terminal)
  );

  assign phase        = (state_q == S_BLACK_RUN) || (state_q == S_BLACK_CMT);
  assign prec         = prec_q;
  assign bit_cnt      = bit_q;
  assign run_en       = (state_q == S_RED_RUN) || (state_q == S_BLACK_RUN);
  assign commit       = (state_q == S_RED_CMT) || (state_q == S_BLACK_CMT);
  assign read_en      = (state_q == S_READ);
  assign first_update = first_q;
  assign busy         = (state_q != S_IDLE) && (state_q != S_DONE);
  assign done         = (state_q == S_DONE);
  assign converged    = conv_q;
  assign update_cnt   = upd_q;
  assign cycle_cnt    = cyc_q;

  // Physical precision of the source bank.
  // Only the Red-phase run reads Black, which was written last update and has
  // not been rewritten yet, so it may still sit at the previous precision.
  // Everything else reads data written at the current precision: the
  // Black-phase run reads Red, just written this update, and every commit
  // cycle reads the destination bank that was computed a moment ago.
  assign src_prec = (run_en && !phase) ? prec_prev_q : prec_q;

  // Priority encoder for the next precision: the narrowest width that fits.
  assign prec_d = !DYN_PREC ? P16
                : all_fit4      ? P4
                : all_fit8      ? P8
                : all_fit12     ? P12
                                : P16;

  // Precision may only narrow, never widen.
  // The transition scheme in r_reg reads a bank at its old tap position, which
  // is correct only on the way down, where the low bits of the old layout are
  // already the complete value. Widening (say P4->P8) would expose q[11:8],
  // which holds rotate and shift garbage.
  // The convergence algorithm guarantees residues only decay, so this never
  // fires -- but that is an algorithm property, and a 2-bit comparator turns
  // it into a hardware one.
  // Encoding P16(00) < P12(01) < P8(10) < P4(11) runs narrow-to-wide, so
  // taking the larger of the two means "narrow only".
  logic [1:0] prec_next;
  assign prec_next = (prec_d > prec_q) ? prec_d : prec_q;

  logic conv_hit;
  assign conv_hit = CONV_ON_SMALL ? all_small : ~any_nonzero;

  // State transitions.
  always_comb begin
    state_d = state_q;
    case (state_q)
      S_IDLE      : if (start)              state_d = S_RED_RUN;
      S_RED_RUN   : if (bit_terminal)       state_d = S_RED_CMT;
      S_RED_CMT   :                         state_d = S_BLACK_RUN;
      S_BLACK_RUN : if (bit_terminal)       state_d = S_BLACK_CMT;
      S_BLACK_CMT :                         state_d = S_CHECK;
      S_CHECK     : if (conv_hit || (upd_q >= MAX_UPDATES-1)) state_d = S_DONE;
                    else                    state_d = S_RED_RUN;
      S_DONE      : if (read_start)         state_d = S_READ;
      S_READ      : if (rd_q >= read_len-1) state_d = S_DONE;
      default     :                         state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= S_IDLE;
      prec_q      <= P16;
      prec_prev_q <= P16;
      upd_q       <= 32'd0;
      cyc_q       <= 32'd0;
      rd_q        <= 32'd0;
      conv_q      <= 1'b0;
      first_q     <= 1'b1;
    end else begin
      state_q <= state_d;

      if (state_q == S_READ) rd_q <= rd_q + 1'b1;
      else                   rd_q <= 32'd0;

      // cycle_cnt measures solve latency only; readout has its own length.
      if (busy && (state_q != S_READ)) cyc_q <= cyc_q + 1'b1;

      if (state_q == S_IDLE && start) begin
        upd_q       <= 32'd0;
        cyc_q       <= 32'd0;
        conv_q      <= 1'b0;
        first_q     <= 1'b1;
        prec_q      <= P16;
        prec_prev_q <= P16;
      end

      if (state_q == S_CHECK) begin
        upd_q       <= upd_q + 1'b1;
        first_q     <= 1'b0;         // boundaries apply to update 0 only
        prec_prev_q <= prec_q;       // this update's precision becomes "prev"
        prec_q      <= prec_next;    // adopt the narrower datapath
        if (conv_hit) conv_q <= 1'b1;
        // Simulation only. If the clamp ever engages, residues have grown
        // back and the monotonic-narrowing property no longer holds for this
        // problem, so the r_reg transition scheme needs revisiting.
        // No regression case triggers this today.
        // synopsys translate_off
        if (prec_d < prec_q)
          $display("[pde_tcu] WARNING: precision tried to widen (prec_d=%0d < prec_q=%0d) @update %0d, clamped",
                   prec_d, prec_q, upd_q);
        // synopsys translate_on
      end
    end
  end

endmodule
