// SPDX-License-Identifier: GPL-3.0-or-later
module serial_top (
    input clk, spi_clk, spi_cs_n, spi_mosi,
    output spi_miso,
    input rx_p, rx_n,
    output tx_p, tx_n,
    output D1, D2, D3, D4, D5
);
    wire pll_clk, locked;
    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"), .DIVR(4'd0), .DIVF(7'd79),
        .DIVQ(3'd3), .FILTER_RANGE(3'd1)
    ) pll (
        .REFERENCECLK(clk), .PLLOUTCORE(pll_clk), .LOCK(locked),
        .RESETB(1'b1), .BYPASS(1'b0)
    );

    // The PLL generates 120 MHz. Divide by three for the PCS sampler.
    reg [1:0] phase = 0;
    reg sample_clk = 0;
    always @(posedge pll_clk) begin
        phase <= (phase == 2) ? 0 : phase + 1'b1;
        sample_clk <= phase == 0;
    end
    reg [3:0] startup = 0;
    always @(posedge sample_clk)
        startup <= {startup[2:0], locked};

    wire tx, generator_enable, analyzer_enable;
    wire [7:0] sent, received, bad_crc, bad_preamble;
    spi_regs registers (
        .clk(sample_clk), .spi_clk(spi_clk), .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .generator_enable(generator_enable), .analyzer_enable(analyzer_enable),
        .sent(sent), .received(received), .bad_crc(bad_crc),
        .bad_preamble(bad_preamble), .link_up(D5)
    );
    serial_link link (
        .sample_clk(sample_clk), .reset(!startup[3]),
        .serial_rx(rx_p & ~rx_n), .serial_tx(tx),
        .generator_enable(generator_enable), .analyzer_enable(analyzer_enable),
        .sent(sent), .received(received), .bad_crc(bad_crc), .bad_preamble(bad_preamble),
        .tx_seen(D1), .rx_seen(D2), .good_seen(D3),
        .error_seen(D4), .link_up(D5)
    );
    assign tx_p = tx;
    assign tx_n = ~tx;
endmodule

module serial_link #(
    parameter integer FRAME_PERIOD = 1000000
)(
    input sample_clk, reset, serial_rx, generator_enable, analyzer_enable,
    output reg [7:0] sent, received, bad_crc, bad_preamble,
    output serial_tx,
    output reg tx_seen, rx_seen, good_seen, error_seen,
    output link_up
);
    initial {sent, received, bad_crc, bad_preamble, good_seen, error_seen} = 0;
    always @* begin
        tx_seen = sent[0];
        rx_seen = received[0];
    end
    reg [1:0] bit_div = 0;
    always @(posedge sample_clk)
        bit_div <= bit_div + 1'b1;

    wire tx_clk, rx_clk, rx_dv, rx_er, cdr_locked, pcs_synced, rx_abort;
    wire [7:0] rx_data;
    reg [7:0] tx_data = 0;
    reg tx_valid = 0;
    // Reset on bit-clock edges before the PCS generates any GMII clocks.
    gmii_to_1000basex transmitter (
        .bit_clk(bit_div[1]), .rst(reset), .gmii_tx_clk(tx_clk),
        .gmii_txd(tx_data), .gmii_tx_en(tx_valid), .gmii_tx_er(1'b0),
        .config_enable(1'b0), .config_word(16'd0), .serial_tx(serial_tx)
    );
    basex1000_to_gmii receiver (
        .sample_clk(sample_clk), .rst(reset), .serial_rx(serial_rx),
        .signal_detect(1'b1), .gmii_rx_clk(rx_clk), .gmii_rxd(rx_data),
        .gmii_rx_dv(rx_dv), .gmii_rx_er(rx_er), .cdr_locked(cdr_locked),
        .pcs_synced(pcs_synced), .rx_abort(rx_abort)
    );
    assign link_up = cdr_locked && pcs_synced;

    `include "draft-frame.vh"

    // A synchronous byte ROM uses block RAM and leaves room for the PCS.
    (* ram_style = "block" *) reg [7:0] frame_rom [0:127];
    integer index;
    reg [31:0] word_data;
    initial begin
        for (index = 0; index < 128; index = index + 1) begin
            word_data = draft_frame_word(index[6:2]);
            frame_rom[index] = word_data[8 * (3 - index[1:0]) +: 8];
        end
    end

    reg [$clog2(FRAME_PERIOD)-1:0] tx_cycle = 0;
    reg generator_running = 0;
    always @(posedge tx_clk) begin
        if (tx_cycle == FRAME_PERIOD-1)
            generator_running <= generator_enable;
        tx_cycle <= (tx_cycle == FRAME_PERIOD-1) ? 0 : tx_cycle + 1'b1;
        tx_valid <= generator_running && tx_cycle < FRAME_BYTES;
        tx_data <= frame_rom[tx_cycle[6:0]];
        if (generator_running && tx_cycle == FRAME_BYTES-1)
            sent <= sent + 1'b1;
    end

    // Verify the Ethernet CRC residue over the received frame including FCS.
    reg in_frame = 0, in_payload = 0, rx_bad = 0;
    reg [3:0] preamble = 0;
    reg [6:0] length = 0;
    wire [31:0] crc;
    ethernet_crc_8 checker_crc (
        .clk(rx_clk), .reset(reset), .d(rx_data), .calc(1'b1),
        .init(!rx_dv), .d_valid(rx_dv && in_payload),
        .crc_reg(crc)
    );
    always @(posedge rx_clk) begin
        if (!rx_dv) begin
            if (in_frame && analyzer_enable) begin
                if (in_payload && length >= 64 && !rx_bad && !rx_er &&
                        crc == 32'hc704dd7b) begin
                    received <= received + 1'b1;
                    good_seen <= 1;
                end else begin
                    if (in_payload)
                        bad_crc <= bad_crc + 1'b1;
                    else
                        bad_preamble <= bad_preamble + 1'b1;
                    error_seen <= 1;
                end
            end
            in_frame <= 0;
            in_payload <= 0;
            rx_bad <= 0;
            preamble <= 0;
            length <= 0;
        end else begin
            in_frame <= 1;
            if (rx_er)
                rx_bad <= 1;
            if (in_payload) begin
                if (length < 64)
                    length <= length + 1'b1;
            end else if (rx_data == 8'h55 && preamble < 7) begin
                preamble <= preamble + 1'b1;
            end else if (rx_data == 8'hd5 && (preamble == 6 || preamble == 7)) begin
                in_payload <= 1;
            end else begin
                rx_bad <= 1;
            end
        end
    end
endmodule
