// ============================================================================
// tb_pde_chip_top_safe.sv : protocol-hardening wrapper regression
// ============================================================================
`timescale 1ns/1ps

module tb_pde_chip_top_safe;
  localparam int NROW = 4;
  localparam int NCOL = 4;
  localparam int NPE = NCOL/2;
  localparam int NPEALL = NROW*NPE;
  localparam int GRID_WORDS = NROW*NCOL;
  localparam int TOTAL_BITS = 16*GRID_WORDS;
  localparam int BND = 4096;

  localparam logic [15:0] A_CONTROL = 16'h0000;
  localparam logic [15:0] A_STATUS = 16'h0001;
  localparam logic [15:0] A_UPDATE_LO = 16'h0002;
  localparam logic [15:0] A_UPDATE_HI = 16'h0003;
  localparam logic [15:0] A_CYCLE_LO = 16'h0004;
  localparam logic [15:0] A_CYCLE_HI = 16'h0005;
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

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cfg_valid, cfg_write, cfg_ready, cfg_rvalid;
  logic [15:0] cfg_addr, cfg_wdata, cfg_rdata;
  logic scan_out, scan_valid, scan_last;

  pde_chip_top_safe #(
    .NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
    .CONV_ON_SMALL(1'b1), .DYN_PREC(1'b1), .MAX_UPDATES(1024)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(cfg_valid), .cfg_write(cfg_write),
    .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_ready(cfg_ready),
    .cfg_rvalid(cfg_rvalid), .cfg_rdata(cfg_rdata),
    .scan_out(scan_out), .scan_valid(scan_valid), .scan_last(scan_last)
  );

  integer errors = 0;
  logic forbid_scan;
  logic forbidden_scan_seen;

  always @(posedge clk) begin
    if (rst_n && forbid_scan && scan_valid) begin
      forbidden_scan_seen <= 1'b1;
      $display("  FAIL: scan_valid appeared after rejected second read");
    end
  end

  task automatic fail(input string message);
    begin
      $display("  FAIL: %s", message);
      errors = errors + 1;
    end
  endtask

  task automatic cfg_write_word(input logic [15:0] address,
                                input logic [15:0] data);
    begin
      @(negedge clk);
      cfg_valid = 1'b1;
      cfg_write = 1'b1;
      cfg_addr = address;
      cfg_wdata = data;
      do @(posedge clk); while (!cfg_ready);
      @(negedge clk);
      cfg_valid = 1'b0;
      cfg_write = 1'b0;
      cfg_addr = '0;
      cfg_wdata = '0;
    end
  endtask

  task automatic cfg_read_word(input logic [15:0] address,
                               output logic [15:0] data);
    integer wait_cycles;
    begin
      @(negedge clk);
      cfg_valid = 1'b1;
      cfg_write = 1'b0;
      cfg_addr = address;
      cfg_wdata = '0;
      do @(posedge clk); while (!cfg_ready);
      @(negedge clk);
      cfg_valid = 1'b0;
      cfg_addr = '0;
      wait_cycles = 0;
      while (!cfg_rvalid && wait_cycles < 4) begin
        @(negedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!cfg_rvalid) begin
        fail($sformatf("read timeout at 0x%04h", address));
        data = 'x;
      end else data = cfg_rdata;
    end
  endtask

  logic [15:0] status_word, lo_word, hi_word, scan_shift;
  logic [31:0] updates, cycles;
  integer i, polls, scan_bits, scan_words, bit_in_word;
  integer scan_last_count, got_signed, delta;

  initial begin
    cfg_valid = 0; cfg_write = 0; cfg_addr = 0; cfg_wdata = 0;
    forbid_scan = 0; forbidden_scan_seen = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    $display("\n=== pde_chip_top_safe 4x4 protocol regression ===");

    for (i = 0; i < NPEALL; i = i + 1) begin
      cfg_write_word(A_RED+i, 16'd0);
      cfg_write_word(A_BLACK+i, 16'd0);
    end
    for (i = 0; i < NCOL; i = i + 1) begin
      cfg_write_word(A_NORTH+i, 16'(BND));
      cfg_write_word(A_SOUTH+i, 16'(BND));
    end
    for (i = 0; i < NROW; i = i + 1) begin
      cfg_write_word(A_WEST+i, 16'(BND));
      cfg_write_word(A_EAST+i, 16'(BND));
    end
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_CFG_COMPLETE]) fail("cfg_complete is low");

    // Reserved bit 15 makes the entire START write invalid.  It must not leak
    // through to the implementation even though bit 0 is also set.
    cfg_write_word(A_CONTROL, 16'h8001);
    repeat (4) begin
      @(posedge clk);
      if (scan_valid) fail("scan_valid appeared after rejected START");
    end
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_CFG_ERROR]) fail("rejected START did not set cfg_error");
    if (status_word[ST_BUSY]) fail("rejected START made the core busy");
    if (status_word[ST_DONE]) fail("rejected START advanced the core to done");

    // Legal clear reaches both wrapper and implementation sticky errors.
    cfg_write_word(A_CONTROL, 16'h0004);
    cfg_read_word(A_STATUS, status_word);
    if (status_word[ST_CFG_ERROR]) fail("legal clear did not clear cfg_error");

    cfg_write_word(A_CONTROL, 16'h0001);
    polls = 0;
    status_word = 0;
    while (!status_word[ST_DONE] && polls < 4096) begin
      repeat (8) @(posedge clk);
      cfg_read_word(A_STATUS, status_word);
      polls = polls + 1;
    end
    if (!status_word[ST_DONE]) fail("legal START did not reach DONE");
    if (!status_word[ST_CONVERGED]) fail("4x4 solve did not converge");
    if (status_word[ST_BUSY]) fail("busy remained high in DONE");

    cfg_read_word(A_UPDATE_LO, lo_word);
    cfg_read_word(A_UPDATE_HI, hi_word);
    updates = {hi_word, lo_word};
    cfg_read_word(A_CYCLE_LO, lo_word);
    cfg_read_word(A_CYCLE_HI, hi_word);
    cycles = {hi_word, lo_word};
    if (updates == 0 || cycles == 0) fail("solve counters remained zero");

    // First destructive read is legal and produces one continuous stream.
    cfg_write_word(A_CONTROL, 16'h0002);
    scan_shift = 0; scan_bits = 0; scan_words = 0; bit_in_word = 0;
    scan_last_count = 0;
    while (scan_bits < TOTAL_BITS) begin
      @(posedge clk);
      if (scan_last && !scan_valid) fail("scan_last without scan_valid");
      if (scan_valid) begin
        if (scan_last !== (scan_bits == TOTAL_BITS-1))
          fail($sformatf("scan_last at unexpected bit %0d", scan_bits));
        if (scan_last) scan_last_count = scan_last_count + 1;
        scan_shift = {scan_out, scan_shift[15:1]};
        if (bit_in_word == 15) begin
          got_signed = $signed(scan_shift);
          delta = (got_signed >= BND) ? got_signed-BND : BND-got_signed;
          if (delta*10 > BND)
            fail($sformatf("scan word %0d outside 10%% tolerance: %0d",
                           scan_words, got_signed));
          scan_words = scan_words + 1;
          bit_in_word = 0;
        end else bit_in_word = bit_in_word + 1;
        scan_bits = scan_bits + 1;
      end
    end
    if (scan_words != GRID_WORDS) fail("first scan word count mismatch");
    if (scan_last_count != 1) fail("first scan_last count mismatch");

    @(posedge clk);
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_DONE]) fail("first scan did not return to DONE");
    if (status_word[ST_SCAN_ACTIVE]) fail("scan_active stayed high");
    if (!status_word[ST_SCAN_USED]) fail("STATUS.scan_used did not set");

    // scan_used makes all later READ commands atomic rejects.  A persistent
    // monitor proves that no second scan bit appears during status traffic.
    forbid_scan = 1'b1;
    cfg_write_word(A_CONTROL, 16'h0002);
    repeat (12) @(posedge clk);
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_CFG_ERROR]) fail("second READ did not set cfg_error");
    if (!status_word[ST_SCAN_USED]) fail("scan_used was not sticky");
    if (status_word[ST_SCAN_ACTIVE]) fail("second READ activated scan");
    if (!status_word[ST_DONE]) fail("second READ disturbed DONE");
    repeat (12) @(posedge clk);
    forbid_scan = 1'b0;
    if (forbidden_scan_seen) begin
      errors = errors + 1;
      fail("scan_valid was observed after second READ rejection");
    end

    $display("  updates/cycles : %0d / %0d", updates, cycles);
    $display("  first scan     : %0d bits / %0d words", scan_bits, scan_words);
    if (errors == 0) begin
      $display("tb_pde_chip_top_safe : PASS\n");
      $finish;
    end else $fatal(1, "tb_pde_chip_top_safe : FAIL (%0d errors)", errors);
  end

  initial begin
    #2_000_000;
    $fatal(1, "tb_pde_chip_top_safe : TIMEOUT");
  end
endmodule
