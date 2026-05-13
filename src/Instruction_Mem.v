`default_nettype none

// ============================================================
// instruction_mem — RISC-V Instruction Memory
// 
// FIXES:
// 1. Mask write address to ADDR_W bits (prevent out-of-bounds)
// 2. Mask read address to safe range (consistent write/read)
// 3. Handle addr port width safely despite 8-bit interface
// ============================================================

module instruction_mem #(
    parameter DEPTH  = 64,
    parameter ADDR_W = 6
)(
    input  wire              clk,
    input  wire              we,
    input  wire [7:0]        addr,         // 8-bit for bootloader compatibility
    input  wire [31:0]       wdata,

    input  wire [31:0]       read_Address, // 32-bit PC from CPU
    output wire [31:0]       Instruction_out
);

    localparam [31:0] NOP = 32'h00000013;

    reg [31:0] mem [0:DEPTH-1];

    // ========================================================
    // Write path: mask address to safe range [ADDR_W-1:0]
    // ========================================================
    wire [ADDR_W-1:0] write_addr = addr[ADDR_W-1:0];

    always @(posedge clk) begin
        if (we && (write_addr < DEPTH)) begin
            mem[write_addr] <= wdata;
        end
    end

    // ========================================================
    // Read path: extract word index from PC (instruction aligned)
    // PC[31:2] gives 30-bit word address
    // We take [ADDR_W+1:2] to cover 0 to DEPTH-1
    // ========================================================
    wire [ADDR_W-1:0] read_addr = read_Address[ADDR_W+1:2];

    // Asynchronous read with bounds checking
    assign Instruction_out =
        (read_addr < DEPTH) ? mem[read_addr] : NOP;

endmodule

`default_nettype wire


