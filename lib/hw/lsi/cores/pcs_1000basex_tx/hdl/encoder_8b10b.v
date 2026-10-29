module encoder_8b10b (
    input wire [7:0] data,
    input wire is_k,
    input wire rd_in,
    output reg [9:0] code,
    output reg rd_out,
    output wire invalid_k
);
    wire legal_k = (data[4:0] == 5'd28) ||
        ((data[7:5] == 3'd7) &&
         ((data[4:0] == 5'd23) || (data[4:0] == 5'd27) ||
          (data[4:0] == 5'd29) || (data[4:0] == 5'd30)));
    assign invalid_k = is_k && !legal_k;
    wire [7:0] value = invalid_k ? 8'hfe : data;
    reg [5:0] six, six_out;
    reg [3:0] four, four_out;
    reg six_unbalanced, six_flip, four_unbalanced, four_flip;
    reg rd_mid, alt_neg, alt_pos;

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
