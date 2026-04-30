`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// EX_stage.v — ID/EX pipeline register (ASIC optimized)
// GF180 / OpenROAD friendly
//
// CHANGE: Added funct3D_in / funct3D_out ports.
//   funct3 must travel with the instruction through the pipeline so that
//   the MEM stage can generate the correct byte_en for SB/SH/SW stores.
//   Without this, byte_en in DataMem had no source and all RAM stores failed.
// =============================================================================

module EX_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        flushE,

    input  wire [31:0] RD1D_in,
    input  wire [31:0] RD2D_in,
    input  wire [31:0] ImmExtD_in,
    input  wire [31:0] PCPlus4D_in,
    input  wire [31:0] PC_D_in,
    input  wire [4:0]  Rs1D_in,
    input  wire [4:0]  Rs2D_in,
    input  wire [4:0]  RdD_in,
    input  wire [3:0]  ALUControlD_in,
    input  wire        ALUSrcD_in,
    input  wire [1:0]  ALUSrcA_in,
    input  wire        RegWriteD_in,
    input  wire [1:0]  ResultSrcD_in,
    input  wire        MemWriteD_in,
    input  wire        BranchD_in,
    input  wire        JumpD_in,
    input  wire        JumpR_in,
    input  wire [1:0]  ALUType_in,
    input  wire [2:0]  funct3D_in,       // NEW: for byte_en in MEM stage

    output reg  [31:0] RD1E_out,
    output reg  [31:0] RD2E_out,
    output reg  [31:0] ImmExtD_out,
    output reg  [31:0] PCPlus4D_out,
    output reg  [31:0] PC_D_out,
    output reg  [4:0]  Rs1D_out,
    output reg  [4:0]  Rs2D_out,
    output reg  [4:0]  RdD_out,
    output reg  [3:0]  ALUControlD_out,
    output reg         ALUSrcD_out,
    output reg  [1:0]  ALUSrcA_out,
    output reg         RegWriteD_out,
    output reg  [1:0]  ResultSrcD_out,
    output reg         MemWriteD_out,
    output reg         BranchD_out,
    output reg         JumpD_out,
    output reg         JumpR_out,
    output reg  [1:0]  ALUType_out,
    output reg  [2:0]  funct3D_out       // NEW: for byte_en in MEM stage
);

    // =========================================================
    // Internal flush mux signals (ASIC-safe style)
    // =========================================================
    wire flush = reset | flushE;

    wire [31:0] RD1_next        = flush ? 32'd0 : RD1D_in;
    wire [31:0] RD2_next        = flush ? 32'd0 : RD2D_in;
    wire [31:0] ImmExt_next     = flush ? 32'd0 : ImmExtD_in;
    wire [31:0] PCPlus4_next    = flush ? 32'd0 : PCPlus4D_in;
    wire [31:0] PC_next         = flush ? 32'd0 : PC_D_in;

    wire [4:0]  Rs1_next        = flush ? 5'd0  : Rs1D_in;
    wire [4:0]  Rs2_next        = flush ? 5'd0  : Rs2D_in;
    wire [4:0]  Rd_next         = flush ? 5'd0  : RdD_in;

    wire [3:0]  ALUControl_next = flush ? 4'd0  : ALUControlD_in;
    wire        ALUSrc_next     = flush ? 1'b0  : ALUSrcD_in;
    wire [1:0]  ALUSrcA_next    = flush ? 2'd0  : ALUSrcA_in;

    wire        RegWrite_next   = flush ? 1'b0  : RegWriteD_in;
    wire [1:0]  ResultSrc_next  = flush ? 2'd0  : ResultSrcD_in;
    wire        MemWrite_next   = flush ? 1'b0  : MemWriteD_in;
    wire        Branch_next     = flush ? 1'b0  : BranchD_in;
    wire        Jump_next       = flush ? 1'b0  : JumpD_in;
    wire        JumpR_next      = flush ? 1'b0  : JumpR_in;
    wire [1:0]  ALUType_next    = flush ? 2'd0  : ALUType_in;
    wire [2:0]  funct3_next     = flush ? 3'd0  : funct3D_in;  // NEW

    // =========================================================
    // Pipeline registers
    // =========================================================
    always @(posedge clk) begin
        RD1E_out        <= RD1_next;
        RD2E_out        <= RD2_next;
        ImmExtD_out     <= ImmExt_next;
        PCPlus4D_out    <= PCPlus4_next;
        PC_D_out        <= PC_next;

        Rs1D_out        <= Rs1_next;
        Rs2D_out        <= Rs2_next;
        RdD_out         <= Rd_next;

        ALUControlD_out <= ALUControl_next;
        ALUSrcD_out     <= ALUSrc_next;
        ALUSrcA_out     <= ALUSrcA_next;

        RegWriteD_out   <= RegWrite_next;
        ResultSrcD_out  <= ResultSrc_next;
        MemWriteD_out   <= MemWrite_next;

        BranchD_out     <= Branch_next;
        JumpD_out       <= Jump_next;
        JumpR_out       <= JumpR_next;

        ALUType_out     <= ALUType_next;
        funct3D_out     <= funct3_next;   // NEW
    end

endmodule







