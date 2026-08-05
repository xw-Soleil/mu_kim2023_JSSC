// ============================================================================
// tb_pe_smoke.sv : single-PE arithmetic and range detection
// ============================================================================
// Reproduces the worked example of Mu & Kim, JSSC'23 Fig. 10:
//
//   8-bit mode : neighbours 39, -25, 13, 51 -> 78/4 = 19.5 -> accumulate 19
//   4-bit mode : neighbours  5,  -2,  3,  6 -> 12/4 = 3    -> total     22
//
// The 4-bit step also exercises the delta-sigma path: the remainder 2 left
// over from the first step is fed back, so the effective sum is 14 and
// floor(14/4) is still 3, matching the paper.
//
// All stimulus is driven on the negative edge, so it never races the DUT's
// positive-edge sampling.
// ============================================================================
`timescale 1ns/1ps

module tb_pe_smoke;
  import pde_q8p7_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        phase, run_en, commit, read_en, load_en;
  logic [1:0]  prec;
  logic [4:0]  bit_cnt;
  logic        n_i, s_i, e_i, w_i, tx;
  logic [15:0] load_red, load_black;
  logic [15:0] u_red, u_black;
  logic        f12, f8, f4, nz, sm;

  // src_prec is tied to prec: do_load refreshes both banks before every run,
  // so a bank never holds data left at the previous precision.
  // LOAD_ANY_PREC=1 because this bench deliberately loads at 8 and 4 bits to
  // exercise the pack/unpack path; the real chip defaults to 0.
  pe_top #(.ROW_ODD(1'b0), .USE_DSM(1'b1), .LOAD_ANY_PREC(1'b1)) dut (
    .clk(clk), .rst_n(rst_n),
    .phase(phase), .prec(prec), .src_prec(prec), .bit_cnt(bit_cnt),
    .run_en(run_en), .commit(commit), .read_en(read_en),
    .n_bit_i(n_i), .s_bit_i(s_i), .e_bit_i(e_i), .w_bit_i(w_i),
    .tx_bit_o(tx),
    .load_en(load_en), .load_red(load_red), .load_black(load_black),
    .fit12_o(f12), .fit8_o(f8), .fit4_o(f4), .nonzero_o(nz), .small_o(sm),
    .scan_in(1'b0), .scan_out(),
    .u_red_o(u_red), .u_black_o(u_black)
  );

  function automatic logic ser(input logic [15:0] v, input int k, input int b);
    ser = (k < b) ? v[k] : v[15];
  endfunction

  int errors = 0;
  logic [2:0] last_calc_bits;
  task check(input string name, input int got, input int exp);
    if (got !== exp) begin
      $display("  FAIL %-26s got %0d, expected %0d", name, got, exp);
      errors = errors + 1;
    end else
      $display("  ok   %-26s = %0d", name, got);
  endtask

  task do_load(input logic [15:0] vr, input logic [15:0] vb);
    begin
      @(negedge clk); load_red = vr; load_black = vb; load_en = 1'b1;
      @(negedge clk); load_en = 1'b0;
    end
  endtask

  // Pulse commit once for Red then once for Black, so r_status latches and
  // merges the live range checks of both banks.
  // The fit flags are latched outputs, not combinational, because the shared
  // read path sees only one bank at a time.
  task automatic latch_status;
    begin
      phase = 1'b0; run_en = 1'b0;
      @(negedge clk); commit = 1'b1;
      @(negedge clk); commit = 1'b0;
      phase = 1'b1;
      @(negedge clk); commit = 1'b1;
      @(negedge clk); commit = 1'b0;
      phase = 1'b0;
    end
  endtask

  // One Red update phase: three external neighbours plus the local Black bank.
  task run_red_phase(input logic [15:0] vn, input logic [15:0] vs,
                     input logic [15:0] vw, input int b);
    int k;
    begin
      @(negedge clk); phase = 1'b0; run_en = 1'b1; commit = 1'b0;
      for (k = 0; k < b; k++) begin
        bit_cnt = k[4:0];
        n_i = ser(vn,k,b); s_i = ser(vs,k,b); w_i = ser(vw,k,b); e_i = 1'b0;
        // Sample just before the MSB clock edge, while carry_q still holds
        // the previous bit's state, so Sum/MSB1/MSB0 can be checked directly.
        if (k == b-1) begin
          #1;
          last_calc_bits = dut.calc_bits;
        end
        @(negedge clk);
      end
      run_en = 1'b0; bit_cnt = 5'd0; n_i = 0; s_i = 0; w_i = 0;
      @(negedge clk); commit = 1'b1;
      @(negedge clk); commit = 1'b0;
    end
  endtask

  initial begin
    phase=0; prec=P16; bit_cnt=0; run_en=0; commit=0; read_en=0;
    load_en=0; load_red=0; load_black=0; n_i=0; s_i=0; e_i=0; w_i=0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    $display("");
    $display("=== step 1 : 8-bit,  39 + (-25) + 13 + 51 = 78,  78/4 -> 19 ===");
    prec = P8;
    do_load(16'sd0, 16'sd51);          // local horizontal neighbour = 51
    run_red_phase(16'sd39, -16'sd25, 16'sd13, 8);
    check("r_red", $signed(unpack_high(dut.r_red_q, prec)), 19);
    check("u_red",         $signed(u_red),         19);
    check("dsm remainder", dut.u_dsm.err_red_q, 2);
    check("{MSB0,MSB1,Sum}", last_calc_bits,     3'b000);

    $display("");
    $display("=== step 2 : 4-bit,   5 + (-2) + 3 + 6 = 12, +dsm 2 -> 3 ===");
    prec = P4;
    do_load(16'sd0, 16'sd6);           // reload residues, DSM error persists
    run_red_phase(16'sd5, -16'sd2, 16'sd3, 4);
    check("r_red", $signed(unpack_high(dut.r_red_q, prec)), 3);
    check("u_red (accumulated)",  $signed(u_red), 22);
    check("{MSB0,MSB1,Sum}", last_calc_bits, 3'b001);

    $display("");
    $display("=== step 3 : negative MSB parallel correction ===");
    @(negedge clk); rst_n = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
    prec = P4;
    do_load(16'sd0, -16'sd1);
    run_red_phase(-16'sd1, -16'sd1, -16'sd1, 4);
    check("{MSB0,MSB1,Sum}", last_calc_bits, 3'b111);
    check("(-1-1-1-1) >>> 2",
          $signed(unpack_high(dut.r_red_q, prec)), -1);

    $display("");
    $display("=== step 4 : precision range detection ===");
    prec = P16;
    do_load(16'sd7, 16'sd0);   latch_status; check("fit4  (r=7) ", f4, 1);
                              check("fit8  (r=7) ", f8, 1);
    do_load(16'sd8, 16'sd0);   latch_status; check("fit4  (r=8) ", f4, 0);
                              check("fit8  (r=8) ", f8, 1);
    do_load(-16'sd8, 16'sd0);  latch_status; check("fit4  (r=-8)", f4, 1);
    do_load(-16'sd9, 16'sd0);  latch_status; check("fit4  (r=-9)", f4, 0);
    do_load(16'sd2048, 16'sd0);latch_status; check("fit12 (2048)", f12, 0);
    do_load(16'sd2047, 16'sd0);latch_status; check("fit12 (2047)", f12, 1);
    do_load(-16'sd1, 16'sd1);  latch_status; check("small  (-1,+1)", sm, 1);
    do_load(-16'sd2, 16'sd0);  latch_status; check("small  (-2, 0)", sm, 0);
    do_load(16'sd2, 16'sd0);   latch_status; check("small  (+2, 0)", sm, 0);

    $display("");
    $display("=== step 5 : non-destructive serialisation (rotate) ===");
    // A bank must come back unchanged after B cycles of shifting out.
    prec = P8;
    do_load(16'sd0, -16'sd25);
    run_red_phase(16'sd0, 16'sd0, 16'sd0, 8);
    check("r_black preserved",
          $signed(unpack_high(dut.r_black_q, prec)), -25);

    $display("");
    if (errors == 0) begin
      $display("tb_pe_smoke : PASS");
      $display("");
      $finish;
    end else begin
      $fatal(1, "tb_pe_smoke : FAIL (%0d errors)", errors);
    end
  end

endmodule
