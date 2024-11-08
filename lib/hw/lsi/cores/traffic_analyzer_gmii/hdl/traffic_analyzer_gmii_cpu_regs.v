`include "traffic_analyzer_gmii_cpu_regs_defines.v"
module traffic_analyzer_gmii_cpu_regs #
       (
           parameter C_S_AXI_DATA_WIDTH    = 32,
           parameter C_S_AXI_ADDR_WIDTH    = 12,
           parameter C_BASE_ADDRESS        = 32'h00000000,
           parameter C_FRAME_BUF_ADDRESS_WIDTH   = 9
       )
       (
           // General ports
           input       clk,
           input       resetn,
           // Global Registers
           output reg  resetn_sync,

           // AXI Lite ports
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

           // Register ports
           input      [`REG_ID_BITS]    id_reg,
           input      [`REG_VERSION_BITS]    version_reg,
           input      [`REG_FLIP_BITS]    ip2cpu_flip_reg,
           output reg [`REG_FLIP_BITS]    cpu2ip_flip_reg,
           output reg [`REG_CONTROL_BITS]    control_reg,
           output reg [10*4*8-1:0] testframe_filter_data_regs, //40 octet bitmask match filter
           output reg [10*4*8-1:0] testframe_filter_mask_regs,
           input      [`REG_PKTS_BITS]       pkts_reg,
           input      [`REG_OCTETS_BITS]     octets_reg,
           input      [`REG_BAD_CRC_PKTS_BITS]       bad_crc_pkts_reg,
           input      [`REG_BAD_CRC_OCTETS_BITS]     bad_crc_octets_reg,
           input      [`REG_BAD_PREAMBLE_PKTS_BITS]       bad_preamble_pkts_reg,
           input      [`REG_BAD_PREAMBLE_OCTETS_BITS]     bad_preamble_octets_reg,
           input      [`REG_OCTETS_IDLE_BITS] octets_idle_reg,
           input      [`REG_OCTETS_TOTAL_BITS] octets_total_reg,
           input      [`REG_TIMESTAMP_SEC_BITS]	timestamp_sec_reg,
           input      [`REG_TIMESTAMP_NSEC_BITS] timestamp_nsec_reg,
           input      [`REG_FRAME_SIZE_BITS] frame_size_reg,
           input      [`REG_FRAME_BUF_BITS]  frame_buf_data,
           output reg [C_FRAME_BUF_ADDRESS_WIDTH-1 : 0]      frame_buf_address,

           input      [`REG_TESTFRAME_PKTS_BITS] testframe_pkts_reg,
           input      [`REG_SEQUENCE_ERRORS_BITS] sequence_errors_reg,
           input      [`REG_LATENCY_MIN_SEC_BITS]	latency_min_sec_reg,
           input      [`REG_LATENCY_MIN_NSEC_BITS]	latency_min_nsec_reg,
           input      [`REG_LATENCY_MAX_SEC_BITS]	latency_max_sec_reg,
           input      [`REG_LATENCY_MAX_NSEC_BITS]	latency_max_nsec_reg,
           input      [`REG_LATENCY_SEC_BITS]	latency_sec_reg,
           input      [`REG_LATENCY_NSEC_BITS]	latency_nsec_reg,
           input      [`REG_LAST_SEQUENCE_ERROR_RECEIVED_BITS]	last_sequence_error_received_reg,
           input      [`REG_LAST_SEQUENCE_ERROR_EXPECTED_BITS]	last_sequence_error_expected_reg,
           input      [`REG_LAST_SEQUENCE_ERROR_TIMESTAMP_SEC_BITS]	last_sequence_error_timestamp_sec_reg,
           input      [`REG_LAST_SEQUENCE_ERROR_TIMESTAMP_NSEC_BITS]	last_sequence_error_timestamp_nsec_reg

       );

integer i;

// AXI4LITE signals
reg [C_S_AXI_ADDR_WIDTH-1 : 0]      axi_awaddr;
reg                                 axi_awready;
reg                                 axi_wready;
reg [1 : 0]                         axi_bresp;
reg                                 axi_bvalid;
reg [C_S_AXI_ADDR_WIDTH-1 : 0]      axi_araddr;
reg                                 axi_arready;
reg [C_S_AXI_DATA_WIDTH-1 : 0]      axi_rdata;
reg [1 : 0]                         axi_rresp;
reg                                 axi_rvalid;

reg                                 resetn_sync_d;
wire                                reg_rden;
wire                                reg_wren;
reg [C_S_AXI_DATA_WIDTH-1:0]        reg_data_out;
integer                             byte_index;
reg next_buf_index_inc;
reg [31:0] next_buf_data;


