// Combinational interface retained for existing users and decoder checks.
module encoder_8b10b (
    input wire [7:0] data,
    input wire is_k,
    input wire rd_in,
    output wire [9:0] code,
    output wire rd_out,
    output wire invalid_k
);
    wire [5:0] six;
    wire [3:0] four;
    wire six_unbalanced, six_flip, four_unbalanced, four_flip, alt_neg, alt_pos;
    encoder_8b10b_lookup lookup (
        .data(data), .is_k(is_k), .six(six), .four(four),
        .six_unbalanced(six_unbalanced), .six_flip(six_flip),
        .four_unbalanced(four_unbalanced), .four_flip(four_flip),
        .alt_neg(alt_neg), .alt_pos(alt_pos), .invalid_k(invalid_k)
    );
    encoder_8b10b_disparity finish (
        .six(six), .four(four), .six_unbalanced(six_unbalanced), .six_flip(six_flip),
        .four_unbalanced(four_unbalanced), .four_flip(four_flip),
        .alt_neg(alt_neg), .alt_pos(alt_pos), .rd_in(rd_in), .code(code), .rd_out(rd_out)
    );
endmodule

// Stage 1: lookup and data-dependent flags, independent of running disparity.
module encoder_8b10b_lookup (
    input wire [7:0] data,
    input wire is_k,
    output reg [5:0] six,
    output reg [3:0] four,
    output reg six_unbalanced, six_flip, four_unbalanced, four_flip,
    output reg alt_neg, alt_pos,
    output wire invalid_k
);
    wire legal_k = (data[4:0] == 5'd28) ||
        ((data[7:5] == 3'd7) &&
         ((data[4:0] == 5'd23) || (data[4:0] == 5'd27) ||
          (data[4:0] == 5'd29) || (data[4:0] == 5'd30)));
    assign invalid_k = is_k && !legal_k;
    wire [7:0] value = invalid_k ? 8'hfe : data;

    always @* begin
        case (value[4:0])
            5'd0: six = 6'b011000;
            5'd1: six = 6'b100010;
            5'd2: six = 6'b010010;
            5'd3: six = 6'b110001;
            5'd4: six = 6'b001010;
            5'd5: six = 6'b101001;
            5'd6: six = 6'b011001;
            5'd7: six = 6'b000111;
            5'd8: six = 6'b000110;
            5'd9: six = 6'b100101;
            5'd10: six = 6'b010101;
            5'd11: six = 6'b110100;
            5'd12: six = 6'b001101;
            5'd13: six = 6'b101100;
            5'd14: six = 6'b011100;
            5'd15: six = 6'b101000;
            5'd16: six = 6'b100100;
            5'd17: six = 6'b100011;
            5'd18: six = 6'b010011;
            5'd19: six = 6'b110010;
            5'd20: six = 6'b001011;
            5'd21: six = 6'b101010;
            5'd22: six = 6'b011010;
            5'd23: six = 6'b000101;
            5'd24: six = 6'b001100;
            5'd25: six = 6'b100110;
            5'd26: six = 6'b010110;
            5'd27: six = 6'b001001;
            5'd28: six = 6'b001110;
            5'd29: six = 6'b010001;
            5'd30: six = 6'b100001;
            5'd31: six = 6'b010100;
        endcase
        six_unbalanced = (value[4:0] == 0) || (value[4:0] == 1) ||
            (value[4:0] == 2) || (value[4:0] == 4) || (value[4:0] == 8) ||
            (value[4:0] == 15) || (value[4:0] == 16) || (value[4:0] == 23) ||
            (value[4:0] == 24) || (value[4:0] == 27) || (value[4:0] == 29) ||
            (value[4:0] == 30) || (value[4:0] == 31);
        six_flip = six_unbalanced || (value[4:0] == 7);
        if (is_k && value[4:0] == 28) begin
            six = 6'b110000;
            six_unbalanced = 1'b1;
            six_flip = 1'b1;
        end
        case (value[7:5])
            3'd0: four = 4'b0100;
            3'd1: four = 4'b1001;
            3'd2: four = 4'b0101;
            3'd3: four = 4'b0011;
            3'd4: four = 4'b0010;
            3'd5: four = 4'b1010;
            3'd6: four = 4'b0110;
            3'd7: four = 4'b0001;
        endcase
        four_unbalanced = (value[7:5] == 0) || (value[7:5] == 4) ||
                          (value[7:5] == 7);
        four_flip = is_k || four_unbalanced || (value[7:5] == 3);
        alt_neg = (value[7:5] == 7) && (is_k ||
                  (value[4:0] == 17) || (value[4:0] == 18) || (value[4:0] == 20));
        alt_pos = (value[7:5] == 7) && (is_k ||
                  (value[4:0] == 11) || (value[4:0] == 13) || (value[4:0] == 14));
    end
endmodule

// Stage 2: disparity adjustment, fed from registered lookup results in the PCS.
module encoder_8b10b_disparity (
    input wire [5:0] six,
    input wire [3:0] four,
    input wire six_unbalanced, six_flip, four_unbalanced, four_flip,
    input wire alt_neg, alt_pos, rd_in,
    output reg [9:0] code,
    output reg rd_out
);
    reg [5:0] six_out;
    reg [3:0] four_out;
    reg rd_mid;
    always @* begin
        rd_mid = rd_in ^ six_unbalanced;
        six_out = (!rd_in && six_flip) ? ~six : six;
        if (!rd_mid && alt_neg) begin
            four_out = 4'b0111;
            rd_out = !rd_mid;
        end else if (rd_mid && alt_pos) begin
            four_out = 4'b1000;
            rd_out = !rd_mid;
        end else begin
            four_out = (!rd_mid && four_flip) ? ~four : four;
            rd_out = rd_mid ^ four_unbalanced;
        end
        code = {six_out, four_out};
    end
endmodule

// One PCS-symbol register followed by nine registered binary decisions.
// Both disparity variants are precomputed, leaving running disparity out of
// the deep pipeline. Entry: {invalid_k, rd_plus, rd_minus, code_plus, code_minus}.
// Truth table generated from sim/encoder_vectors.csv (including K30.7 fallback).
module encoder_8b10b_pipelined (
    input wire clk, rst, ce,
    input wire [7:0] data,
    input wire is_k, rd_in,
    input wire idle_data,
    output wire [9:0] code,
    output wire rd_out, invalid_k, valid,
    output wire [7:0] symbol_data,
    output wire symbol_is_k
);
    localparam [11775:0] TABLE = {
        512'hd0bbd0a177a122f742c1cf844bed1a177a342ef4685de842bf51a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a34,
        512'h2ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef41c24f6d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0b,
        512'hbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef,
        512'h41c14fad0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1,
        512'ha177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef42c34f2d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef468,
        512'h5de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef41c30f3d0bbd1a17,
        512'h7a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de,
        512'h8d0bbd1a177a342ef4685de8d0bbd1a177a342ef41c28f5d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a3,
        512'h42ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef41c18f9d0bbd1a177a342ef4685de8d0,
        512'hbbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342e,
        512'hf4685de8d0bbd1a177a342ef42c2cf4d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd,
        512'h1a177a342ef4685de8d0bbd1a177a342ef4685de8d0bbd1a177a342ef4685de84a7562a1e78523d709384ee44f6c25615b8cc337233b3142f7425a16b8d43571,
        512'h2c4b7390e5c5314dcc631ba939b15472e25c8738d91671344de3a469c551578ca32f21bb91238f1c591678d234f22bb51388e3c92eb4545ce8a63a712a356c61,
        512'h6798a2d732398e624b6cc9665994cd33131b3622b74c9a669954d5322d8b659364c9364d946d1b1919b63432ec9c671958d632358d65a368c9565594ad2b119b,
        512'h9643b70c99665952d4b129b5658b62c526b58c4ceb161a762a557461a7a8a357523a8ea24d6d496a5a94d535132b3a22d7549aa6a95555522e8ba59565493a4e,
        512'h94751d1929ba3452f49ca729595652368da5a569495a5694b52d11ab9a43d71499a6695354d12ab5a58d63452ab68c54ed162a7a4a6d64a1d78923b711388ed4,
        512'h4eec45625b4cc536a3373242ef445a26b4d455692c8bd39165a5324f4c651ea935b2546ae45c2734d85669348dd3a169a552574ca52ea1b79223971a592674d2,
        512'h54ea2b75238963a92db4945ae92636722a656661c78ca3971a38cec24e6c69635b14c73613333322e7469a36b15475622ccbc591e589334f14671e1931b33462,
        512'he69c373158766234cdc5a1e989535714a72e11b393439f189936715274e12b353589e3852cb4cc58e99632732a2d6a615794a2b72a394e524aeca9655954cb32,
        512'h93173522af4a9a569554b52a2d4b5592e4a9354d546b1a9915b5342aea9c571558b62a354d55a2e8a9555554ab2a91979543af0a99565552b4a92975558ae2a5,
        512'h25b54c4aea9616752a4d726197a4a3374a3a4e924ced29695a54d33493273922cf529a96a555354a2e4b9594e529394e54731c9925b9344af29c972559364a36,
        512'h4d95a4e929595654b32c91a79943cf129996655334c92a75958ce32529b64c52ec9626794a5d68a1b791237721390eb44dec85645accc935a32f3442df485a46,
        512'hacd495592d0bb3926565344ecc691da92db4545ae85c472cd89659350db3a269655456cca92da1af9423a71659466cd294da2af5438a63692bb51456ea262e74
    };
    reg [9:0] raw_symbol; // Registered {idle_data, is_k, data} before bank distribution.
    reg raw_valid;
    reg [9:0] tag [0:8]; // {idle_data, is_k, data}, aligned with each stage.
    reg [8:0] valid_pipe;
    integer n;
    // Only validity resets. Payload may contain arbitrary old values until
    // ten enabled cycles have replaced it; output masking below hides them.
    always @(posedge clk) begin
        if (rst) begin raw_valid <= 1'b0; valid_pipe <= 9'd0; end
        else if (ce) begin
            raw_valid <= 1'b1;
            valid_pipe <= {valid_pipe[7:0], raw_valid};
        end
    end
    always @(posedge clk) begin
        if (ce) begin
            raw_symbol <= {idle_data, is_k, data};
            tag[0] <= raw_symbol;
            for (n=1; n<9; n=n+1) tag[n] <= tag[n-1];
        end
    end
    // Four adjacent lookup entries per selector bank. First-level banks
    // also replicate bit 0 to avoid sharing a broadcast partial result.
    // Replicas sample the preceding address-delay stage, so they replace (rather than extend)
    // the original selector register's latency. Process-level keep is
    // required: a wire-level keep alone does not prevent FF merging.
    genvar bit_index, bank_index, bank_entry;
    generate for (bit_index=1; bit_index<9; bit_index=bit_index+1) begin : stage
        localparam ENTRY_COUNT = 256 >> bit_index;
        reg [22:0] entries [0:ENTRY_COUNT-1];
        for (bank_index=0; bank_index<(ENTRY_COUNT+3)/4; bank_index=bank_index+1) begin : bank
            if (bit_index > 0) begin : local_select
                reg value;
                if (bit_index == 1) begin : raw
                    reg low_bit;
                    (* keep = 1 *) always @(posedge clk) begin
                        if (ce) begin value <= raw_symbol[1]; low_bit <= raw_symbol[0]; end
                    end
                end else begin : delayed
                    (* keep = 1 *) always @(posedge clk) begin
                        if (ce) value <= tag[bit_index-2][bit_index];
                    end
                end
            end
            for (bank_entry=0; bank_entry<4; bank_entry=bank_entry+1) begin : decision
                localparam ENTRY = 4*bank_index + bank_entry;
                if (ENTRY < ENTRY_COUNT) begin : present
                    if (bit_index == 1) begin : first_pair
                        always @(posedge clk) begin
                            if (ce) entries[ENTRY] <= local_select.value ?
                                (local_select.raw.low_bit ? TABLE[(4*ENTRY+3)*23 +: 23] :
                                                            TABLE[(4*ENTRY+2)*23 +: 23]) :
                                (local_select.raw.low_bit ? TABLE[(4*ENTRY+1)*23 +: 23] :
                                                            TABLE[4*ENTRY*23 +: 23]);
                        end
                    end else begin : following
                        always @(posedge clk) begin
                            if (ce) entries[ENTRY] <= local_select.value ?
                                stage[bit_index-1].entries[2*ENTRY+1] :
                                stage[bit_index-1].entries[2*ENTRY];
                        end
                    end
                end
            end
        end
    end endgenerate
    wire [22:0] result = stage[8].entries[0];
    wire idle = tag[8][9];
    // The comma preceding /I/ toggles disparity. Pick the idle data symbol
    // from the disparity AFTER that comma, rather than predicting ten
    // in-flight symbols at the input. Both idle variants finish negative.
    wire [9:0] selected_code = idle ? (rd_in ? 10'h245 : 10'h296) :
                                    (rd_in ? result[19:10] : result[9:0]);
    wire selected_rd = idle ? 1'b0 : (rd_in ? result[21] : result[20]);
    assign valid = valid_pipe[8];
    // Keep the same known K28.5 startup placeholder as the reset-filled
    // implementation. PCS ignores its disparity until valid becomes true.
    assign code = valid ? selected_code : (rd_in ? 10'h305 : 10'h0fa);
    assign rd_out = valid ? selected_rd : ~rd_in;
    assign invalid_k = valid && !idle && result[22];
    assign symbol_data = !valid ? 8'hbc : (idle ? (rd_in ? 8'h50 : 8'hc5) : tag[8][7:0]);
    assign symbol_is_k = !valid || (!idle && tag[8][8]);
endmodule
