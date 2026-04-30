`default_nettype none
`timescale 1ns/1ps

// =============================================================================
// instruction_mem.v
// DFF RAM for GF180MCU / Tiny Tapeout
// DEPTH = 64 (256 bytes)
// =============================================================================

module instruction_mem #(
    parameter integer DEPTH  = 64,      // Fixed as per your request
    parameter integer ADDR_W = 6
)(
    input  wire              clk,
    input  wire              reset,

    // Write port - Used by UART Bootloader
    input  wire              we,                    // Write Enable
    input  wire [ADDR_W-1:0] addr,
    input  wire [31:0]       wdata,

    // Read port - Used by CPU for fetching instructions
    input  wire [ADDR_W-1:0] read_word_idx,
    output wire [31:0]       Instruction_out
);

    // DFF-based RAM (Efficient array of flip-flops)
    reg [31:0] mem [0:DEPTH-1];

    // =========================================================
    // Write Logic (for Bootloader)
    // =========================================================
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata;
        end
    end

    // =========================================================
    // Async Read Logic (Instruction Fetch)
    // =========================================================
    assign Instruction_out = mem[read_word_idx];

endmodule












