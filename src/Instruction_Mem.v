`default_nettype none

module instruction_mem #(
    parameter DEPTH  = 64,
    parameter ADDR_W = 6
)(
    input  wire              clk,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,
    input  wire [31:0]       wdata,

    input  wire [31:0]       read_Address,
    output wire [31:0]       Instruction_out
);

    localparam [31:0] NOP = 32'h00000013;

    reg [31:0] mem [0:DEPTH-1];

    wire [ADDR_W-1:0] word_idx;

    assign word_idx = read_Address[ADDR_W+1:2];

    // synchronous write
    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    // asynchronous read
    assign Instruction_out =
        (word_idx < DEPTH) ? mem[word_idx] : NOP;


endmodule

`default_nettype wire

