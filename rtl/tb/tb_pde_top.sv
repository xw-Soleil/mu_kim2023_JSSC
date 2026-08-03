// ============================================================================
// tb_pde_top.sv : full-array test
// ============================================================================
// Test case: 2-D Laplace with a uniform Dirichlet boundary on all four sides.
// The analytic steady state is then u = C everywhere, so the run is
// self-checking without a reference solver.
//
// This bench
//   1. solves once with dynamic precision and records the cycle count;
//   2. solves again at fixed 16 bits (DYN_PREC=0) as the speed-up baseline;
//   3. dumps both grids for a bit-exact compare against golden_model.py;
//   4. shifts the solution out through the accumulator scan chain and checks
//      it against the values probed in parallel.
// ============================================================================
`timescale 1ns/1ps

`ifndef MIXED_P
`define MIXED_P 0
`endif

module tb_pde_top;
  import pde_q8p7_pkg::*;

  parameter int NROW     = `NROW_P;
  parameter int NCOL     = `NCOL_P;
  parameter int NPE      = NCOL/2;
  parameter int BND      = `BND_P;
  parameter bit MIXED    = `MIXED_P;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [16*NCOL-1:0]      bn_f, bs_f;
  logic [16*NROW-1:0]      bw_f, be_f;
  logic [16*NROW*NPE-1:0]  lr_f, lb_f;
  logic                    start, read_start, scan_in, load_en;

  // Dynamic-precision instance
  logic        busy_d, done_d, conv_d, so_d;
  logic [1:0]  prec_d;
  logic [31:0] upd_d, cyc_d;
  logic [16*NROW*NPE-1:0] ur_d, ub_d;

  pde_top #(.NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
            .DYN_PREC(1'b1), .MAX_UPDATES(2048)) dut_dyn (
    .clk(clk), .rst_n(rst_n), .start(start), .read_start(read_start),
    .bnd_north_flat(bn_f), .bnd_south_flat(bs_f),
    .bnd_west_flat(bw_f),  .bnd_east_flat(be_f),
    .load_en(load_en), .load_red_flat(lr_f), .load_black_flat(lb_f),
    .scan_in(scan_in), .scan_out(so_d),
    .busy(busy_d), .done(done_d), .converged(conv_d), .prec_o(prec_d),
    .update_cnt(upd_d), .cycle_cnt(cyc_d),
    .u_red_flat(ur_d), .u_black_flat(ub_d)
  );

  // Fixed 16-bit baseline
  logic        busy_f, done_f;
  logic [31:0] upd_f, cyc_f;
  logic [16*NROW*NPE-1:0] ur_f, ub_f;

  pde_top #(.NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
            .DYN_PREC(1'b0), .MAX_UPDATES(2048)) dut_fix (
    .clk(clk), .rst_n(rst_n), .start(start), .read_start(1'b0),
    .bnd_north_flat(bn_f), .bnd_south_flat(bs_f),
    .bnd_west_flat(bw_f),  .bnd_east_flat(be_f),
    .load_en(load_en), .load_red_flat(lr_f), .load_black_flat(lb_f),
    .scan_in(1'b0), .scan_out(),
    .busy(busy_f), .done(done_f), .converged(), .prec_o(),
    .update_cnt(upd_f), .cycle_cnt(cyc_f),
    .u_red_flat(ur_f), .u_black_flat(ub_f)
  );

  // Unfold the two banks back into the logical grid.
  //   even rows : 2c is Red,   2c+1 is Black    (Red where (i+j) is even)
  //   odd rows  : 2c is Black, 2c+1 is Red
  function automatic integer get_u(input logic [16*NROW*NPE-1:0] ur,
                                   input logic [16*NROW*NPE-1:0] ub,
                                   input int i, input int j);
    int c, idx;
    logic [15:0] v;
    begin
      c   = j/2;
      idx = i*NPE + c;
      if ((i + j) % 2 == 0) v = ur[16*idx +: 16];   // Red
      else                  v = ub[16*idx +: 16];   // Black
      get_u = $signed(v);
    end
  endfunction

  task dump(input string fname,
            input logic [16*NROW*NPE-1:0] ur,
            input logic [16*NROW*NPE-1:0] ub);
    int fd, i, j;
    begin
      fd = $fopen(fname, "w");
      if (!fd) $fatal(1, "cannot open %s for writing", fname);
      for (i = 0; i < NROW; i++) begin
        for (j = 0; j < NCOL; j++) $fwrite(fd, "%0d ", get_u(ur, ub, i, j));
        $fwrite(fd, "\n");
      end
      $fclose(fd);
    end
  endtask

  int errors = 0;
  int i, j, k, maxerr, v, exp_scan, bnd_mag;
  int scan_idx, scan_side, scan_col;
  int exp_grid [0:NROW-1][0:NCOL-1];
  logic [31:0] cyc_before_scan;
  logic [15:0] sc_word;

  initial begin
    start = 0; read_start = 0; scan_in = 0; load_en = 0;
    lr_f = '0; lb_f = '0;
    for (i = 0; i < NCOL; i++) begin
      bn_f[16*i +: 16] = MIXED ? 16'( 100 + 11*i) : 16'(BND);
      bs_f[16*i +: 16] = MIXED ? 16'(-200 -  7*i) : 16'(BND);
    end
    for (i = 0; i < NROW; i++) begin
      bw_f[16*i +: 16] = MIXED ? 16'( 300 + 13*i) : 16'(BND);
      be_f[16*i +: 16] = MIXED ? 16'(-400 + 17*i) : 16'(BND);
    end

    repeat (3) @(negedge clk);
    rst_n = 1;
    @(negedge clk);

    $display("");
    if (MIXED)
      $display("=== %0dx%0d Laplace, nonuniform mixed-sign boundaries ===",
               NROW, NCOL);
    else
      $display("=== %0dx%0d Laplace, uniform boundary %0d ===",
               NROW, NCOL, BND);

    start = 1; @(negedge clk); start = 0;
    wait (done_d && done_f);
    @(negedge clk);

    // Accuracy check for uniform boundaries: the exact solution is BND
    // everywhere. Mixed boundaries are checked point by point by
    // check_golden.py instead.
    maxerr = 0;
    bnd_mag = (BND < 0) ? -BND : BND;
    for (i = 0; i < NROW; i++)
      for (j = 0; j < NCOL; j++) begin
        v = get_u(ur_d, ub_d, i, j);
        exp_grid[i][j] = v;  // save before the readout shift destroys it
        if (!MIXED) begin
          if (v > BND) begin if (v-BND > maxerr) maxerr = v-BND; end
          else         begin if (BND-v > maxerr) maxerr = BND-v; end
        end
      end
    $display("  converged            : %0d", conv_d);
    if (!MIXED)
      $display("  max |u - exact|      : %0d  (%0d%% of |boundary|)",
               maxerr, bnd_mag ? (100*maxerr)/bnd_mag : 0);
    if (!conv_d)          begin $display("  FAIL did not converge"); errors++; end
    if (!MIXED && (maxerr*10 > bnd_mag)) begin
      $display("  FAIL error over 10%%"); errors++;
    end

    // Cycle count: dynamic precision vs fixed 16 bits
    $display("");
    $display("  dynamic precision    : %0d updates, %0d cycles", upd_d, cyc_d);
    $display("  fixed 16-bit         : %0d updates, %0d cycles", upd_f, cyc_f);
    if (cyc_d > 0)
      $display("  speed-up             : %0d.%0d%0d x",
               (cyc_f*100)/cyc_d/100, ((cyc_f*100)/cyc_d/10)%10,
               ((cyc_f*100)/cyc_d)%10);
    if (cyc_d >= cyc_f) begin
      $display("  FAIL dynamic precision is not faster"); errors++;
    end
    if (upd_d != upd_f) begin
      $display("  FAIL dynamic/fixed update counts differ"); errors++;
    end

    dump("u_dyn.txt", ur_d, ub_d);
    dump("u_fix.txt", ur_f, ub_f);

    // Scan-chain readout, checked word by word. PEs come out in reverse
    // order, and within a PE the logically right-hand (tail) bank leads.
    cyc_before_scan = cyc_d;
    read_start = 1; @(negedge clk); read_start = 0;
    for (scan_idx = NROW*NPE-1; scan_idx >= 0; scan_idx--) begin
      i = scan_idx / NPE;
      scan_col = scan_idx % NPE;
      for (scan_side = 1; scan_side >= 0; scan_side--) begin
        j = 2*scan_col + scan_side;
        exp_scan = exp_grid[i][j];
        sc_word = '0;
        for (k = 0; k < 16; k++) begin
          sc_word = {so_d, sc_word[15:1]};
          @(negedge clk);
        end
        if ($signed(sc_word) !== exp_scan) begin
          $display("  FAIL scan u[%0d][%0d]: got %0d expected %0d",
                   i, j, $signed(sc_word), exp_scan);
          errors++;
        end
      end
    end
    $display("");
    $display("  scan-chain words checked: %0d", NROW*NCOL);
    if (!done_d) begin $display("  FAIL readout did not return to DONE"); errors++; end
    if (cyc_d != cyc_before_scan) begin
      $display("  FAIL readout changed solver cycle count"); errors++;
    end

    $display("");
    if (errors == 0) begin
      $display("tb_pde_top : PASS");
      $display("");
      $finish;
    end else begin
      $fatal(1, "tb_pde_top : FAIL (%0d errors)", errors);
    end
  end

  initial begin
    #20_000_000;
    $fatal(1, "tb_pde_top : TIMEOUT");
  end

endmodule
