module pma_1000basex_tx (
    input wire bit_clk,
    input wire rst,
    input wire symbol_ce,
    input wire [9:0] parallel_code,
    output reg serial_tx,
    output reg [9:0] code_group,
    output reg code_group_valid
);
    reg [9:0] shift;
    always @(posedge bit_clk) begin
        if (rst) begin
            shift <= 0;
            serial_tx <= 0;
            code_group <= 0;
            code_group_valid <= 0;
        end else begin
            code_group_valid <= symbol_ce;
            if (symbol_ce) begin
                serial_tx <= parallel_code[9];
                shift <= {parallel_code[8:0], 1'b0};
                code_group <= parallel_code;
            end else begin
                serial_tx <= shift[9];
                shift <= {shift[8:0], 1'b0};
            end
        end
    end
endmodule
