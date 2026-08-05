// ============================================================================
// pde_chip_top.sv : narrow, word-addressed configuration wrapper
// ============================================================================
// Reads are returned one cycle after acceptance. Solution readout is the raw
// core scan stream: fixed rate, LSB first, with no backpressure.
//
// STATUS[7:0] = {cfg_complete, cfg_error, scan_active, prec[1:0],
//                  converged, done, busy}
// ============================================================================
module pde_chip_top #(
  parameter int NROW          = 20,
  parameter int NCOL_LOG      = 20,
  parameter bit USE_DSM       = 1'b1,
  parameter bit CONV_ON_SMALL = 1'b1,
  parameter bit DYN_PREC      = 1'b1,
  parameter int MAX_UPDATES   = 4096,
  parameter int NPE           = NCOL_LOG/2
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cfg_valid,
  input  logic        cfg_write,
  input  logic [15:0] cfg_addr,
  input  logic [15:0] cfg_wdata,
  output logic        cfg_ready,
  output logic        cfg_rvalid,
  output logic [15:0] cfg_rdata,
  output logic        scan_out,
  output logic        scan_valid,
  output logic        scan_last
);

  localparam int NPEALL    = NROW*NPE;
  localparam int READ_BITS = 16*NROW*NCOL_LOG;
  localparam int SCAN_CW   = (READ_BITS <= 1) ? 1 : $clog2(READ_BITS);

  localparam logic [15:0] A_CONTROL = 16'h0000;
  localparam logic [15:0] A_STATUS  = 16'h0001;
  localparam logic [15:0] A_UPD_LO  = 16'h0002;
  localparam logic [15:0] A_UPD_HI  = 16'h0003;
  localparam logic [15:0] A_CYC_LO  = 16'h0004;
  localparam logic [15:0] A_CYC_HI  = 16'h0005;
  localparam logic [15:0] A_NROW    = 16'h0006;
  localparam logic [15:0] A_NCOL    = 16'h0007;
  localparam logic [15:0] A_RED     = 16'h1000;
  localparam logic [15:0] A_BLACK   = 16'h2000;
  localparam logic [15:0] A_NORTH   = 16'h3000;
  localparam logic [15:0] A_SOUTH   = 16'h3400;
  localparam logic [15:0] A_WEST    = 16'h3800;
  localparam logic [15:0] A_EAST    = 16'h3c00;
  localparam logic [SCAN_CW-1:0] SCAN_LAST_COUNT = READ_BITS-1;

  // Shadow payloads intentionally have no reset. Their resettable valid maps
  // prevent an incomplete payload from ever reaching the core.
  logic [15:0] red_shadow   [0:NPEALL-1];
  logic [15:0] black_shadow [0:NPEALL-1];
  logic [15:0] north_shadow [0:NCOL_LOG-1];
  logic [15:0] south_shadow [0:NCOL_LOG-1];
  logic [15:0] west_shadow  [0:NROW-1];
  logic [15:0] east_shadow  [0:NROW-1];

  logic [NPEALL-1:0] red_valid_q, black_valid_q;
  logic [NCOL_LOG-1:0] north_valid_q, south_valid_q;
  logic [NROW-1:0] west_valid_q, east_valid_q;
  logic cfg_complete;

  logic [16*NPEALL-1:0] load_red_flat, load_black_flat;
  logic [16*NCOL_LOG-1:0] bnd_north_flat, bnd_south_flat;
  logic [16*NROW-1:0] bnd_west_flat, bnd_east_flat;

  genvar gp, gc, gr;
  generate
    for (gp = 0; gp < NPEALL; gp++) begin : g_flat_pe
      assign load_red_flat[16*gp +: 16]   = red_shadow[gp];
      assign load_black_flat[16*gp +: 16] = black_shadow[gp];
    end
    for (gc = 0; gc < NCOL_LOG; gc++) begin : g_flat_col
      assign bnd_north_flat[16*gc +: 16] = north_shadow[gc];
      assign bnd_south_flat[16*gc +: 16] = south_shadow[gc];
    end
    for (gr = 0; gr < NROW; gr++) begin : g_flat_row
      assign bnd_west_flat[16*gr +: 16] = west_shadow[gr];
      assign bnd_east_flat[16*gr +: 16] = east_shadow[gr];
    end
  endgenerate

  assign cfg_complete = (&red_valid_q)   && (&black_valid_q)
                      && (&north_valid_q) && (&south_valid_q)
                      && (&west_valid_q)  && (&east_valid_q);

  logic core_busy, core_done, core_converged;
  logic [1:0] core_prec;
  logic [31:0] core_update_cnt, core_cycle_cnt;
  logic core_scan_out;
  logic core_start, core_load_en, core_read_start;

  pde_core #(
    .NROW(NROW), .NCOL_LOG(NCOL_LOG), .USE_DSM(USE_DSM),
    .CONV_ON_SMALL(CONV_ON_SMALL), .DYN_PREC(DYN_PREC),
    .MAX_UPDATES(MAX_UPDATES), .NPE(NPE)
  ) u_core (
    .clk(clk), .rst_n(rst_n),
    .start(core_start), .read_start(core_read_start),
    .bnd_north_flat(bnd_north_flat), .bnd_south_flat(bnd_south_flat),
    .bnd_west_flat(bnd_west_flat), .bnd_east_flat(bnd_east_flat),
    .load_en(core_load_en),
    .load_red_flat(load_red_flat), .load_black_flat(load_black_flat),
    .scan_in(1'b0), .scan_out(core_scan_out),
    .busy(core_busy), .done(core_done), .converged(core_converged),
    .prec_o(core_prec), .update_cnt(core_update_cnt),
    .cycle_cnt(core_cycle_cnt), .u_red_flat(), .u_black_flat()
  );

  logic cfg_accept, cfg_read_accept, cfg_write_accept;
  logic hit_control, hit_red, hit_black, hit_north, hit_south, hit_west, hit_east;
  logic hit_payload, known_read;
  logic writable, start_ok, read_ok, control_conflict;
  logic clear_error, access_error;
  logic cfg_error_q;
  logic scan_active_q;
  logic [SCAN_CW-1:0] scan_count_q;

  assign cfg_ready        = 1'b1;
  assign cfg_accept       = cfg_valid && cfg_ready;
  assign cfg_read_accept  = cfg_accept && !cfg_write;
  assign cfg_write_accept = cfg_accept &&  cfg_write;

  assign hit_control = (cfg_addr == A_CONTROL);
  assign hit_red     = (cfg_addr >= A_RED)   && (cfg_addr < A_RED   + NPEALL);
  assign hit_black   = (cfg_addr >= A_BLACK) && (cfg_addr < A_BLACK + NPEALL);
  assign hit_north   = (cfg_addr >= A_NORTH) && (cfg_addr < A_NORTH + NCOL_LOG);
  assign hit_south   = (cfg_addr >= A_SOUTH) && (cfg_addr < A_SOUTH + NCOL_LOG);
  assign hit_west    = (cfg_addr >= A_WEST)  && (cfg_addr < A_WEST  + NROW);
  assign hit_east    = (cfg_addr >= A_EAST)  && (cfg_addr < A_EAST  + NROW);
  assign hit_payload = hit_red || hit_black || hit_north || hit_south
                     || hit_west || hit_east;

  assign known_read = hit_control || (cfg_addr == A_STATUS)
                    || (cfg_addr == A_UPD_LO) || (cfg_addr == A_UPD_HI)
                    || (cfg_addr == A_CYC_LO) || (cfg_addr == A_CYC_HI)
                    || (cfg_addr == A_NROW) || (cfg_addr == A_NCOL)
                    || hit_payload;

  assign writable        = !core_busy && !core_done && !scan_active_q;
  assign start_ok        = writable && cfg_complete;
  assign read_ok         = core_done && !scan_active_q;
  assign control_conflict = cfg_wdata[0] && cfg_wdata[1];

  assign core_start = cfg_write_accept && hit_control && cfg_wdata[0]
                    && !control_conflict && start_ok;
  assign core_load_en = core_start;
  assign core_read_start = cfg_write_accept && hit_control && cfg_wdata[1]
                         && !control_conflict && read_ok;
  assign clear_error = cfg_write_accept && hit_control && cfg_wdata[2];

  always_comb begin
    access_error = 1'b0;
    if (cfg_accept) begin
      if (cfg_write) begin
        if (hit_control) begin
          if (|cfg_wdata[15:3]) access_error = 1'b1;
          if (control_conflict) access_error = 1'b1;
          if (cfg_wdata[0] && !start_ok) access_error = 1'b1;
          if (cfg_wdata[1] && !read_ok)  access_error = 1'b1;
        end else if (hit_payload) begin
          if (!writable) access_error = 1'b1;
        end else begin
          access_error = 1'b1;
        end
      end else if (!known_read) begin
        access_error = 1'b1;
      end
    end
  end

  logic [15:0] read_data_d;
  always_comb begin
    read_data_d = 16'h0000;
    if (cfg_addr == A_STATUS)
      read_data_d = {8'h00, cfg_complete, cfg_error_q, scan_active_q,
                     core_prec, core_converged, core_done, core_busy};
    else if (cfg_addr == A_UPD_LO) read_data_d = core_update_cnt[15:0];
    else if (cfg_addr == A_UPD_HI) read_data_d = core_update_cnt[31:16];
    else if (cfg_addr == A_CYC_LO) read_data_d = core_cycle_cnt[15:0];
    else if (cfg_addr == A_CYC_HI) read_data_d = core_cycle_cnt[31:16];
    else if (cfg_addr == A_NROW)   read_data_d = 16'(NROW);
    else if (cfg_addr == A_NCOL)   read_data_d = 16'(NCOL_LOG);
    else if (hit_red)   read_data_d = red_shadow[cfg_addr-A_RED];
    else if (hit_black) read_data_d = black_shadow[cfg_addr-A_BLACK];
    else if (hit_north) read_data_d = north_shadow[cfg_addr-A_NORTH];
    else if (hit_south) read_data_d = south_shadow[cfg_addr-A_SOUTH];
    else if (hit_west)  read_data_d = west_shadow[cfg_addr-A_WEST];
    else if (hit_east)  read_data_d = east_shadow[cfg_addr-A_EAST];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      red_valid_q   <= '0;
      black_valid_q <= '0;
      north_valid_q <= '0;
      south_valid_q <= '0;
      west_valid_q  <= '0;
      east_valid_q  <= '0;
    end else if (cfg_write_accept && hit_payload && writable) begin
      if (hit_red) begin
        red_shadow[cfg_addr-A_RED] <= cfg_wdata;
        red_valid_q[cfg_addr-A_RED] <= 1'b1;
      end else if (hit_black) begin
        black_shadow[cfg_addr-A_BLACK] <= cfg_wdata;
        black_valid_q[cfg_addr-A_BLACK] <= 1'b1;
      end else if (hit_north) begin
        north_shadow[cfg_addr-A_NORTH] <= cfg_wdata;
        north_valid_q[cfg_addr-A_NORTH] <= 1'b1;
      end else if (hit_south) begin
        south_shadow[cfg_addr-A_SOUTH] <= cfg_wdata;
        south_valid_q[cfg_addr-A_SOUTH] <= 1'b1;
      end else if (hit_west) begin
        west_shadow[cfg_addr-A_WEST] <= cfg_wdata;
        west_valid_q[cfg_addr-A_WEST] <= 1'b1;
      end else if (hit_east) begin
        east_shadow[cfg_addr-A_EAST] <= cfg_wdata;
        east_valid_q[cfg_addr-A_EAST] <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_error_q <= 1'b0;
      cfg_rvalid  <= 1'b0;
      cfg_rdata   <= 16'h0000;
    end else begin
      cfg_rvalid <= cfg_read_accept;
      if (cfg_read_accept) cfg_rdata <= read_data_d;
      if (clear_error) cfg_error_q <= 1'b0;
      if (access_error) cfg_error_q <= 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scan_active_q <= 1'b0;
      scan_count_q  <= '0;
    end else if (core_read_start) begin
      scan_active_q <= 1'b1;
      scan_count_q  <= '0;
    end else if (scan_active_q) begin
      if (scan_count_q == SCAN_LAST_COUNT) begin
        scan_active_q <= 1'b0;
        scan_count_q  <= '0;
      end else begin
        scan_count_q <= scan_count_q + 1'b1;
      end
    end
  end

  assign scan_out   = core_scan_out;
  assign scan_valid = scan_active_q;
  assign scan_last  = scan_active_q && (scan_count_q == SCAN_LAST_COUNT);

  // synopsys translate_off
  initial begin
    if (NROW <= 0) $fatal(1, "NROW must be positive");
    if ((NCOL_LOG <= 0) || ((NCOL_LOG % 2) != 0))
      $fatal(1, "NCOL_LOG must be positive and even");
    if (NPE != NCOL_LOG/2) $fatal(1, "NPE must equal NCOL_LOG/2");
    if (NPEALL > 4096) $fatal(1, "PE shadow address window overflow");
    if ((NROW > 1024) || (NCOL_LOG > 1024))
      $fatal(1, "boundary shadow address window overflow");
  end
  always_ff @(posedge clk) begin
    if (rst_n && access_error)
      $display("[pde_chip_top] illegal cfg access addr=%h write=%b data=%h",
               cfg_addr, cfg_write, cfg_wdata);
  end
  // synopsys translate_on

endmodule