// I/O Connections assignments
assign S_AXI_AWREADY    = axi_awready;
assign S_AXI_WREADY     = axi_wready;
assign S_AXI_BRESP      = axi_bresp;
assign S_AXI_BVALID     = axi_bvalid;
assign S_AXI_ARREADY    = axi_arready;
assign S_AXI_RDATA      = axi_rdata;
assign S_AXI_RRESP      = axi_rresp;
assign S_AXI_RVALID     = axi_rvalid;

//Sample reset
always @ (posedge clk) begin
    if (~resetn) begin
        resetn_sync_d  <=  1'b0;
        resetn_sync    <=  1'b0;
    end
    else begin
        resetn_sync_d  <=  resetn;
        resetn_sync    <=  resetn_sync_d;
    end
end


// Implement axi_awready generation

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_awready <= 1'b0;
    end
    else begin
        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            // slave is ready to accept write address when
            // there is a valid write address and write data
            // on the write address and data bus. This design
            // expects no outstanding transactions.
            axi_awready <= 1'b1;
        end
        else begin
            axi_awready <= 1'b0;
        end
    end
end

// Implement axi_awaddr latching

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_awaddr <= 0;
    end
    else begin
        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            // Write Address latching
            axi_awaddr <= S_AXI_AWADDR ^ C_BASE_ADDRESS;
        end
    end
end

// Implement axi_wready generation

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_wready <= 1'b0;
    end
    else begin
        if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID) begin
            // slave is ready to accept write data when
            // there is a valid write address and write data
            // on the write address and data bus. This design
            // expects no outstanding transactions.
            axi_wready <= 1'b1;
        end
        else begin
            axi_wready <= 1'b0;
        end
    end
end

// Implement write response logic generation

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_bvalid  <= 0;
        axi_bresp   <= 2'b0;
    end
    else begin
        if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
            // indicates a valid write response is available
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b0; // OKAY response
        end                   // work error responses in future
        else begin
            if (S_AXI_BREADY && axi_bvalid)
                //check if bready is asserted while bvalid is high)
                //(there is a possibility that bready is always asserted high)
            begin
                axi_bvalid <= 1'b0;
            end
        end
    end
end

// Implement axi_arready generation

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_arready <= 1'b0;
        axi_araddr  <= 32'b0;
    end
    else begin
        if (~axi_arready && S_AXI_ARVALID) begin
            // indicates that the slave has acceped the valid read address
            // Read address latching
            axi_arready <= 1'b1;
            axi_araddr  <= S_AXI_ARADDR ^ C_BASE_ADDRESS;
        end
        else begin
            axi_arready <= 1'b0;
        end
    end
end


// Implement axi_rvalid generation

always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_rvalid <= 0;
        axi_rresp  <= 0;
    end
    else begin
        if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            // Valid read data is available at the read data bus
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b0; // OKAY response
        end
        else if (axi_rvalid && S_AXI_RREADY) begin
            // Read data is accepted by the master
            axi_rvalid <= 1'b0;
        end
    end
end

// Implement frame_buf address increment
always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        frame_buf_address  <= 0;
        next_buf_index_inc <= 0;
    end
    else begin
        if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            if(axi_araddr == `REG_FRAME_SIZE_ADDR) begin
                frame_buf_address <= 0;
                next_buf_index_inc <= 0;
            end
            else if(axi_araddr == `REG_FRAME_BUF_ADDR) begin
                next_buf_index_inc <= 1;
            end
        end
        else if (axi_rvalid && S_AXI_RREADY) begin
            if(next_buf_index_inc) begin
                frame_buf_address  <= frame_buf_address + 1;
                next_buf_index_inc <= 0;
            end
        end
    end
end


// Implement memory mapped register select and write logic generation

assign reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

//////////////////////////////////////////////////////////////
// write registers
//////////////////////////////////////////////////////////////


