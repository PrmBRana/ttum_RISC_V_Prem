`default_nettype none

module Reg_file (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire        Regwrite,
    input  wire [31:0] Write_data,
    output wire [31:0] Read_data1,
    output wire [31:0] Read_data2
);

    reg [31:0] rf [0:31];

    // Write (x0 is hardwired, never written)
    always @(posedge clk) begin
        if (Regwrite && rd_addr != 5'd0)
            rf[rd_addr] <= Write_data;
    end

    // Read with write-forwarding
    assign Read_data1 = (rs1_addr == 5'd0) ? 32'd0 :
                        (Regwrite && rd_addr == rs1_addr && rd_addr != 5'd0) ? Write_data :
                        rf[rs1_addr];

    assign Read_data2 = (rs2_addr == 5'd0) ? 32'd0 :
                        (Regwrite && rd_addr == rs2_addr && rd_addr != 5'd0) ? Write_data :
                        rf[rs2_addr];

endmodule

`default_nettype wire



