module cdr_oversample_1000basex #(
    parameter integer OVERSAMPLE = 4,
    parameter integer LOCK_EDGES = 16,
    parameter integer MAX_GAP_BITS = 16
)(
    input wire sample_clk,
    input wire rst,
    input wire serial_rx,
    input wire signal_detect,
    output reg nrz_bit,
    output reg bit_valid,
    output reg locked
);
    (* async_reg = "true" *) reg [1:0] rx_sync;
    (* async_reg = "true" *) reg [1:0] sd_sync;
    reg edge_level;
    integer phase, edge_age, good_edges;
    wire transition = rx_sync[1] ^ edge_level;
    always @(posedge sample_clk) begin
        if (rst) begin
            rx_sync <= 0;
            sd_sync <= 0;
        end else begin
            rx_sync <= {rx_sync[0],serial_rx};
            sd_sync <= {sd_sync[0],signal_detect};
        end
    end
    always @(posedge sample_clk) begin
        if (rst) begin
            edge_level <= 0;
            phase <= 0;
            edge_age <= 0;
            good_edges <= 0;
            locked <= 0;
            nrz_bit <= 0;
            bit_valid <= 0;
        end else begin
            edge_level <= rx_sync[1];
            bit_valid <= 0;
            if (!sd_sync[1]) begin
                phase <= 0;
                edge_age <= 0;
                good_edges <= 0;
                locked <= 0;
            end else if (transition) begin
                phase <= 0;
                edge_age <= 0;
                if (edge_age + 1 < OVERSAMPLE/2) begin
                    good_edges <= 0;
                    locked <= 0;
                end else begin
                    if (good_edges < LOCK_EDGES) good_edges <= good_edges+1;
                    if (good_edges >= LOCK_EDGES-1) locked <= 1;
                end
            end else if (edge_age >= MAX_GAP_BITS*OVERSAMPLE-1) begin
                good_edges <= 0;
                locked <= 0;
                phase <= 0;
            end else begin
                edge_age <= edge_age+1;
                phase <= (phase == OVERSAMPLE-1) ? 0 : phase+1;
                if (phase == OVERSAMPLE/2-1) begin
                    nrz_bit <= rx_sync[1];
                    bit_valid <= locked;
                end
            end
        end
    end
endmodule
