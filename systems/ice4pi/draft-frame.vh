// SPDX-License-Identifier: GPL-3.0-or-later
// draft-ietf-bmwg-network-tester-cfg-17, Appendices A.2 and A.4.
// Preamble and SFD precede the example data, and the FCS follows it.
localparam integer FRAME_BYTES = 72;
function [31:0] draft_frame_word(input [4:0] index);
    begin
        case (index)
            5'd0 : draft_frame_word = 32'h55555555;
            5'd1 : draft_frame_word = 32'h555555d5;
            5'd2 : draft_frame_word = 32'h6ca96f00;
            5'd3 : draft_frame_word = 32'h00026ca9;
            5'd4 : draft_frame_word = 32'h6f000001;
            5'd5 : draft_frame_word = 32'h08004500;
            5'd6 : draft_frame_word = 32'h002ed4a5;
            5'd7 : draft_frame_word = 32'h00000a11;
            5'd8 : draft_frame_word = 32'h5816c000;
            5'd9 : draft_frame_word = 32'h0201c000;
            5'd10: draft_frame_word = 32'h0202c020;
            5'd11: draft_frame_word = 32'h0007001a;
            5'd12: draft_frame_word = 32'h00000102;
            5'd13: draft_frame_word = 32'h03040506;
            5'd14: draft_frame_word = 32'h0708090a;
            5'd15: draft_frame_word = 32'h0b0c0d0e;
            5'd16: draft_frame_word = 32'h0f101112;
            5'd17: draft_frame_word = 32'h6eecf305;
            default: draft_frame_word = 0;
        endcase
    end
endfunction
