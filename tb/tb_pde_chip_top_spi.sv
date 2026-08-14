// ============================================================================
// tb_pde_chip_top_spi.sv : full-chip test through the SPI-lite interface
// ============================================================================
// Drives pde_chip_top_spi exclusively through its nine chip pins, the way a
// bench master would: mode-0 SPI frames per docs/spi_interface_spec.md, with
// randomized SCLK phase and per-edge jitter, then the slow-clock readout mode
// (core clock divided by ten) for the scan stream.  Results are checked two
// ways: word-exact against a reference pde_top instance, and dumped to
// u_dyn.txt for the external golden-model comparison run by the Makefile.
//
//   +SCLK_RATIO=<n>  SCLK period as a multiple of the clk period (default 10,
//                    spec minimum 8; smaller values are expected to fail and
//                    are used by the sweep target to locate the break point).
`timescale 1ns/1ps

`ifndef NROW_P
`define NROW_P 20
`endif
`ifndef NCOL_P
`define NCOL_P 20
`endif

module tb_pde_chip_top_spi;
  localparam int NROW = `NROW_P;
  localparam int NCOL = `NCOL_P;
  localparam int BND = 4096;
  localparam int MAX_UPDATES = 4096;
  localparam int NPE = NCOL/2;
  localparam int NPEALL = NROW*NPE;
  localparam int GRID_WORDS = NROW*NCOL;
  localparam int TOTAL_BITS = 16*GRID_WORDS;

  localparam logic [15:0] A_CONTROL = 16'h0000;
  localparam logic [15:0] A_STATUS = 16'h0001;
  localparam logic [15:0] A_UPDATE_LO = 16'h0002;
  localparam logic [15:0] A_UPDATE_HI = 16'h0003;
  localparam logic [15:0] A_CYCLE_LO = 16'h0004;
  localparam logic [15:0] A_CYCLE_HI = 16'h0005;
  localparam logic [15:0] A_NROW = 16'h0006;
  localparam logic [15:0] A_NCOL = 16'h0007;
  localparam logic [15:0] A_RED = 16'h1000;
  localparam logic [15:0] A_BLACK = 16'h2000;
  localparam logic [15:0] A_NORTH = 16'h3000;
  localparam logic [15:0] A_SOUTH = 16'h3400;
  localparam logic [15:0] A_WEST = 16'h3800;
  localparam logic [15:0] A_EAST = 16'h3c00;

  localparam int ST_BUSY = 0;
  localparam int ST_DONE = 1;
  localparam int ST_CONVERGED = 2;
  localparam int ST_SCAN_ACTIVE = 5;
  localparam int ST_CFG_ERROR = 6;
  localparam int ST_CFG_COMPLETE = 7;
  localparam int ST_SCAN_USED = 8;

  // Variable-period core clock: halved period in ns, changed at runtime for
  // the slow-clock readout rehearsal.
  real core_half_ns = 5.0;
  logic clk = 1'b0;
  always #(core_half_ns) clk = ~clk;

  logic rst_n = 1'b0;
  logic sclk = 1'b0, cs_n = 1'b1, mosi = 1'b0;
  logic miso;
  logic scan_out, scan_valid, scan_last;

  integer sclk_ratio;
  real sclk_half_ns;

  pde_chip_top_spi #(
    .NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
    .CONV_ON_SMALL(1'b1), .DYN_PREC(1'b1),
    .MAX_UPDATES(MAX_UPDATES)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso),
    .scan_out(scan_out), .scan_valid(scan_valid), .scan_last(scan_last)
  );

  // Reference model: the array core driven directly, as in the other chip TBs.
  logic [16*NCOL-1:0] ref_bn, ref_bs;
  logic [16*NROW-1:0] ref_bw, ref_be;
  logic [16*NPEALL-1:0] ref_lr, ref_lb, ref_ur, ref_ub;
  logic ref_start, ref_load_en, ref_done, ref_converged;
  logic [31:0] ref_updates, ref_cycles;

  pde_top #(
    .NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
    .CONV_ON_SMALL(1'b1), .DYN_PREC(1'b1),
    .MAX_UPDATES(MAX_UPDATES)
  ) u_reference (
    .clk(clk), .rst_n(rst_n), .start(ref_start), .read_start(1'b0),
    .bnd_north_flat(ref_bn), .bnd_south_flat(ref_bs),
    .bnd_west_flat(ref_bw), .bnd_east_flat(ref_be),
    .load_en(ref_load_en), .load_red_flat(ref_lr), .load_black_flat(ref_lb),
    .scan_in(1'b0), .scan_out(), .busy(), .done(ref_done),
    .converged(ref_converged), .prec_o(),
    .update_cnt(ref_updates), .cycle_cnt(ref_cycles),
    .u_red_flat(ref_ur), .u_black_flat(ref_ub)
  );

  integer errors = 0;
  task automatic fail(input string message);
    begin
      $display("  FAIL: %s", message);
      errors = errors + 1;
    end
  endtask

  // Cross-check that only legal frames reach the internal cfg bus.
  integer bus_writes = 0, bus_reads = 0;
  integer exp_writes = 0, exp_reads = 0;
  always @(posedge clk) begin
    if (dut.cfg_valid) begin
      if (dut.cfg_write) bus_writes = bus_writes + 1;
      else               bus_reads = bus_reads + 1;
    end
    if (dut.u_spi.bit_cnt_q > 6'd40)
      fail("bridge bit counter exceeded 40");
  end

  // ---------------------------------------------------------------------
  // SPI master model: mode 0, MSB first, one 40-bit frame per CS_N low,
  // per-edge jitter of +/-10 percent of the half period.
  // ---------------------------------------------------------------------
  function automatic real jitter_half();
    jitter_half = sclk_half_ns
                * (1.0 + (real'($urandom_range(0, 200)) - 100.0)/1000.0);
  endfunction

  task automatic spi_xfer(input logic [39:0] frame, input integer nbits,
                          output logic [15:0] rdata);
    integer b;
    begin
      rdata = '0;
      cs_n = 1'b0;
      #(sclk_half_ns);
      for (b = 0; b < nbits; b = b + 1) begin
        mosi = frame[39-b];
        #(jitter_half());
        sclk = 1'b1;
        if (b >= 24) rdata = {rdata[14:0], miso};
        #(jitter_half());
        sclk = 1'b0;
      end
      #(sclk_half_ns);
      cs_n = 1'b1;
      mosi = 1'b0;
      #(4.0*sclk_half_ns + real'($urandom_range(0, 37)));
    end
  endtask

  task automatic spi_write(input logic [15:0] address,
                           input logic [15:0] data);
    logic [15:0] unused;
    begin
      spi_xfer({8'h80, address, data}, 40, unused);
      exp_writes = exp_writes + 1;
    end
  endtask

  task automatic spi_read(input logic [15:0] address,
                          output logic [15:0] data);
    begin
      spi_xfer({8'h00, address, 16'h0000}, 40, data);
      exp_reads = exp_reads + 1;
    end
  endtask

  function automatic logic [15:0] reference_word(input integer logical_idx);
    integer row, col, pe_idx;
    begin
      row = logical_idx / NCOL;
      col = logical_idx % NCOL;
      pe_idx = row*NPE + col/2;
      reference_word = (((row+col) % 2) == 0)
                     ? ref_ur[16*pe_idx +: 16]
                     : ref_ub[16*pe_idx +: 16];
    end
  endfunction

  // Scan capture, run concurrently with the READ command frame so the
  // backpressure-free stream is never missed.
  logic [15:0] grid_mem [0:GRID_WORDS-1];
  integer scan_bits, scan_words, scan_last_count;

  task automatic capture_scan();
    logic [15:0] scan_shift;
    integer bit_in_word, expected_idx;
    begin
      scan_shift = '0; bit_in_word = 0;
      scan_bits = 0; scan_words = 0; scan_last_count = 0;
      while (scan_bits < TOTAL_BITS) begin
        @(posedge clk);
        if (scan_last && !scan_valid) fail("scan_last without scan_valid");
        if (scan_valid) begin
          if (scan_last !== (scan_bits == TOTAL_BITS-1))
            fail($sformatf("scan_last at bit %0d", scan_bits));
          if (scan_last) scan_last_count = scan_last_count + 1;
          scan_shift = {scan_out, scan_shift[15:1]};
          if (bit_in_word == 15) begin
            expected_idx = GRID_WORDS-1-scan_words;
            grid_mem[expected_idx] = scan_shift;
            if (scan_shift !== reference_word(expected_idx))
              fail($sformatf("word %0d/grid %0d got %04h expected %04h",
                             scan_words, expected_idx, scan_shift,
                             reference_word(expected_idx)));
            scan_words = scan_words + 1;
            bit_in_word = 0;
          end else bit_in_word = bit_in_word + 1;
          scan_bits = scan_bits + 1;
        end
      end
    end
  endtask

  logic [15:0] status_word, lo_word, hi_word, rd_word, unused_word;
  logic [31:0] chip_updates, chip_cycles;
  integer i, polls, wr_snapshot, fd, row, col;

  initial begin
    if (!$value$plusargs("SCLK_RATIO=%d", sclk_ratio)) sclk_ratio = 10;
    sclk_half_ns = real'(sclk_ratio) * core_half_ns;
    $display("\n=== pde_chip_top_spi %0dx%0d, SCLK ratio %0d ===",
             NROW, NCOL, sclk_ratio);

    ref_start = 0; ref_load_en = 0;
    ref_lr = 0; ref_lb = 0; ref_bn = 0; ref_bs = 0; ref_bw = 0; ref_be = 0;
    for (i = 0; i < NCOL; i = i + 1) begin
      ref_bn[16*i +: 16] = 16'(BND);
      ref_bs[16*i +: 16] = 16'(BND);
    end
    for (i = 0; i < NROW; i = i + 1) begin
      ref_bw[16*i +: 16] = 16'(BND);
      ref_be[16*i +: 16] = 16'(BND);
    end

    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    #(real'($urandom_range(0, 97)));   // random SCLK-vs-clk phase

    // --- interface smoke: dimension registers over SPI -------------------
    spi_read(A_NROW, rd_word);
    if (rd_word != NROW) fail("NROW register mismatch over SPI");
    spi_read(A_NCOL, rd_word);
    if (rd_word != NCOL) fail("NCOL register mismatch over SPI");

    // --- frame-robustness tests (before configuration) -------------------
    wr_snapshot = bus_writes;
    spi_xfer({8'h80, A_CONTROL, 16'h0001}, 17, unused_word);  // short frame
    spi_xfer({8'h82, A_CONTROL, 16'h0001}, 40, unused_word);  // reserved bit
    repeat (8) @(posedge clk);
    if (bus_writes != wr_snapshot)
      fail("discarded frame reached the cfg bus");
    spi_read(A_STATUS, status_word);
    if (status_word[ST_BUSY] || status_word[ST_CFG_ERROR])
      fail("discarded frame disturbed chip state");

    spi_write(16'h0008, 16'h1234);              // illegal address
    spi_read(A_STATUS, status_word);
    if (!status_word[ST_CFG_ERROR]) fail("illegal write did not set error");
    spi_write(A_CONTROL, 16'h0004);             // clear
    spi_read(A_STATUS, status_word);
    if (status_word[ST_CFG_ERROR]) fail("error clear failed");

    // --- configuration ----------------------------------------------------
    for (i = 0; i < NPEALL; i = i + 1) begin
      spi_write(A_RED+i, 16'd0);
      spi_write(A_BLACK+i, 16'd0);
    end
    for (i = 0; i < NCOL; i = i + 1) begin
      spi_write(A_NORTH+i, 16'(BND));
      spi_write(A_SOUTH+i, 16'(BND));
    end
    for (i = 0; i < NROW; i = i + 1) begin
      spi_write(A_WEST+i, 16'(BND));
      spi_write(A_EAST+i, 16'(BND));
    end
    spi_read(A_STATUS, status_word);
    if (!status_word[ST_CFG_COMPLETE]) fail("cfg_complete is low");
    if (status_word[ST_CFG_ERROR]) fail("legal configuration set cfg_error");

    // --- solve ------------------------------------------------------------
    @(negedge clk);
    ref_load_en = 1; ref_start = 1;
    @(negedge clk);
    ref_load_en = 0; ref_start = 0;
    spi_write(A_CONTROL, 16'h0001);

    polls = 0;
    status_word = 0;
    while (!status_word[ST_DONE] && polls < 20000) begin
      spi_read(A_STATUS, status_word);
      polls = polls + 1;
    end
    if (!status_word[ST_DONE]) fail("chip did not reach DONE");
    if (status_word[ST_BUSY]) fail("busy remained high in DONE");
    if (!status_word[ST_CONVERGED]) fail("chip did not converge");
    if (!ref_done) wait (ref_done);
    if (!ref_converged) fail("reference did not converge");

    spi_read(A_UPDATE_LO, lo_word);
    spi_read(A_UPDATE_HI, hi_word);
    chip_updates = {hi_word, lo_word};
    spi_read(A_CYCLE_LO, lo_word);
    spi_read(A_CYCLE_HI, hi_word);
    chip_cycles = {hi_word, lo_word};
    if (chip_updates == 0 || chip_cycles == 0) fail("counter remained zero");
    if (chip_updates !== ref_updates) fail("update count differs from reference");
    if (chip_cycles !== ref_cycles) fail("cycle count differs from reference");

    // --- slow-clock readout: core clock /10, SCLK ratio preserved ---------
    core_half_ns = core_half_ns * 10.0;
    sclk_half_ns = real'(sclk_ratio) * core_half_ns;
    repeat (4) @(posedge clk);
    fork
      capture_scan();
      spi_write(A_CONTROL, 16'h0002);
    join

    if (scan_bits != TOTAL_BITS) fail("scan bit count mismatch");
    if (scan_words != GRID_WORDS) fail("scan word count mismatch");
    if (scan_last_count != 1) fail("scan_last count mismatch");
    @(posedge clk);
    spi_read(A_STATUS, status_word);
    if (!status_word[ST_DONE]) fail("controller did not return to DONE");
    if (status_word[ST_SCAN_ACTIVE]) fail("scan_active remained high");
    if (!status_word[ST_SCAN_USED]) fail("scan_used not reported");

    // --- bus-transaction accounting ---------------------------------------
    repeat (8) @(posedge clk);
    if (bus_writes != exp_writes)
      fail($sformatf("bus writes %0d != frames %0d", bus_writes, exp_writes));
    if (bus_reads != exp_reads)
      fail($sformatf("bus reads %0d != frames %0d", bus_reads, exp_reads));

    // --- dump for the external golden-model check -------------------------
    fd = $fopen("u_dyn.txt", "w");
    for (row = 0; row < NROW; row = row + 1) begin
      for (col = 0; col < NCOL; col = col + 1)
        $fwrite(fd, "%0d ", $signed(grid_mem[row*NCOL+col]));
      $fwrite(fd, "\n");
    end
    $fclose(fd);

    $display("  configuration words: %0d", 2*NPEALL+2*NCOL+2*NROW);
    $display("  updates/cycles     : %0d / %0d", chip_updates, chip_cycles);
    $display("  scan bits/words    : %0d / %0d", scan_bits, scan_words);
    $display("  bus writes/reads   : %0d / %0d", bus_writes, bus_reads);
    if (errors == 0) begin
      $display("tb_pde_chip_top_spi : PASS\n");
      $finish;
    end else $fatal(1, "tb_pde_chip_top_spi : FAIL (%0d errors)", errors);
  end

  initial begin
    #80_000_000;
    $fatal(1, "tb_pde_chip_top_spi : TIMEOUT");
  end
endmodule
