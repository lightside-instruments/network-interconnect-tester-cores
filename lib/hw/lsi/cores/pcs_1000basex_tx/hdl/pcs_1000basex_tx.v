module pcs_1000basex_tx (
    input wire clk,
    input wire rst,
    input wire symbol_ce,
    input wire [7:0] gmii_txd,
    input wire gmii_tx_en,
    input wire gmii_tx_er,
    // Optional configuration ordered sets, controlled by an external AN FSM.
    // Tie config_enable low for forced-link operation. Not an AN controller.
    input wire config_enable,
    input wire [15:0] config_word,
    output wire [9:0] code_group,
    output wire [7:0] symbol_data,
    output wire symbol_is_k,
    output wire running_disparity,
    output reg protocol_error
);
    localparam IDLE_COMMA=3'd0, IDLE_DATA=3'd1, DATA=3'd2,
               EXTEND=3'd3, CONFIG_TYPE=3'd4, CONFIG_LOW=3'd5, CONFIG_HIGH=3'd6;
    reg [2:0] state;
    reg even;
    reg rd;
    reg correcting_idle;
    reg config_type;
    reg [15:0] config_latched;
    reg [7:0] character;
    reg control;
    wire rd_next, invalid_k;
    assign symbol_data = character;
    assign symbol_is_k = control;
    assign running_disparity = rd;

    encoder_8b10b encoder (
        .data(character), .is_k(control), .rd_in(rd),
        .code(code_group), .rd_out(rd_next), .invalid_k(invalid_k)
    );

    always @* begin
        character = 8'hbc; // /K28.5/
        control = 1'b1;
        case (state)
            IDLE_COMMA: begin
                if (!config_enable && gmii_tx_en)
                    character = 8'hfb; // /S/: replaces the first preamble byte.
            end
            IDLE_DATA: begin
                character = correcting_idle ? 8'hc5 : 8'h50; // D5.6 / D16.2
                control = 1'b0;
            end
            DATA: begin
                if (!gmii_tx_en)
                    character = 8'hfd; // /T/
                else if (gmii_tx_er)
                    character = 8'hfe; // /V/: error propagation
                else begin
                    character = gmii_txd;
                    control = 1'b0;
                end
            end
            EXTEND: character = 8'hf7; // /R/
            CONFIG_TYPE: begin
                character = config_type ? 8'h42 : 8'hb5; // D2.2 / D21.5
                control = 1'b0;
            end
            CONFIG_LOW: begin
                character = config_latched[7:0];
                control = 1'b0;
            end
            CONFIG_HIGH: begin
                character = config_latched[15:8];
                control = 1'b0;
            end
            default: character = 8'hfe;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE_COMMA;
            even <= 1'b1;
            rd <= 1'b0; // Initial running disparity is negative.
            correcting_idle <= 1'b0;
            config_type <= 1'b0;
            config_latched <= 16'd0;
            protocol_error <= 1'b0;
        end else if (symbol_ce) begin
            even <= !even;
            rd <= rd_next;
            if (invalid_k)
                protocol_error <= 1'b1;
            case (state)
                IDLE_COMMA: begin
                    if (config_enable) begin
                        config_latched <= config_word;
                        state <= CONFIG_TYPE;
                        if (gmii_tx_en)
                            protocol_error <= 1'b1;
                    end else if (gmii_tx_en) begin
                        state <= DATA;
                        if (gmii_tx_er || gmii_txd != 8'h55)
                            protocol_error <= 1'b1;
                    end else begin
                        // Choose based on disparity BEFORE the comma.
                        correcting_idle <= rd;
                        state <= IDLE_DATA;
                    end
                end
                IDLE_DATA: begin
                    state <= IDLE_COMMA;
                    // An odd-position start loses one preamble byte while
                    // finishing the current idle ordered set. /S/ follows.
                    if (gmii_tx_en && (gmii_tx_er || gmii_txd != 8'h55))
                        protocol_error <= 1'b1;
                end
                DATA: if (!gmii_tx_en) state <= EXTEND;
                EXTEND: begin
                    // End /R/ on an odd position; the next comma is even.
                    if (!even) state <= IDLE_COMMA;
                    if (gmii_tx_en) protocol_error <= 1'b1; // Insufficient IFG.
                end
                CONFIG_TYPE: state <= CONFIG_LOW;
                CONFIG_LOW: state <= CONFIG_HIGH;
                CONFIG_HIGH: begin
                    config_type <= !config_type;
                    state <= IDLE_COMMA;
                end
                default: state <= IDLE_COMMA;
            endcase
            if ((state == CONFIG_TYPE || state == CONFIG_LOW || state == CONFIG_HIGH)
                    && gmii_tx_en)
                protocol_error <= 1'b1;
        end
    end
endmodule
