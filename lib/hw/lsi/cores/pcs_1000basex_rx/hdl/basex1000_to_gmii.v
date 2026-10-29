module basex1000_to_gmii #(
    parameter integer OVERSAMPLE = 4
)(
    input wire sample_clk,
    input wire rst,
    input wire serial_rx,
    input wire signal_detect,
    output reg gmii_rx_clk,
    output reg [7:0] gmii_rxd,
    output reg gmii_rx_dv,
    output reg gmii_rx_er,
    output reg gmii_rx_ce,
    output wire cdr_locked,
    output wire pcs_synced,
    output wire disparity_error,
    output wire [15:0] config_word,
    output wire config_valid,
    output reg rx_abort,
    output wire code_error,
    output reg overflow
);
    wire nrz_bit, bit_valid;
    wire [7:0] pcs_data;
    wire pcs_dv, pcs_er, pcs_valid, frame_active;
    pma_1000basex_rx #(.OVERSAMPLE(OVERSAMPLE)) pma (
        .sample_clk(sample_clk),.rst(rst),.serial_rx(serial_rx),
        .signal_detect(signal_detect),.nrz_bit(nrz_bit),.bit_valid(bit_valid),
        .cdr_locked(cdr_locked)
    );
    pcs_1000basex_rx pcs (
        .sample_clk(sample_clk),.rst(rst),.cdr_locked(cdr_locked),
        .bit_valid(bit_valid),.nrz_bit(nrz_bit),.rx_data(pcs_data),
        .rx_dv(pcs_dv),.rx_er(pcs_er),.rx_valid(pcs_valid),
        .frame_active(frame_active),.pcs_synced(pcs_synced),.code_error(code_error),
        .disparity_error(disparity_error),.config_word(config_word),.config_valid(config_valid)
    );
    reg [9:0] fifo [0:3];
    reg [1:0] wr_ptr, rd_ptr;
    reg [2:0] count;
    reg [3:0] byte_phase;
    reg was_locked;
    wire ready = cdr_locked && pcs_synced;
    wire load_output = ready && bit_valid && byte_phase == 0;
    wire pop = load_output && count != 0;
    wire push = ready && pcs_valid;
    wire accept_push = push && ((count != 4) || pop);

    always @(posedge sample_clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            byte_phase <= 0;
            was_locked <= 0;
            gmii_rx_clk <= 0;
            gmii_rxd <= 0;
            gmii_rx_dv <= 0;
            gmii_rx_er <= 0;
            gmii_rx_ce <= 0;
            rx_abort <= 0;
            overflow <= 0;
        end else begin
            was_locked <= ready;
            gmii_rx_ce <= 0;
            rx_abort <= 0;
            if (!ready) begin
                wr_ptr <= 0;
                rd_ptr <= 0;
                count <= 0;
                byte_phase <= 0;
                gmii_rx_clk <= 0;
                gmii_rx_dv <= 0;
                if (was_locked && (gmii_rx_dv || frame_active || count != 0)) begin
                    rx_abort <= 1;
                    gmii_rx_er <= 1;
                    gmii_rx_ce <= 1;
                end
            end else begin
                if (bit_valid) begin
                    byte_phase <= (byte_phase == 9) ? 0 : byte_phase+1'b1;
                    if (byte_phase == 0) begin
                        gmii_rx_clk <= 0;
                        gmii_rx_ce <= 1;
                        if (pop) begin
                            {gmii_rx_er,gmii_rx_dv,gmii_rxd} <= fifo[rd_ptr];
                            rd_ptr <= rd_ptr+1'b1;
                        end else begin
                            gmii_rxd <= 0;
                            gmii_rx_dv <= 0;
                            gmii_rx_er <= 0;
                        end
                    end
                    if (byte_phase == 5) gmii_rx_clk <= 1;
                end
                if (push && pcs_er && !pcs_dv) rx_abort <= 1;
                if (accept_push) begin
                    fifo[wr_ptr] <= {pcs_er,pcs_dv,pcs_data};
                    wr_ptr <= wr_ptr+1'b1;
                end
                case ({accept_push,pop})
                    2'b10: count <= count+1'b1;
                    2'b01: count <= count-1'b1;
                    default: begin end
                endcase
                if (push && !accept_push) begin
                    overflow <= 1;
                    rx_abort <= 1;
                end
            end
            if (pcs_valid && pcs_er && !pcs_dv) begin
                rx_abort <= 1;
                if (!ready) begin
                    gmii_rx_er <= 1;
                    gmii_rx_ce <= 1;
                end
            end
        end
    end
endmodule
