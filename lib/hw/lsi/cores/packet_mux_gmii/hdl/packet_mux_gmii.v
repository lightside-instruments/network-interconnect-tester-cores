`timescale 1ns/1ps

module packet_mux_gmii
#(

 // AXI Registers Data Width
    parameter C_S_AXI_DATA_WIDTH    = 32,          
    parameter C_S_AXI_ADDR_WIDTH    = 12,          
    parameter C_BASEADDR            = 32'h00000000

)
(
    // Global Ports
    input clk,

    // GMII input 0
    input [7:0] gmii_d_in0,
    input gmii_en_in0,
    input gmii_er_in0,

    // GMII input 1
    input [7:0] gmii_d_in1,
    input gmii_en_in1,
    input gmii_er_in1,

    // GMII output
    output reg [7:0] gmii_d_out,
    output reg gmii_en_out,
    output reg gmii_er_out

);

   // GMII input 0
   reg [7:0] gmii_d_in0_r0 = 0;
   reg gmii_en_in0_r0 = 0;
   reg gmii_er_in0_r0 = 0;
   reg [7:0] gmii_d_in0_r1 = 0;
   reg gmii_en_in0_r1 = 0;
   reg gmii_er_in0_r1 = 0;

   // GMII input 1
   reg [7:0] gmii_d_in1_r0 = 0;
   reg gmii_en_in1_r0 = 0;
   reg gmii_er_in1_r0 = 0;
   reg [7:0] gmii_d_in1_r1 = 0;
   reg gmii_en_in1_r1 = 0;
   reg gmii_er_in1_r1 = 0;

   reg     [7:0]   state = 0;
   reg     [31:0]  interframe_gap_delay = 0;



always @(posedge clk) begin
    gmii_d_in0_r0 <= gmii_d_in0;
    gmii_en_in0_r0 <= gmii_en_in0;
    gmii_er_in0_r0 <= gmii_er_in0;
    gmii_d_in0_r1 <= gmii_d_in0_r0;
    gmii_en_in0_r1 <= gmii_en_in0_r0;
    gmii_er_in0_r1 <= gmii_er_in0_r0;
end

always @(posedge clk) begin
    gmii_d_in1_r0 <= gmii_d_in1;
    gmii_en_in1_r0 <= gmii_en_in1;
    gmii_er_in1_r0 <= gmii_er_in1;
    gmii_d_in1_r1 <= gmii_d_in1_r0;
    gmii_en_in1_r1 <= gmii_en_in1_r0;
    gmii_er_in1_r1 <= gmii_er_in1_r0;
end

always @(posedge clk) begin
    case(state)
    8'h01 : begin
        gmii_d_out <= gmii_d_in0_r1;
        gmii_en_out <= gmii_en_in0_r1;
        gmii_er_out <= gmii_er_in0_r1;
        if(gmii_en_in0_r0==0) begin
            state <= 0;
        end
    end
    8'h02 : begin
        gmii_d_out <= gmii_d_in1_r1;
        gmii_en_out <= gmii_en_in1_r1;
        gmii_er_out <= gmii_er_in1_r1;
        if(gmii_en_in1_r0==0) begin
            state <= 0;
        end
    end
    default: begin
        gmii_d_out <= 0;
        gmii_en_out <= 0;
        gmii_er_out <= 0;
        if(interframe_gap_delay>0) begin
            interframe_gap_delay <= interframe_gap_delay - 1;
        end
        if(gmii_en_in0_r0==1 && gmii_en_in0_r1==0) begin
            state <= 1;
        end
        else if(gmii_en_in1_r0==1 && gmii_en_in1_r1==0) begin
            state <= 2;
        end
    end
    endcase
end
endmodule
