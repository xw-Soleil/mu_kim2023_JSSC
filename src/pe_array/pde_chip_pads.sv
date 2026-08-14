// ============================================================================
// pde_chip_pads.sv : pad-level chip top (tphn28hpcpgv18 GPIO ring, signals)
// ============================================================================
// Instantiates the nine signal pads around pde_chip_top_spi.  Pad polarity per
// databook DB_TPHN28HPCPGV18 section 9.12: OEN is active LOW (0 = drive PAD
// from I; 1 = tri-state, PAD -> C input path), REN is active LOW (0 = pull
// resistor enabled).  PDDW* pulls down, PDUW* pulls up.
//
// Inputs keep their pull enabled so a disconnected bench line settles to a
// safe level: rst_n pulls low (chip held in reset), CS_N pulls high
// (deselected), SCLK/MOSI/clk pull low (quiet).  Outputs drive always
// (point-to-point assumption, spec section 9 open item 1) with pulls off.
//
// Power pads (PVDD1/PVSS1/PVDD2/PVSS2/PVDD2POC), corner and filler cells have
// no logic function and are added as physical-only cells at the ICC2
// floorplan stage, not here.

module pde_chip_pads #(
  parameter int NROW          = 20,
  parameter int NCOL_LOG      = 20,
  parameter bit USE_DSM       = 1'b1,
  parameter bit CONV_ON_SMALL = 1'b1,
  parameter bit DYN_PREC      = 1'b1,
  parameter int MAX_UPDATES   = 4096,
  parameter int NPE           = NCOL_LOG/2
)(
  inout wire PAD_CLK,
  inout wire PAD_RSTN,
  inout wire PAD_SCLK,
  inout wire PAD_CSN,
  inout wire PAD_MOSI,
  inout wire PAD_MISO,
  inout wire PAD_SCAN_OUT,
  inout wire PAD_SCAN_VALID,
  inout wire PAD_SCAN_LAST
);

  wire clk_i, rst_n_i, sclk_i, cs_n_i, mosi_i;
  wire miso_o, scan_out_o, scan_valid_o, scan_last_o;

  // Inputs: OEN=1 (driver off), REN=0 (pull enabled).
  PDDW04DGZ_H_G  u_pad_clk  (.I(1'b0), .OEN(1'b1), .REN(1'b0),
                             .PAD(PAD_CLK), .C(clk_i));
  PDDW04SDGZ_H_G u_pad_rstn (.I(1'b0), .OEN(1'b1), .REN(1'b0),
                             .PAD(PAD_RSTN), .C(rst_n_i));
  PDDW04SDGZ_H_G u_pad_sclk (.I(1'b0), .OEN(1'b1), .REN(1'b0),
                             .PAD(PAD_SCLK), .C(sclk_i));
  PDUW04SDGZ_H_G u_pad_csn  (.I(1'b0), .OEN(1'b1), .REN(1'b0),
                             .PAD(PAD_CSN), .C(cs_n_i));
  PDDW04SDGZ_H_G u_pad_mosi (.I(1'b0), .OEN(1'b1), .REN(1'b0),
                             .PAD(PAD_MOSI), .C(mosi_i));

  // Outputs: OEN=0 (drive), REN=1 (pull off), C unused.
  PDDW04DGZ_H_G u_pad_miso  (.I(miso_o), .OEN(1'b0), .REN(1'b1),
                             .PAD(PAD_MISO), .C());
  PDDW04DGZ_H_G u_pad_scano (.I(scan_out_o), .OEN(1'b0), .REN(1'b1),
                             .PAD(PAD_SCAN_OUT), .C());
  PDDW04DGZ_H_G u_pad_scanv (.I(scan_valid_o), .OEN(1'b0), .REN(1'b1),
                             .PAD(PAD_SCAN_VALID), .C());
  PDDW04DGZ_H_G u_pad_scanl (.I(scan_last_o), .OEN(1'b0), .REN(1'b1),
                             .PAD(PAD_SCAN_LAST), .C());

  pde_chip_top_spi #(
    .NROW(NROW),
    .NCOL_LOG(NCOL_LOG),
    .USE_DSM(USE_DSM),
    .CONV_ON_SMALL(CONV_ON_SMALL),
    .DYN_PREC(DYN_PREC),
    .MAX_UPDATES(MAX_UPDATES),
    .NPE(NPE)
  ) u_core (
    .clk(clk_i),
    .rst_n(rst_n_i),
    .sclk(sclk_i),
    .cs_n(cs_n_i),
    .mosi(mosi_i),
    .miso(miso_o),
    .scan_out(scan_out_o),
    .scan_valid(scan_valid_o),
    .scan_last(scan_last_o)
  );

endmodule
