// SPDX-License-Identifier: GPL-3.0-or-later
module spi_regs (
    input clk, spi_clk, spi_cs_n, spi_mosi,
    output spi_miso,
    output reg generator_enable, analyzer_enable,
    input [7:0] sent, received, bad_crc, bad_preamble,
    input link_up
);
    initial {generator_enable, analyzer_enable} = 2'b11;
    // Oversample the Pi's SPI mode-0 signals with the FPGA system clock.
    (* async_reg = "true" *) reg [1:0] sck = 0, cs = 3, mosi = 0;
    reg prev_sck = 0;
    reg [4:0] bits = 0;
    reg [7:0] shift = 0;
    reg [7:0] command = 0;
    reg pending_read = 0;
    wire [7:0] assembled = {shift[6:0], mosi[1]};

    always @(posedge clk) begin
        sck <= {sck[0], spi_clk};
        cs <= {cs[0], spi_cs_n};
        mosi <= {mosi[0], spi_mosi};
        prev_sck <= sck[1];
        pending_read <= 0;

        if (cs[1]) begin
            bits <= 0;
        end else begin
            if (pending_read) begin
                case (command[6:0])
                    7'h00: shift <= {7'd0, generator_enable};
                    7'h01: shift <= sent;
                    7'h10: shift <= {7'd0, analyzer_enable};
                    7'h11: shift <= received;
                    7'h12: shift <= bad_crc;
                    7'h13: shift <= bad_preamble;
                    7'h14: shift <= {7'd0, link_up};
                    default: shift <= 0;
                endcase
            end
            if (sck[1] && !prev_sck && bits < 16) begin
                bits <= bits + 1'b1;
                shift <= assembled;
                if (bits == 7) begin
                    command <= assembled;
                    pending_read <= !assembled[7];
                end
                if (bits == 15 && command[7]) begin
                    case (command[6:0])
                        7'h00: generator_enable <= assembled[0];
                        7'h10: analyzer_enable <= assembled[0];
                        default: begin end
                    endcase
                end
            end
        end
    end

    // Share MISO with CE0, the configuration flash.
    assign spi_miso = spi_cs_n ? 1'bz : (bits[4:3] == 2'b01 ? shift[7] : 1'b0);
endmodule
