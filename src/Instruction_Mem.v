`default_nettype none

module instruction_mem #(
    parameter integer DEPTH  = 64,
    parameter integer ADDR_W = 6
)(
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_W-1:0]     addr,
    input  wire [31:0]           wdata,

    input  wire [31:0]           read_Address,
    output wire [31:0]           Instruction_out
);

    localparam [31:0] NOP = 32'h00000013;

    // memory
    reg [31:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------
    // FIX 1: remove WIDTHEXPAND (safe word alignment)
    // ------------------------------------------------------------
    wire [31:0] addr_shifted;
    assign addr_shifted = read_Address >> 2;

    wire [ADDR_W-1:0] word_idx;
    assign word_idx = addr_shifted[ADDR_W-1:0];

    // ------------------------------------------------------------
    // synchronous write
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    // ------------------------------------------------------------
    // read
    // FIX 2: no width mismatch comparison
    // ------------------------------------------------------------
    assign Instruction_out =
        (addr_shifted < DEPTH) ? mem[word_idx] : NOP;

endmodule

`default_nettype wire


