module gmii_to_1000basex (
    input wire bit_clk,
    input wire rst,
    output reg gmii_tx_clk,
    input wire [7:0] gmii_txd,
    input wire gmii_tx_en,
    input wire gmii_tx_er,
    input wire config_enable,
    input wire [15:0] config_word,
    output wire serial_tx,
    output wire [9:0] code_group,
    output wire code_group_valid,
    output wire protocol_error
);
    reg [3:0] phase;
    reg [7:0] sampled_data;
    reg sampled_en, sampled_er, sampled_config;
    reg [15:0] sampled_config_word;
    wire [9:0] encoded;
    wire symbol_ce = (phase == 0);

    pcs_1000basex_tx pcs (
        .clk(bit_clk), .rst(rst), .symbol_ce(symbol_ce),
        .gmii_txd(sampled_data), .gmii_tx_en(sampled_en), .gmii_tx_er(sampled_er),
        .config_enable(sampled_config), .config_word(sampled_config_word),
        .code_group(encoded), .symbol_data(), .symbol_is_k(),
        .running_disparity(), .protocol_error(protocol_error)
    );

    pma_1000basex_tx pma (
        .bit_clk(bit_clk), .rst(rst), .symbol_ce(symbol_ce),
        .parallel_code(encoded), .serial_tx(serial_tx),
        .code_group(code_group), .code_group_valid(code_group_valid)
    );

    always @(posedge bit_clk) begin
        if (rst) begin
            phase <= 0;
            gmii_tx_clk <= 0;
            sampled_data <= 0;
            sampled_en <= 0;
            sampled_er <= 0;
            sampled_config <= 0;
            sampled_config_word <= 0;
        end else begin
            phase <= (phase == 9) ? 0 : phase + 1'b1;
            if (phase == 9) gmii_tx_clk <= 1;
            if (phase == 4) gmii_tx_clk <= 0;
            if (phase == 5) begin
                sampled_data <= gmii_txd;
                sampled_en <= gmii_tx_en;
                sampled_er <= gmii_tx_er;
                sampled_config <= config_enable;
                sampled_config_word <= config_word;
            end

        end
    end
endmodule