//R/W register, not cleared
always @(posedge S_AXI_ACLK) begin
    if (!resetn) begin

        cpu2ip_flip_reg <= #1 `REG_FLIP_DEFAULT;
        control_reg <= #1 1;
    end
    else begin
        if (reg_wren && S_AXI_WSTRB==4'hF) //write event
        case (axi_awaddr)
            //Flip Register
            `REG_FLIP_ADDR : begin
                for ( byte_index = 0; byte_index <= (`REG_FLIP_WIDTH/8-1); byte_index = byte_index +1)
                    if (S_AXI_WSTRB[byte_index] == 1) begin
                        cpu2ip_flip_reg[byte_index*8 +: 8] <=  S_AXI_WDATA[byte_index*8 +: 8]; //dynamic register;
                    end
            end
            //Control Register
            `REG_CONTROL_ADDR : begin
                control_reg[`REG_CONTROL_WIDTH-1:0] <=  S_AXI_WDATA[`REG_CONTROL_WIDTH-1:0];
            end
        endcase

        //Testframe Filter Registers
        for(i=0;i<10;i=i+1) begin
            if(axi_awaddr == `REG_CONTROL_ADDR+4+i*4) begin
                testframe_filter_data_regs[(0*8*4+ 0+7):(0*8*4+0)] <=  S_AXI_WDATA[0*8+7:0*8];
                //testframe_filter_data_regs[i*8*4+ 8+7:i*8*4+8 ] <= S_AXI_WDATA[1*8+7:1*8];
                //testframe_filter_data_regs[i*8*4+16+7:i*8*4+16] <= S_AXI_WDATA[2*8+7:2*8];
                //testframe_filter_data_regs[i*8*4+24+7:i*8*4+24] <= S_AXI_WDATA[3*8+7:3*8];
            end
        end
    end
end



/////////////////////////
//// end of write
/////////////////////////

// Implement memory mapped register select and read logic generation
// Slave register read enable is asserted when valid address is available
// and the slave is ready to accept the read address.

// reg_rden control logic
// temperary no extra logic here
assign reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;


