// ============================================================================
// spi_cfg_bridge.sv : SPI-lite slave -> cfg-bus master bridge
// ============================================================================
// Contract: docs/spi_interface_spec.md.  Mode-0 SPI, 40-bit fixed frames
// {CMD[7:0], ADDR[15:0], DATA[15:0]}, MSB first, exactly one frame per CS_N
// assertion.  CMD[7]=1 write / 0 read, CMD[6:0] reserved and must be zero --
// a frame violating this is discarded without issuing a bus transaction.
//
// SCLK/CS_N/MOSI are asynchronous inputs oversampled in the clk domain
// (f_SCLK <= f_clk/8); the chip keeps a single clock domain.  Each input runs
// through a 3-deep synchronizer; stage [1] is the resolved sample, stage [2]
// provides edge history.  The SCLK and MOSI paths have identical depth, so
// their latency mismatch is bounded by one clk cycle -- far inside the
// half-period guard band that mode 0 provides around the sampling edge.
//
// A read frame issues its cfg read once CMD+ADDR are complete (24th rising
// edge); the response returns in one cycle (cfg_ready is constant 1 and read
// latency is fixed, see pde_chip_top.sv) and is shifted out on MISO during
// the DATA phase of the same frame.  A write frame issues its cfg write after
// the 40th rising edge.  CS_N high at any point resets the frame state; a
// short frame is discarded (a read frame aborted after edge 24 may already
// have issued its side-effect-free cfg read).

module spi_cfg_bridge (
  input  logic        clk,
  input  logic        rst_n,       // raw async reset; synchronized locally
  // SPI pins (asynchronous to clk)
  input  logic        sclk,
  input  logic        cs_n,
  input  logic        mosi,
  output logic        miso,
  // cfg bus master (synchronous to clk)
  output logic        cfg_valid,
  output logic        cfg_write,
  output logic [15:0] cfg_addr,
  output logic [15:0] cfg_wdata,
  input  logic        cfg_ready,
  input  logic        cfg_rvalid,
  input  logic [15:0] cfg_rdata
);

  // Two-stage reset synchronizer, same pattern as pde_chip_top_safe: the
  // wrapper's synchronizer is private to it, so the bridge carries its own.
  logic [1:0] rst_sync_q;
  logic       rst_n_sync;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rst_sync_q <= 2'b00;
    else        rst_sync_q <= {rst_sync_q[0], 1'b1};
  end

  assign rst_n_sync = rst_sync_q[1];

  // Input synchronizers.  CS_N resets to deselected.
  logic [2:0] sclk_q, csn_q, mosi_q;

  always_ff @(posedge clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      sclk_q <= '0;
      csn_q  <= 3'b111;
      mosi_q <= '0;
    end else begin
      sclk_q <= {sclk_q[1:0], sclk};
      csn_q  <= {csn_q[1:0], cs_n};
      mosi_q <= {mosi_q[1:0], mosi};
    end
  end

  wire sclk_rise = sclk_q[1] & ~sclk_q[2];
  wire sclk_fall = ~sclk_q[1] & sclk_q[2];
  wire csn_s     = csn_q[1];
  wire mosi_s    = mosi_q[1];

  typedef enum logic [1:0] {S_IDLE, S_FRAME, S_WAIT} state_e;

  state_e      state_q;
  logic [5:0]  bit_cnt_q;    // completed rising edges in this frame, 0..40
  logic [39:0] rx_q;         // MSB-first accumulator
  logic [15:0] tx_q;         // read-data output shifter
  logic        rd_issue_q;   // one-cycle: launch cfg read (ADDR in rx_q[15:0])
  logic        wr_issue_q;   // one-cycle: launch cfg write

  always_ff @(posedge clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      state_q    <= S_IDLE;
      bit_cnt_q  <= '0;
      rx_q       <= '0;
      rd_issue_q <= 1'b0;
      wr_issue_q <= 1'b0;
    end else begin
      rd_issue_q <= 1'b0;
      wr_issue_q <= 1'b0;

      if (csn_s) begin
        state_q   <= S_IDLE;
        bit_cnt_q <= '0;
      end else begin
        unique case (state_q)
          S_IDLE: begin
            state_q   <= S_FRAME;
            bit_cnt_q <= '0;
          end
          S_FRAME: begin
            if (sclk_rise) begin
              rx_q      <= {rx_q[38:0], mosi_s};
              bit_cnt_q <= bit_cnt_q + 6'd1;
              // 24th bit: CMD+ADDR complete.  Pre-shift, CMD[7] sits at
              // rx_q[22] and CMD[6:0] at rx_q[21:15].
              if (bit_cnt_q == 6'd23)
                rd_issue_q <= !rx_q[22] && (rx_q[21:15] == '0);
              // 40th bit: frame complete.  Pre-shift, CMD[7] at rx_q[38],
              // CMD[6:0] at rx_q[37:31].
              if (bit_cnt_q == 6'd39) begin
                wr_issue_q <= rx_q[38] && (rx_q[37:31] == '0);
                state_q    <= S_WAIT;
              end
            end
          end
          S_WAIT: ;   // extra edges ignored until CS_N returns high
        endcase
      end
    end
  end

  // Bus launch stage: one registered single-cycle cfg transaction per issue
  // pulse.  Post-shift field positions: read ADDR = rx_q[15:0] (24 bits in),
  // write ADDR = rx_q[31:16] and DATA = rx_q[15:0] (40 bits in).
  always_ff @(posedge clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      cfg_valid <= 1'b0;
      cfg_write <= 1'b0;
      cfg_addr  <= '0;
      cfg_wdata <= '0;
    end else begin
      cfg_valid <= rd_issue_q || wr_issue_q;
      cfg_write <= wr_issue_q;
      cfg_addr  <= wr_issue_q ? rx_q[31:16] : rx_q[15:0];
      cfg_wdata <= rx_q[15:0];
    end
  end

  // The bridge is the only bus master and never has more than one read in
  // flight, so every cfg_rvalid pulse belongs to it.
  always_ff @(posedge clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      tx_q <= '0;
      miso <= 1'b0;
    end else begin
      if (cfg_rvalid) tx_q <= cfg_rdata;
      if (csn_s) begin
        miso <= 1'b0;
      end else if (sclk_fall && state_q == S_FRAME
                   && bit_cnt_q >= 6'd24 && bit_cnt_q <= 6'd39) begin
        miso <= tx_q[15];
        tx_q <= {tx_q[14:0], 1'b0};
      end
    end
  end

endmodule
