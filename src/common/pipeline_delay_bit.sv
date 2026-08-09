// Enable-gated single-bit delay line, for pipelining local control signals.
module pipeline_delay_bit #(
  parameter int unsigned DELAY = 1
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic enable_i,
  input  logic data_i,
  output logic data_o
);

  generate
    if (DELAY == 0) begin : g_no_delay
      assign data_o = data_i;
    end else begin : g_delay
      logic [DELAY-1:0] delay_q;

      assign data_o = delay_q[DELAY-1];

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
          delay_q <= '0;
        else if (clear_i)
          delay_q <= '0;
        else if (enable_i) begin
          delay_q[0] <= data_i;
          for (int i = 1; i < DELAY; i++)
            delay_q[i] <= delay_q[i-1];
        end
      end
    end
  endgenerate

endmodule