always @(*) begin

    case ( axi_araddr /*S_AXI_ARADDR ^ C_BASE_ADDRESS*/)
        //Id Register
        `REG_ID_ADDR : begin
            reg_data_out [`REG_ID_BITS] =  id_reg;
        end
        //Version Register
        `REG_VERSION_ADDR : begin
            reg_data_out [`REG_VERSION_BITS] =  version_reg;
        end
        //Flip Register
        `REG_FLIP_ADDR : begin
            reg_data_out [`REG_FLIP_BITS] =  ip2cpu_flip_reg;
        end
        //Counters
        `REG_PKTS_ADDR : begin
            reg_data_out [31:0] =  pkts_reg[63:32];
        end
        `REG_PKTS_ADDR+4 : begin
            reg_data_out [31:0] =  pkts_reg[31:0];
        end
        `REG_OCTETS_ADDR : begin
            reg_data_out [31:0] =  octets_reg[63:32];
        end
        `REG_OCTETS_ADDR+4 : begin
            reg_data_out [31:0] =  octets_reg[31:0];
        end
        `REG_BAD_CRC_PKTS_ADDR : begin
            reg_data_out [31:0] =  bad_crc_pkts_reg[63:32];
        end
        `REG_BAD_CRC_PKTS_ADDR+4 : begin
            reg_data_out [31:0] =  bad_crc_pkts_reg[31:0];
        end
        `REG_BAD_CRC_OCTETS_ADDR : begin
            reg_data_out [31:0] =  bad_crc_octets_reg[63:32];
        end
        `REG_BAD_CRC_OCTETS_ADDR+4 : begin
            reg_data_out [31:0] =  bad_crc_octets_reg[31:0];
        end
        `REG_BAD_PREAMBLE_PKTS_ADDR : begin
            reg_data_out [31:0] =  bad_preamble_pkts_reg[63:32];
        end
        `REG_BAD_PREAMBLE_PKTS_ADDR+4 : begin
            reg_data_out [31:0] =  bad_preamble_pkts_reg[31:0];
        end
        `REG_BAD_PREAMBLE_OCTETS_ADDR : begin
            reg_data_out [31:0] =  bad_preamble_octets_reg[63:32];
        end
        `REG_BAD_PREAMBLE_OCTETS_ADDR+4 : begin
            reg_data_out [31:0] =  bad_preamble_octets_reg[31:0];
        end
        `REG_OCTETS_IDLE_ADDR : begin
            reg_data_out [31:0] =  octets_idle_reg[63:32];
        end
        `REG_OCTETS_IDLE_ADDR+4 : begin
            reg_data_out [31:0] =  octets_idle_reg[31:0];
        end
        `REG_OCTETS_TOTAL_ADDR : begin
            reg_data_out [31:0] =  octets_total_reg[63:32];
        end
        `REG_OCTETS_TOTAL_ADDR+4 : begin
            reg_data_out [31:0] =  octets_total_reg[31:0];
        end
        `REG_TIMESTAMP_SEC_ADDR : begin
            reg_data_out [31:0] =  timestamp_sec_reg[63:32];
        end
        `REG_TIMESTAMP_SEC_ADDR+4 : begin
            reg_data_out [31:0] =  timestamp_sec_reg[31:0];
        end
        `REG_TIMESTAMP_NSEC_ADDR : begin
            reg_data_out [31:0] =  timestamp_nsec_reg[31:0];
        end
        `REG_FRAME_SIZE_ADDR : begin
            reg_data_out [31:0] =  frame_size_reg[31:0];
        end
        `REG_FRAME_BUF_ADDR : begin
            reg_data_out [31:0] =  frame_buf_data;
        end
        `REG_TESTFRAME_PKTS_ADDR : begin
            reg_data_out [31:0] =  testframe_pkts_reg[63:32];
        end
        `REG_TESTFRAME_PKTS_ADDR+4 : begin
            reg_data_out [31:0] =  testframe_pkts_reg[31:0];
        end
        `REG_SEQUENCE_ERRORS_ADDR : begin
            reg_data_out [31:0] =  sequence_errors_reg[63:32];
        end
        `REG_SEQUENCE_ERRORS_ADDR+4 : begin
            reg_data_out [31:0] =  sequence_errors_reg[31:0];
        end
        `REG_LATENCY_MIN_SEC_ADDR : begin
            reg_data_out [31:0] =  latency_min_sec_reg[63:32];
        end
        `REG_LATENCY_MIN_SEC_ADDR+4 : begin
            reg_data_out [31:0] =  latency_min_sec_reg[31:0];
        end
        `REG_LATENCY_MIN_NSEC_ADDR : begin
            reg_data_out [31:0] =  latency_min_nsec_reg[31:0];
        end
        `REG_LATENCY_MAX_SEC_ADDR : begin
            reg_data_out [31:0] =  latency_max_sec_reg[63:32];
        end
        `REG_LATENCY_MAX_SEC_ADDR+4 : begin
            reg_data_out [31:0] =  latency_max_sec_reg[31:0];
        end
        `REG_LATENCY_MAX_NSEC_ADDR : begin
            reg_data_out [31:0] =  latency_max_nsec_reg[31:0];
        end
        `REG_LATENCY_SEC_ADDR : begin
            reg_data_out [31:0] =  latency_sec_reg[63:32];
        end
        `REG_LATENCY_SEC_ADDR+4 : begin
            reg_data_out [31:0] =  latency_sec_reg[31:0];
        end
        `REG_LATENCY_NSEC_ADDR : begin
            reg_data_out [31:0] =  latency_nsec_reg[31:0];
        end
        `REG_LAST_SEQUENCE_ERROR_RECEIVED_ADDR : begin
            reg_data_out [31:0] =  last_sequence_error_received_reg[63:32];
        end
        `REG_LAST_SEQUENCE_ERROR_RECEIVED_ADDR+4 : begin
            reg_data_out [31:0] =  last_sequence_error_received_reg[31:0];
        end
        `REG_LAST_SEQUENCE_ERROR_EXPECTED_ADDR : begin
            reg_data_out [31:0] =  last_sequence_error_expected_reg[63:32];
        end
        `REG_LAST_SEQUENCE_ERROR_EXPECTED_ADDR+4 : begin
            reg_data_out [31:0] =  last_sequence_error_expected_reg[31:0];
        end
        `REG_LAST_SEQUENCE_ERROR_TIMESTAMP_SEC_ADDR : begin
            reg_data_out [31:0] =  last_sequence_error_timestamp_sec_reg[63:32];
        end
        `REG_LAST_SEQUENCE_ERROR_TIMESTAMP_SEC_ADDR+4 : begin
            reg_data_out [31:0] =  last_sequence_error_timestamp_sec_reg[31:0];
        end
        `REG_LAST_SEQUENCE_ERROR_TIMESTAMP_NSEC_ADDR : begin
            reg_data_out [31:0] =  last_sequence_error_timestamp_nsec_reg[31:0];
        end

 
        //Default return value
        default: begin
            reg_data_out [31:0] =  32'hDEADBEEF;
        //   reg_data_out [31:0] =  32'hZZZZZZZZ;
        end

    endcase

end//end of assigning data to IP2Bus_Data bus

//Read only registers, not cleared
//Nothing to do here....

//Read only registers, cleared on read (e.g. counters)
//Nothing to do here....


// Output register or memory read data
always @( posedge S_AXI_ACLK ) begin
    if ( S_AXI_ARESETN == 1'b0 ) begin
        axi_rdata  <= 0;
    end
    else begin
        // When there is a valid read address (S_AXI_ARVALID) with
        // acceptance of read address by the slave (axi_arready),
        // output the read dada
        if (reg_rden) begin
            axi_rdata <= reg_data_out/*ip2bus_data*/;     // register read data /* some new changes here */
        end
    end
end
endmodule
