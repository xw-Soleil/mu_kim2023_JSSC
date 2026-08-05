// Bind-only helper: add this file to a chip8 VCS build to produce an FSDB
// without putting simulator-specific system tasks in the functional TB/RTL.
module pde_chip_wave_dump;
  initial begin
    $fsdbDumpfile("pde_chip_top8.fsdb");
    $fsdbDumpvars(0, tb_pde_chip_top);
  end
endmodule

bind tb_pde_chip_top pde_chip_wave_dump u_pde_chip_wave_dump();
