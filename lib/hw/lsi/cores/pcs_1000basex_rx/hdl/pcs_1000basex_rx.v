module pcs_1000basex_rx (
    input wire sample_clk,
    input wire rst,
    input wire cdr_locked,
    input wire bit_valid,
    input wire nrz_bit,
    output reg [7:0] rx_data,
    output reg rx_dv,
    output reg rx_er,
    output reg rx_valid,
    output reg frame_active,
    output reg pcs_synced,
    output reg code_error,
    output reg disparity_error,
    output reg [15:0] config_word,
    output reg config_valid
);
    localparam WAIT_KIND=3'd0, IDLE_COMMA=3'd1, DATA=3'd2,
               END_R1=3'd3, END_R2=3'd4, CONFIG_LOW=3'd5, CONFIG_HIGH=3'd6;
    reg [2:0] state;
    reg aligned, even, rd, term_even;
    reg [9:0] shift;
    reg [3:0] bit_count;
    reg [3:0] history_count;
    reg [1:0] confirmations, bad_count;
    reg [7:0] config_low;
    wire [9:0] word_next = {shift[8:0],nrz_bit};
    wire comma = (word_next == 10'h0fa) || (word_next == 10'h305);
    wire [7:0] decoded;
    wire is_k, invalid, wrong_rd, next_rd;
    wire symbol_error = invalid || wrong_rd;
    decoder_8b10b decoder(.code(word_next),.rd_in(rd),.data(decoded),
        .is_k(is_k),.invalid_code(invalid),.disparity_error(wrong_rd),.rd_out(next_rd));

    always @(posedge sample_clk) begin
        if (rst) begin
            shift <= 0;
            bit_count <= 0;
            history_count <= 0;
            aligned <= 0;
            even <= 0;
            rd <= 0;
            state <= WAIT_KIND;
            confirmations <= 0;
            bad_count <= 0;
            term_even <= 0;
            config_low <= 0;
            config_word <= 0;
            config_valid <= 0;
            rx_data <= 0;
            rx_dv <= 0;
            rx_er <= 0;
            rx_valid <= 0;
            frame_active <= 0;
            pcs_synced <= 0;
            code_error <= 0;
            disparity_error <= 0;
        end else begin
            rx_valid <= 0;
            config_valid <= 0;
            if (!cdr_locked) begin
                shift <= 0;
                bit_count <= 0;
                history_count <= 0;
                aligned <= 0;
                pcs_synced <= 0;
                confirmations <= 0;
                bad_count <= 0;
                state <= WAIT_KIND;
                rx_dv <= 0;
                frame_active <= 0;
                if (frame_active) code_error <= 1;
            end else if (bit_valid) begin
                shift <= word_next;
                if (history_count < 10) history_count <= history_count+1'b1;
                if (!aligned) begin
                    // Search every bit, accepting either comma disparity.
                    if (history_count >= 9 && comma) begin
                        aligned <= 1;
                        bit_count <= 0;
                        rd <= (word_next == 10'h0fa);
                        even <= 0; // Comma is even; the next character is odd.
                        state <= WAIT_KIND;
                        confirmations <= 0;
                        bad_count <= 0;
                    end
                end else if (bit_count != 9)
                    bit_count <= bit_count+1'b1;
                else begin
                    bit_count <= 0;
                    rd <= next_rd;
                    even <= !even;
                    if (invalid) code_error <= 1;
                    if (wrong_rd) disparity_error <= 1;
                    if (symbol_error) bad_count <= bad_count+1'b1;
                    else bad_count <= 0;

                    case (state)
                        WAIT_KIND: begin
                            if (!symbol_error && !is_k &&
                                (decoded == 8'hc5 || decoded == 8'h50) && !next_rd) begin
                                state <= IDLE_COMMA;
                                if (confirmations < 3) confirmations <= confirmations+1'b1;
                                if (confirmations >= 2) pcs_synced <= 1;
                            end else if (!symbol_error && !is_k &&
                                         (decoded == 8'hb5 || decoded == 8'h42))
                                state <= CONFIG_LOW;
                            else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                confirmations <= 0;
                                code_error <= 1;
                            end
                        end
                        IDLE_COMMA: begin
                            if (!symbol_error && is_k && decoded == 8'hbc && even)
                                state <= WAIT_KIND;
                            else if (!symbol_error && is_k && decoded == 8'hfb && even && pcs_synced) begin
                                state <= DATA;
                                frame_active <= 1;
                                rx_data <= 8'h55; // Restore the /S/ preamble byte.
                                rx_dv <= 1;
                                rx_er <= 0;
                                rx_valid <= 1;
                            end else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                confirmations <= 0;
                                code_error <= 1;
                            end
                        end
                        DATA: begin
                            if (!is_k) begin
                                rx_data <= decoded;
                                rx_dv <= 1;
                                rx_er <= symbol_error;
                                rx_valid <= 1;
                            end else if (decoded == 8'hfe) begin
                                rx_data <= 8'hfe;
                                rx_dv <= 1;
                                rx_er <= 1;
                                rx_valid <= 1;
                            end else if (decoded == 8'hfd) begin
                                state <= END_R1;
                                term_even <= even;
                                frame_active <= 0;
                                rx_data <= 0;
                                rx_dv <= 0;
                                rx_er <= symbol_error;
                                rx_valid <= 1;
                            end else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                code_error <= 1;
                                frame_active <= 0;
                                rx_data <= 0;
                                rx_dv <= 0;
                                rx_er <= 1;
                                rx_valid <= 1;
                            end
                        end
                        END_R1, END_R2: begin
                            if (!symbol_error && is_k && decoded == 8'hf7) begin
                                if (state == END_R1 && !term_even) state <= END_R2;
                                else state <= IDLE_COMMA;
                            end else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                code_error <= 1;
                                rx_data <= 0;
                                rx_dv <= 0;
                                rx_er <= 1;
                                rx_valid <= 1;
                            end
                        end
                        CONFIG_LOW: begin
                            if (!symbol_error && !is_k) begin
                                config_low <= decoded;
                                state <= CONFIG_HIGH;
                            end else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                code_error <= 1;
                            end
                        end
                        CONFIG_HIGH: begin
                            if (!symbol_error && !is_k) begin
                                config_word <= {decoded,config_low};
                                config_valid <= 1;
                                state <= IDLE_COMMA;
                                if (confirmations < 3) confirmations <= confirmations+1'b1;
                                if (confirmations >= 2) pcs_synced <= 1;
                            end else begin
                                aligned <= 0;
                                pcs_synced <= 0;
                                code_error <= 1;
                            end
                        end
                        default: begin aligned <= 0; pcs_synced <= 0; end
                    endcase
                    // Three consecutive code/disparity errors trigger a new
                    // bit-wise comma search. This is a simplified sync policy.
                    if (symbol_error && bad_count >= 2) begin
                        aligned <= 0;
                        pcs_synced <= 0;
                        confirmations <= 0;
                        bad_count <= 0;
                        code_error <= 1;
                        if (frame_active) begin
                            frame_active <= 0;
                            rx_dv <= 0;
                            rx_er <= 1;
                            rx_valid <= 1;
                        end
                    end
                end
            end
        end
    end
endmodule
