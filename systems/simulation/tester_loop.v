`timescale 1ns/1ps

//        +-------+       +-------+
//        |  tg0  |       |  tg1  |
//        +-------+       +-------+
//            V               V
//            |               |
//     +------------------------------+
//     |         packet_mux           |
//     +------------------------------+
//                   V
//                   |
//     +-----------------------------+
//     |           filter            |
//     +-----------------------------+
//                   V
//                   |
//                   +
//                  / \
//                 /   \
//                /     \
//         +-------+    +-------+
//         |  ta0  |    |  ta1  |
//         +-------+    +-------+


module tester_loop       #(
           parameter C_S_AXI_DATA_WIDTH    = 32,
           parameter C_S_AXI_ADDR_WIDTH    = 32,
           parameter C_CLK_TO_NS_RATIO    = 8

       )
(
    input clk,
    input resetn,
    input pps,
    input pps2,

    output reg [47:0] sec,
    output reg [29:0] nsec,

    // Slave AXI Ports
    input                                     S_AXI_ACLK,
    input                                     S_AXI_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_AWADDR,
    input                                     S_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_WSTRB,
    input                                     S_AXI_WVALID,
    input                                     S_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_ARADDR,
    input                                     S_AXI_ARVALID,
    input                                     S_AXI_RREADY,
    output                                    S_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_RDATA,
    output     [1 : 0]                        S_AXI_RRESP,
    output                                    S_AXI_RVALID,
    output                                    S_AXI_WREADY,
    output     [1 :0]                         S_AXI_BRESP,
    output                                    S_AXI_BVALID,
    output                                    S_AXI_AWREADY,

    // Slave AXI Ports TG
    input                                     S_AXI_TG0_ACLK,
    input                                     S_AXI_TG0_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TG0_AWADDR,
    input                                     S_AXI_TG0_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TG0_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_TG0_WSTRB,
    input                                     S_AXI_TG0_WVALID,
    input                                     S_AXI_TG0_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TG0_ARADDR,
    input                                     S_AXI_TG0_ARVALID,
    input                                     S_AXI_TG0_RREADY,
    output                                    S_AXI_TG0_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TG0_RDATA,
    output     [1 : 0]                        S_AXI_TG0_RRESP,
    output                                    S_AXI_TG0_RVALID,
    output                                    S_AXI_TG0_WREADY,
    output     [1 :0]                         S_AXI_TG0_BRESP,
    output                                    S_AXI_TG0_BVALID,
    output                                    S_AXI_TG0_AWREADY,

    input                                     S_AXI_TG1_ACLK,
    input                                     S_AXI_TG1_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TG1_AWADDR,
    input                                     S_AXI_TG1_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TG1_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_TG1_WSTRB,
    input                                     S_AXI_TG1_WVALID,
    input                                     S_AXI_TG1_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TG1_ARADDR,
    input                                     S_AXI_TG1_ARVALID,
    input                                     S_AXI_TG1_RREADY,
    output                                    S_AXI_TG1_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TG1_RDATA,
    output     [1 : 0]                        S_AXI_TG1_RRESP,
    output                                    S_AXI_TG1_RVALID,
    output                                    S_AXI_TG1_WREADY,
    output     [1 :0]                         S_AXI_TG1_BRESP,
    output                                    S_AXI_TG1_BVALID,
    output                                    S_AXI_TG1_AWREADY,


    // Slave AXI Ports TA
    input                                     S_AXI_TA0_ACLK,
    input                                     S_AXI_TA0_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TA0_AWADDR,
    input                                     S_AXI_TA0_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TA0_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_TA0_WSTRB,
    input                                     S_AXI_TA0_WVALID,
    input                                     S_AXI_TA0_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TA0_ARADDR,
    input                                     S_AXI_TA0_ARVALID,
    input                                     S_AXI_TA0_RREADY,
    output                                    S_AXI_TA0_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TA0_RDATA,
    output     [1 : 0]                        S_AXI_TA0_RRESP,
    output                                    S_AXI_TA0_RVALID,
    output                                    S_AXI_TA0_WREADY,
    output     [1 :0]                         S_AXI_TA0_BRESP,
    output                                    S_AXI_TA0_BVALID,
    output                                    S_AXI_TA0_AWREADY,

    input                                     S_AXI_TA1_ACLK,
    input                                     S_AXI_TA1_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TA1_AWADDR,
    input                                     S_AXI_TA1_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TA1_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_TA1_WSTRB,
    input                                     S_AXI_TA1_WVALID,
    input                                     S_AXI_TA1_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_TA1_ARADDR,
    input                                     S_AXI_TA1_ARVALID,
    input                                     S_AXI_TA1_RREADY,
    output                                    S_AXI_TA1_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_TA1_RDATA,
    output     [1 : 0]                        S_AXI_TA1_RRESP,
    output                                    S_AXI_TA1_RVALID,
    output                                    S_AXI_TA1_WREADY,
    output     [1 :0]                         S_AXI_TA1_BRESP,
    output                                    S_AXI_TA1_BVALID,
    output                                    S_AXI_TA1_AWREADY,

    // Slave AXI Ports TF
    input                                     S_AXI_FT_ACLK,
    input                                     S_AXI_FT_ARESETN,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_FT_AWADDR,
    input                                     S_AXI_FT_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_FT_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_FT_WSTRB,
    input                                     S_AXI_FT_WVALID,
    input                                     S_AXI_FT_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_FT_ARADDR,
    input                                     S_AXI_FT_ARVALID,
    input                                     S_AXI_FT_RREADY,
    output                                    S_AXI_FT_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_FT_RDATA,
    output     [1 : 0]                        S_AXI_FT_RRESP,
    output                                    S_AXI_FT_RVALID,
    output                                    S_AXI_FT_WREADY,
    output     [1 :0]                         S_AXI_FT_BRESP,
    output                                    S_AXI_FT_BVALID,
    output                                    S_AXI_FT_AWREADY

);



localparam CLK_PERIOD_NS=8;

localparam AXI_CLK_PERIOD_NS=10;
localparam RC_BASEADDR = 32'h00000000;
localparam TG0_BASEADDR = 32'h10000000;
localparam TG1_BASEADDR = 32'h11000000;
localparam TA0_BASEADDR = 32'h20000000;
localparam TA1_BASEADDR = 32'h21000000;
localparam FT_BASEADDR = 32'h30000000;


wire clk_;
wire resetn_;
wire [47:0] sec_;
wire [29:0] nsec_;
time       cur_time;

wire [8 - 1:0] gmii_d_ta;
wire gmii_en_ta;
wire gmii_er_ta;

wire [8 - 1:0] gmii_d_ta1;
wire gmii_en_ta1;
wire gmii_er_ta1;

wire [8 - 1:0] gmii_d_tg;
wire gmii_en_tg;
wire gmii_er_tg;

wire [8 - 1:0] gmii_d_tg1;
wire gmii_en_tg1;
wire gmii_er_tg1;

wire [8 - 1:0] gmii_d_ft;
wire gmii_en_ft;
wire gmii_er_ft;

wire [8 - 1:0] gmii_d_pm;
wire gmii_en_pm;
wire gmii_er_pm;


reg [31:0] data;
reg [63:0] data64;
reg [7:0] frame [0:1530];
integer i;
integer len;

assign sec = sec_;
assign nsec = nsec_;
assign clk_ = clk;
assign resetn_ = resetn;

rtclock #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(RC_BASEADDR),
           .C_CLK_TO_NS_RATIO(CLK_PERIOD_NS)
         ) rtclock0 (
                           .clk(clk_),
                           .resetn(resetn_),
                           .sec(sec_),
                           .nsec(nsec_),
                           .pps(pps),
                           .pps2(pps2),

                           // AXI Lite ports
                           .S_AXI_ACLK(S_AXI_ACLK),
                           .S_AXI_ARESETN(S_AXI_ARESETN),
                           .S_AXI_AWADDR(S_AXI_AWADDR),
                           .S_AXI_AWVALID(S_AXI_AWVALID),
                           .S_AXI_WDATA(S_AXI_WDATA),
                           .S_AXI_WSTRB(S_AXI_WSTRB),
                           .S_AXI_WVALID(S_AXI_WVALID),
                           .S_AXI_BREADY(S_AXI_BREADY),
                           .S_AXI_ARADDR(S_AXI_ARADDR),
                           .S_AXI_ARVALID(S_AXI_ARVALID),
                           .S_AXI_RREADY(S_AXI_RREADY),
                           .S_AXI_ARREADY(S_AXI_ARREADY),
                           .S_AXI_RDATA(S_AXI_RDATA),
                           .S_AXI_RRESP(S_AXI_RRESP),
                           .S_AXI_RVALID(S_AXI_RVALID),
                           .S_AXI_WREADY(S_AXI_WREADY),
                           .S_AXI_BRESP(S_AXI_BRESP),
                           .S_AXI_BVALID(S_AXI_BVALID),
                           .S_AXI_AWREADY(S_AXI_AWREADY)


);

traffic_generator_gmii #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(TG0_BASEADDR)
                       ) traffic_generator_gmii0
                       (
                           .clk(clk),
                           .resetn(resetn_),

                           .gmii_d(gmii_d_tg),
                           .gmii_en(gmii_en_tg),
                           .gmii_er(gmii_er_tg),

                           .sec(sec_),
                           .nsec(nsec_),


                           // AXI Lite ports
                           .S_AXI_ACLK(S_AXI_TG0_ACLK),
                           .S_AXI_ARESETN(S_AXI_TG0_ARESETN),
                           .S_AXI_AWADDR(S_AXI_TG0_AWADDR),
                           .S_AXI_AWVALID(S_AXI_TG0_AWVALID),
                           .S_AXI_WDATA(S_AXI_TG0_WDATA),
                           .S_AXI_WSTRB(S_AXI_TG0_WSTRB),
                           .S_AXI_WVALID(S_AXI_TG0_WVALID),
                           .S_AXI_BREADY(S_AXI_TG0_BREADY),
                           .S_AXI_ARADDR(S_AXI_TG0_ARADDR),
                           .S_AXI_ARVALID(S_AXI_TG0_ARVALID),
                           .S_AXI_RREADY(S_AXI_TG0_RREADY),
                           .S_AXI_ARREADY(S_AXI_TG0_ARREADY),
                           .S_AXI_RDATA(S_AXI_TG0_RDATA),
                           .S_AXI_RRESP(S_AXI_TG0_RRESP),
                           .S_AXI_RVALID(S_AXI_TG0_RVALID),
                           .S_AXI_WREADY(S_AXI_TG0_WREADY),
                           .S_AXI_BRESP(S_AXI_TG0_BRESP),
                           .S_AXI_BVALID(S_AXI_TG0_BVALID),
                           .S_AXI_AWREADY(S_AXI_TG0_AWREADY)


                       );

traffic_generator_gmii #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(TG1_BASEADDR)
                       ) traffic_generator_gmii1
                       (
                           .clk(clk),
                           .resetn(resetn_),

                           .gmii_d(gmii_d_tg1),
                           .gmii_en(gmii_en_tg1),
                           .gmii_er(gmii_er_tg1),

                           .sec(sec_),
                           .nsec(nsec_),


                           // AXI Lite ports
                           .S_AXI_ACLK(S_AXI_TG1_ACLK),
                           .S_AXI_ARESETN(S_AXI_TG1_ARESETN),
                           .S_AXI_AWADDR(S_AXI_TG1_AWADDR),
                           .S_AXI_AWVALID(S_AXI_TG1_AWVALID),
                           .S_AXI_WDATA(S_AXI_TG1_WDATA),
                           .S_AXI_WSTRB(S_AXI_TG1_WSTRB),
                           .S_AXI_WVALID(S_AXI_TG1_WVALID),
                           .S_AXI_BREADY(S_AXI_TG1_BREADY),
                           .S_AXI_ARADDR(S_AXI_TG1_ARADDR),
                           .S_AXI_ARVALID(S_AXI_TG1_ARVALID),
                           .S_AXI_RREADY(S_AXI_TG1_RREADY),
                           .S_AXI_ARREADY(S_AXI_TG1_ARREADY),
                           .S_AXI_RDATA(S_AXI_TG1_RDATA),
                           .S_AXI_RRESP(S_AXI_TG1_RRESP),
                           .S_AXI_RVALID(S_AXI_TG1_RVALID),
                           .S_AXI_WREADY(S_AXI_TG1_WREADY),
                           .S_AXI_BRESP(S_AXI_TG1_BRESP),
                           .S_AXI_BVALID(S_AXI_TG1_BVALID),
                           .S_AXI_AWREADY(S_AXI_TG1_AWREADY)


                       );

traffic_analyzer_gmii #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(TA0_BASEADDR)
                      ) traffic_analyzer_gmii0
                      (
                          .clk(clk_),
                          .resetn(resetn_),

                          .gmii_d(gmii_d_ft),
                          .gmii_en(gmii_en_ft),
                          .gmii_er(gmii_er_ft),

                          .sec(sec_),
                          .nsec(nsec_),

                          // AXI Lite ports
                          .S_AXI_ACLK(S_AXI_TA0_ACLK),
                          .S_AXI_ARESETN(S_AXI_TA0_ARESETN),
                          .S_AXI_AWADDR(S_AXI_TA0_AWADDR),
                          .S_AXI_AWVALID(S_AXI_TA0_AWVALID),
                          .S_AXI_WDATA(S_AXI_TA0_WDATA),
                          .S_AXI_WSTRB(S_AXI_TA0_WSTRB),
                          .S_AXI_WVALID(S_AXI_TA0_WVALID),
                          .S_AXI_BREADY(S_AXI_TA0_BREADY),
                          .S_AXI_ARADDR(S_AXI_TA0_ARADDR),
                          .S_AXI_ARVALID(S_AXI_TA0_ARVALID),
                          .S_AXI_RREADY(S_AXI_TA0_RREADY),
                          .S_AXI_ARREADY(S_AXI_TA0_ARREADY),
                          .S_AXI_RDATA(S_AXI_TA0_RDATA),
                          .S_AXI_RRESP(S_AXI_TA0_RRESP),
                          .S_AXI_RVALID(S_AXI_TA0_RVALID),
                          .S_AXI_WREADY(S_AXI_TA0_WREADY),
                          .S_AXI_BRESP(S_AXI_TA0_BRESP),
                          .S_AXI_BVALID(S_AXI_TA0_BVALID),
                          .S_AXI_AWREADY(S_AXI_TA0_AWREADY)
                      );
traffic_analyzer_gmii #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(TA1_BASEADDR)
                      ) traffic_analyzer_gmii1
                      (
                          .clk(clk_),
                          .resetn(resetn_),

                          .gmii_d(gmii_d_ft),
                          .gmii_en(gmii_en_ft),
                          .gmii_er(gmii_er_ft),

                          .sec(sec_),
                          .nsec(nsec_),

                          // AXI Lite ports
                          .S_AXI_ACLK(S_AXI_TA1_ACLK),
                          .S_AXI_ARESETN(S_AXI_TA1_ARESETN),
                          .S_AXI_AWADDR(S_AXI_TA1_AWADDR),
                          .S_AXI_AWVALID(S_AXI_TA1_AWVALID),
                          .S_AXI_WDATA(S_AXI_TA1_WDATA),
                          .S_AXI_WSTRB(S_AXI_TA1_WSTRB),
                          .S_AXI_WVALID(S_AXI_TA1_WVALID),
                          .S_AXI_BREADY(S_AXI_TA1_BREADY),
                          .S_AXI_ARADDR(S_AXI_TA1_ARADDR),
                          .S_AXI_ARVALID(S_AXI_TA1_ARVALID),
                          .S_AXI_RREADY(S_AXI_TA1_RREADY),
                          .S_AXI_ARREADY(S_AXI_TA1_ARREADY),
                          .S_AXI_RDATA(S_AXI_TA1_RDATA),
                          .S_AXI_RRESP(S_AXI_TA1_RRESP),
                          .S_AXI_RVALID(S_AXI_TA1_RVALID),
                          .S_AXI_WREADY(S_AXI_TA1_WREADY),
                          .S_AXI_BRESP(S_AXI_TA1_BRESP),
                          .S_AXI_BVALID(S_AXI_TA1_BVALID),
                          .S_AXI_AWREADY(S_AXI_TA1_AWREADY)
                      );

filter_gmii #(
           .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
           .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
           .C_BASEADDR(FT_BASEADDR)
                      ) dut0
                      (
                          .clk(clk_),

                          .gmii_d_in(gmii_d_pm),
                          .gmii_en_in(gmii_en_pm),
                          .gmii_er_in(gmii_er_pm),

                          .gmii_d_out(gmii_d_ft),
                          .gmii_en_out(gmii_en_ft),
                          .gmii_er_out(gmii_er_ft),

                          // AXI Lite ports
                          .S_AXI_ACLK(S_AXI_FT_ACLK),
                          .S_AXI_ARESETN(S_AXI_FT_ARESETN),
                          .S_AXI_AWADDR(S_AXI_FT_AWADDR),
                          .S_AXI_AWVALID(S_AXI_FT_AWVALID),
                          .S_AXI_WDATA(S_AXI_FT_WDATA),
                          .S_AXI_WSTRB(S_AXI_FT_WSTRB),
                          .S_AXI_WVALID(S_AXI_FT_WVALID),
                          .S_AXI_BREADY(S_AXI_FT_BREADY),
                          .S_AXI_ARADDR(S_AXI_FT_ARADDR),
                          .S_AXI_ARVALID(S_AXI_FT_ARVALID),
                          .S_AXI_RREADY(S_AXI_FT_RREADY),
                          .S_AXI_ARREADY(S_AXI_FT_ARREADY),
                          .S_AXI_RDATA(S_AXI_FT_RDATA),
                          .S_AXI_RRESP(S_AXI_FT_RRESP),
                          .S_AXI_RVALID(S_AXI_FT_RVALID),
                          .S_AXI_WREADY(S_AXI_FT_WREADY),
                          .S_AXI_BRESP(S_AXI_FT_BRESP),
                          .S_AXI_BVALID(S_AXI_FT_BVALID),
                          .S_AXI_AWREADY(S_AXI_FT_AWREADY)
                      );

packet_mux_gmii  packet_mux_gmii0
                      (
                          .clk(clk_),

                          .gmii_d_in0(gmii_d_tg),
                          .gmii_en_in0(gmii_en_tg),
                          .gmii_er_in0(gmii_er_tg),

                          .gmii_d_in1(gmii_d_tg1),
                          .gmii_en_in1(gmii_en_tg1),
                          .gmii_er_in1(gmii_er_tg1),

                          .gmii_d_out(gmii_d_pm),
                          .gmii_en_out(gmii_en_pm),
                          .gmii_er_out(gmii_er_pm)
                      );

endmodule
