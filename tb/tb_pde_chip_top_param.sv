// ============================================================================
// tb_pde_chip_top_param.sv : parameterized full-chip narrow-interface test
// ============================================================================
`timescale 1ns/1ps

module tb_pde_chip_top_param #(
  parameter int NROW = 20,
  parameter int NCOL = 20,
  parameter int BND = 4096,
  parameter int MAX_UPDATES = 4096
);
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

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cfg_valid, cfg_write, cfg_ready, cfg_rvalid;
  logic [15:0] cfg_addr, cfg_wdata, cfg_rdata;
  logic scan_out, scan_valid, scan_last;

  pde_chip_top #(
    .NROW(NROW), .NCOL_LOG(NCOL), .USE_DSM(1'b1),
    .CONV_ON_SMALL(1'b1), .DYN_PREC(1'b1),
    .MAX_UPDATES(MAX_UPDATES)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(cfg_valid), .cfg_write(cfg_write),
    .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_ready(cfg_ready),
    .cfg_rvalid(cfg_rvalid), .cfg_rdata(cfg_rdata),
    .scan_out(scan_out), .scan_valid(scan_valid), .scan_last(scan_last)
  );

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

  logic [15:0] status_word, lo_word, hi_word, scan_shift;
  logic [31:0] chip_updates, chip_cycles;
  integer i, polls, scan_bits, scan_words, bit_in_word;
  integer expected_idx, scan_last_count;

  initial begin
    cfg_valid = 0; cfg_write = 0; cfg_addr = 0; cfg_wdata = 0;
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
    $display("\n=== pde_chip_top %0dx%0d full regression ===", NROW, NCOL);

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

    cfg_read_word(A_NROW, lo_word);
    cfg_read_word(A_NCOL, hi_word);
    if (lo_word != NROW || hi_word != NCOL) fail("dimension register mismatch");
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_CFG_COMPLETE]) fail("cfg_complete is low");
    if (status_word[ST_CFG_ERROR]) fail("legal configuration set cfg_error");

    fork
      cfg_write_word(A_CONTROL, 16'h0001);
      begin
        @(negedge clk);
        ref_load_en = 1; ref_start = 1;
        @(negedge clk);
        ref_load_en = 0; ref_start = 0;
      end
    join

    polls = 0;
    status_word = 0;
    while (!status_word[ST_DONE] && polls < 20000) begin
      repeat (16) @(posedge clk);
      cfg_read_word(A_STATUS, status_word);
      polls = polls + 1;
    end
    if (!status_word[ST_DONE]) fail("chip did not reach DONE");
    if (status_word[ST_BUSY]) fail("busy remained high in DONE");
    if (!status_word[ST_CONVERGED]) fail("chip did not converge");
    if (!ref_done) wait (ref_done);
    if (!ref_converged) fail("reference did not converge");

    cfg_read_word(A_UPDATE_LO, lo_word);
    cfg_read_word(A_UPDATE_HI, hi_word);
    chip_updates = {hi_word, lo_word};
    cfg_read_word(A_CYCLE_LO, lo_word);
    cfg_read_word(A_CYCLE_HI, hi_word);
    chip_cycles = {hi_word, lo_word};
    if (chip_updates == 0 || chip_cycles == 0) fail("counter remained zero");
    if (chip_updates !== ref_updates) fail("update count differs from reference");
    if (chip_cycles !== ref_cycles) fail("cycle count differs from reference");

    cfg_write_word(A_CONTROL, 16'h0002);
    scan_shift = 0; scan_bits = 0; scan_words = 0; bit_in_word = 0;
    scan_last_count = 0;
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

    if (scan_bits != TOTAL_BITS) fail("scan bit count mismatch");
    if (scan_words != GRID_WORDS) fail("scan word count mismatch");
    if (scan_last_count != 1) fail("scan_last count mismatch");
    @(posedge clk);
    cfg_read_word(A_STATUS, status_word);
    if (!status_word[ST_DONE]) fail("controller did not return to DONE");
    if (status_word[ST_SCAN_ACTIVE]) fail("scan_active remained high");

    $display("  configuration words: %0d", 2*NPEALL+2*NCOL+2*NROW);
    $display("  updates/cycles     : %0d / %0d", chip_updates, chip_cycles);
    $display("  scan bits/words    : %0d / %0d", scan_bits, scan_words);
    if (errors == 0) begin
      $display("tb_pde_chip_top_param : PASS\n");
      $finish;
    end else $fatal(1, "tb_pde_chip_top_param : FAIL (%0d errors)", errors);
  end

  initial begin
    #20_000_000;
    $fatal(1, "tb_pde_chip_top_param : TIMEOUT");
  end
endmodule
