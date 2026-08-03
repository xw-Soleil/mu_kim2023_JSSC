// Counter with synchronous clear, clock enable and wrap at a terminal value.
module counter_ce #(
    parameter int unsigned WIDTH = 4
)(
    input  logic                 clk_i,
    input  logic                 rst_ni,            // async reset, active low
    input  logic                 clear_i,           // sync clear, beats enable
    input  logic                 enable_i,          // count enable
    input  logic [WIDTH-1:0]     terminal_count_i,  // wrap value
    output logic [WIDTH-1:0]     count_o,
    output logic                 terminal_o         // high on count==terminal
);

assign terminal_o = enable_i && (count_o == terminal_count_i);

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        count_o <= '0;               // async reset
    end else if (clear_i) begin
        count_o <= '0;               // sync clear
    end else if (enable_i) begin
        if (count_o == terminal_count_i)
            count_o <= '0;           // wrap
        else
            count_o <= count_o + 1'b1;
    end
end

endmodule
