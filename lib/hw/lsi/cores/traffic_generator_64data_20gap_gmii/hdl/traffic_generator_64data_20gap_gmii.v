// SPDX-License-Identifier: BSD-2-Clause
// Attribution and license terms: project-root COPYRIGHT.
module traffic_generator_64data_20gap_gmii (
    input wire clk,
    input wire resetn,
    output reg [7:0] gmii_d,
    output reg gmii_en,
    output wire gmii_er,
    output reg cycle_start
);
    // Fixed frame body: draft-ietf-bmwg-network-tester-cfg-17, Appendix A.2.
    // Ethernet FCS is appended in wire byte order: 6e ec f3 05.
    // 84 clocks: 8 preamble/SFD + 64 frame (including FCS) + 12 idle.
    // Bit 9: cycle_start, bit 8: gmii_en, bits 7:0: gmii_d.
    // Force block-memory inference even though this ROM is small.
    (* ram_style = "block" *) reg [9:0] pattern [0:127];
    integer i;
    initial begin
        for (i=0; i<128; i=i+1) pattern[i] = 10'd0;
        pattern[0] = 10'h355;
        pattern[1] = 10'h155;
        pattern[2] = 10'h155;
        pattern[3] = 10'h155;
        pattern[4] = 10'h155;
        pattern[5] = 10'h155;
        pattern[6] = 10'h155;
        pattern[7] = 10'h1d5;
        pattern[8] = 10'h16c;
        pattern[9] = 10'h1a9;
        pattern[10] = 10'h16f;
        pattern[11] = 10'h100;
        pattern[12] = 10'h100;
        pattern[13] = 10'h102;
        pattern[14] = 10'h16c;
        pattern[15] = 10'h1a9;
        pattern[16] = 10'h16f;
        pattern[17] = 10'h100;
        pattern[18] = 10'h100;
        pattern[19] = 10'h101;
        pattern[20] = 10'h108;
        pattern[21] = 10'h100;
        pattern[22] = 10'h145;
        pattern[23] = 10'h100;
        pattern[24] = 10'h100;
        pattern[25] = 10'h12e;
        pattern[26] = 10'h1d4;
        pattern[27] = 10'h1a5;
        pattern[28] = 10'h100;
        pattern[29] = 10'h100;
        pattern[30] = 10'h10a;
        pattern[31] = 10'h111;
        pattern[32] = 10'h158;
        pattern[33] = 10'h116;
        pattern[34] = 10'h1c0;
        pattern[35] = 10'h100;
        pattern[36] = 10'h102;
        pattern[37] = 10'h101;
        pattern[38] = 10'h1c0;
        pattern[39] = 10'h100;
        pattern[40] = 10'h102;
        pattern[41] = 10'h102;
        pattern[42] = 10'h1c0;
        pattern[43] = 10'h120;
        pattern[44] = 10'h100;
        pattern[45] = 10'h107;
        pattern[46] = 10'h100;
        pattern[47] = 10'h11a;
        pattern[48] = 10'h100;
        pattern[49] = 10'h100;
        pattern[50] = 10'h101;
        pattern[51] = 10'h102;
        pattern[52] = 10'h103;
        pattern[53] = 10'h104;
        pattern[54] = 10'h105;
        pattern[55] = 10'h106;
        pattern[56] = 10'h107;
        pattern[57] = 10'h108;
        pattern[58] = 10'h109;
        pattern[59] = 10'h10a;
        pattern[60] = 10'h10b;
        pattern[61] = 10'h10c;
        pattern[62] = 10'h10d;
        pattern[63] = 10'h10e;
        pattern[64] = 10'h10f;
        pattern[65] = 10'h110;
        pattern[66] = 10'h111;
        pattern[67] = 10'h112;
        pattern[68] = 10'h16e;
        pattern[69] = 10'h1ec;
        pattern[70] = 10'h1f3;
        pattern[71] = 10'h105;
    end

    reg [6:0] position;
    reg [9:0] rom_word;
    reg read_valid;
    // No reset or address look-ahead on the synchronous ROM read port.
    // This register is absorbed into the inferred block RAM's read port.
    always @(posedge clk) rom_word <= pattern[position];

    assign gmii_er = 1'b0;
    always @(posedge clk) begin
        if (!resetn) begin
            position <= 7'd0;
            read_valid <= 1'b0;
            gmii_d <= 8'd0;
            gmii_en <= 1'b0;
            cycle_start <= 1'b0;
        end else begin
            position <= (position == 7'd83) ? 7'd0 : position + 7'd1;
            read_valid <= 1'b1;
            // Fabric output register splits RAM output routing from PCS logic.
            // Exactly one idle startup cycle primes the synchronous ROM.
            gmii_d <= read_valid ? rom_word[7:0] : 8'd0;
            gmii_en <= read_valid && rom_word[8];
            cycle_start <= read_valid && rom_word[9];
        end
    end
endmodule
