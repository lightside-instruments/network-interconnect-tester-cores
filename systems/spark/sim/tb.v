`timescale 1ns / 1ps

module tb();
  localparam HALF_CLK_PERIOD = 0.8;

  // Should be updated according to the generated address map
  localparam [31:0] gmii_mux_0_address = 32'hA00F0000;
  localparam [31:0] gmii_mux_1_address = 32'hA0100000;
  localparam [31:0] gmii_mux_6_address = 32'hA0150000;
  localparam [31:0] axi_ethernet_0_address = 32'hA0000000;
  localparam [31:0] traffic_generator_gmii_0_address = 32'hA0160000;
  localparam [31:0] traffic_generator_gmii_1_address = 32'hA0170000;
  localparam [31:0] traffic_analyzer_gmii_0_address = 32'hA0180000;
  reg aclk =1'b0;
  reg arstn = 1'b0;

  reg BT_ctsn;

  wire sfp_port_0_rxn;
  wire sfp_port_0_rxp;
  wire sfp_port_1_rxn;
  wire sfp_port_1_rxp;

  wire BT_ctsn;
  wire BT_rtsn;

  wire sfp_port_0_txn;
  wire sfp_port_0_txp;
  wire sfp_port_1_txn;
  wire sfp_port_1_txp;


  reg resp;
  reg [31:0] read_data;
  reg [63:0] read_data_64;
  reg [63:0] read_data_again_64;

  spark_wrapper spark_wrapper_i
       (.BT_ctsn(BT_ctsn),
        .BT_rtsn(BT_rtsn),
        .sfp_port_0_rxn(sfp_port_0_rxn),
        .sfp_port_0_rxp(sfp_port_0_rxp),
        .sfp_port_0_txn(sfp_port_0_txn),
        .sfp_port_0_txp(sfp_port_0_txp),
        .sfp_port_1_rxn(sfp_port_1_rxn),
        .sfp_port_1_rxp(sfp_port_1_rxp),
        .sfp_port_1_txn(sfp_port_1_txn),
        .sfp_port_1_txp(sfp_port_1_txp));

task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.write_burst_strb(addr,0,2,0,0,0,0,data,1,16'h000F,4,resp);
    end
endtask

task axi_read;
    input [31:0] addr;
    output reg [31:0] data;
    reg resp;
    begin
        tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.read_data(addr, 8'd4, data, resp);
    end
endtask


 // rеsеt
 initial begin
    arstn = 1'b0;
    #(HALF_CLK_PERIOD * 2*10);
    arstn = 1'b1;
    #(HALF_CLK_PERIOD * 2*10);

    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.por_srstb_reset(1'b1);
    #200;
    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.por_srstb_reset(1'b0);
    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h1);
    #2000 ;  // This delay depends on your clock frequency. It should be at least 16 clock cycles.
    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.por_srstb_reset(1'b1);
    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h0);
    #2000 ;

    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h2);

    #20000 ;

    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h0);

    #20000 ;

    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h2);

    #20000 ;

    tb.spark_wrapper_i.spark_i.zynq_ultra_ps_e_0.inst.fpga_soft_reset(32'h0);

    #1000 ;

    axi_read(traffic_analyzer_gmii_0_address+32'h28, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h2C, read_data_64[31:0]);
    $display("traffic_analyzer_gmii OCTETS reg (%x)", read_data_64);

    axi_read(traffic_analyzer_gmii_0_address+32'h58, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h5C, read_data_64[31:0]);
    $display("traffic_analyzer_gmii BAD_CRC_PKTS reg (%x)", read_data_64);


    /* enable port0 traffic generator */
    axi_read(gmii_mux_0_address, read_data);
    axi_write(gmii_mux_0_address+8, 32'h00000003);

    /* enable port1 traffic generator */
    axi_read(gmii_mux_1_address, read_data);
    axi_write(gmii_mux_1_address+8, 32'h00000003);

    /* enable port1 traffic analyzer */
    axi_read(gmii_mux_6_address, read_data);
    axi_write(gmii_mux_6_address+8, 32'h00000000);

    axi_read(gmii_mux_0_address+32'h00, read_data);
    $display("gmii_mux IP id (%x)", read_data);

    axi_read(traffic_generator_gmii_1_address+32'h00, read_data);
    $display("traffic_generator_gmii IP id (%x)", read_data);

    axi_write(traffic_generator_gmii_1_address+32'h0C, 32'h12345678);
    axi_read(traffic_generator_gmii_1_address+32'h0C, read_data);
    $display("traffic_generator_gmii FLIP reg (%x)", read_data);

    axi_write(traffic_analyzer_gmii_0_address+32'h0C, 32'h12345678);
    axi_read(traffic_analyzer_gmii_0_address+32'h0C, read_data);
    $display("traffic_analyzer_gmii FLIP reg (%x)", read_data);

    axi_write(traffic_generator_gmii_1_address+32'h14, 32'h0000000C); /* interframe gap */
    axi_write(traffic_generator_gmii_1_address+32'h44, 32'd50); /* layer 1 frame size -seqnum(8) - timestamp(10) - crc(4) */
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h55555555);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h555555d5);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h01020304);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h05060708);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h090a0b0c);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h0d0e0f10);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h11121314);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h15161718);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h191a1b1c);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h1d1e1f20);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h21222324);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h25262728);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h292a2b2c);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h2d2e2f30);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h31323334);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h35363738);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h393a3b3c);
    axi_write(traffic_generator_gmii_1_address+32'h50, 32'h344ca062);
    axi_write(traffic_generator_gmii_1_address+32'h14, 32'h0000000C); /* interframe gap */

    axi_write( traffic_analyzer_gmii_0_address+16, 32'h00000001); /* set the enable bit reg control[0] */
    axi_write(traffic_generator_gmii_1_address+16, 32'h00000003); /* set the enable bit reg control[0] and dynamic mode control[1]*/

    #50000 ;

    axi_write(traffic_generator_gmii_1_address+16, 32'h00000000); /* clear the enable bit reg control[0] */
    axi_write(traffic_analyzer_gmii_0_address+16, 32'h00000003); /* set the freeze bit reg control[1] */
    #5000

    axi_write(traffic_generator_gmii_1_address+32'h0C, 32'h12345678);
    axi_read(traffic_generator_gmii_1_address+32'h0C, read_data);
    $display("traffic_generator_gmii FLIP reg (%x)", read_data);

    axi_write(traffic_analyzer_gmii_0_address+32'h0C, 32'h12345678);
    axi_read(traffic_analyzer_gmii_0_address+32'h0C, read_data);
    $display("traffic_analyzer_gmii FLIP reg (%x)", read_data);

    axi_read(traffic_analyzer_gmii_0_address+32'h28, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h2C, read_data_64[31:0]);
    $display("traffic_analyzer_gmii OCTETS reg (%x)", read_data_64);
    axi_read(traffic_analyzer_gmii_0_address+32'h30, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h34, read_data_64[31:0]);
    $display("traffic_analyzer_gmii OCTETS_IDLE reg (%x)", read_data_64);
    axi_read(traffic_analyzer_gmii_0_address+32'h20, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h24, read_data_64[31:0]);
    $display("traffic_analyzer_gmii PKTS reg (%x)", read_data_64);
    axi_read(traffic_analyzer_gmii_0_address+32'h58, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h5C, read_data_64[31:0]);
    $display("traffic_analyzer_gmii BAD_CRC_PKTS reg (%x)", read_data_64);
    axi_read(traffic_analyzer_gmii_0_address+32'h60, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h64, read_data_64[31:0]);
    $display("traffic_analyzer_gmii BAD_CRC_OCTETS reg (%x)", read_data_64);

    axi_read(traffic_analyzer_gmii_0_address+32'h98, read_data);
    $display("traffic_analyzer_gmii LATENCY_MIN_NSEC reg (%u)", read_data);

    axi_read(traffic_analyzer_gmii_0_address+32'hA8, read_data);
    $display("traffic_analyzer_gmii LATENCY_MAX_NSEC reg (%u)", read_data);

    axi_read(traffic_analyzer_gmii_0_address+32'hB8, read_data);
    $display("traffic_analyzer_gmii LATENCY_NSEC reg (%u)", read_data);


    axi_read(traffic_analyzer_gmii_0_address+32'h20, read_data_64[63:32]);
    axi_read(traffic_analyzer_gmii_0_address+32'h24, read_data_64[31:0]);
    $display("traffic_analyzer_gmii PKTS reg (%x)", read_data_64);

    // Read RX Good Frames counter pg051
    axi_read(axi_ethernet_0_address+32'h00000290, read_data_64[31:0]);
    axi_read(axi_ethernet_0_address+32'h00000294, read_data_64[63:32]);
    $display("Read RX Good Frames counter pg051 reg (%x)", read_data_64);

    if(read_data_64 < 2) begin
      $error("Too few frames received at eth0");
    end

    #5000

   // Read RX Good Frames counter pg051
    axi_read(axi_ethernet_0_address+32'h00000290, read_data_again_64[31:0]);
    axi_read(axi_ethernet_0_address+32'h00000294, read_data_again_64[63:32]);

     if(read_data_again_64 != read_data_64) begin
      $error("No new frames expected");
     end

    // Read TX Good Frames counter pg051
    axi_read(axi_ethernet_0_address+32'h000002D8, read_data_64[31:0]);
    axi_read(axi_ethernet_0_address+32'h000002DC, read_data_64[63:32]);

    // Read TX Good Frames counter pg051
//    axi_read(tri_mode_ethernet_mac_2_address+32'h000002d8, read_data_64[31:0]);
//    axi_read(tri_mode_ethernet_mac_2_address+32'h000002dc, read_data_64[63:32]);


    $finish;

end

assign sfp_port_0_rxn = sfp_port_1_txn;
assign sfp_port_0_rxp = sfp_port_1_txp;
assign sfp_port_1_rxn = sfp_port_0_txn;
assign sfp_port_1_rxp = sfp_port_0_txp;

endmodule
