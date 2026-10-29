module network_tester_reset_sync (
    input wire clk,
    input wire async_reset,
    output wire reset
);
    (* async_reg = "true" *) reg [1:0] pipeline = 2'b11;
    always @(posedge clk or posedge async_reset) begin
        if (async_reset) pipeline <= 2'b11;
        else pipeline <= {pipeline[0],1'b0};
    end
    assign reset = pipeline[1];
endmodule
