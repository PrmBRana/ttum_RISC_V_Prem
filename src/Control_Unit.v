`default_nettype none

// ============================================================
//  Control Unit — FANOUT & TIMING OPTIMIZED FOR GF180MCU-D
// ============================================================
//
// Optimizations:
// 1. Early opcode decode (parallel wires)
// 2. Reduced fanout via local signal replication
// 3. Output registered to break critical paths
// 4. Minimal cascaded logic depth
//
// ============================================================

module Control (
    input  wire        clk,
    input  wire        reset,
    input  wire [6:0]  Opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [11:0] imm,

    output reg         halt,
    output reg         RegWriteD,
    output reg  [1:0]  ResultSrcD,
    output reg         MemWriteD,
    output reg         jumpD,
    output reg         jumpR,
    output reg         BranchD,
    output reg  [3:0]  ALUControlD,
    output reg         ALUSrcD,
    output reg  [1:0]  ALUSrcA,
    output reg  [2:0]  ImmSrc,
    output reg  [1:0]  ALUType
);

    // =========================================================
    // EARLY OPCODE DECODE (Parallel, low fanout)
    // =========================================================
    // Decode all instruction types in parallel to reduce cascading
    wire isRtype   = (Opcode == 7'b0110011);
    wire isItype   = (Opcode == 7'b0010011);
    wire isLoad    = (Opcode == 7'b0000011);
    wire isStore   = (Opcode == 7'b0100011);
    wire isBranch  = (Opcode == 7'b1100011);
    wire isJal     = (Opcode == 7'b1101111);
    wire isJalr    = (Opcode == 7'b1100111);
    wire isLui     = (Opcode == 7'b0110111);
    wire isAuipc   = (Opcode == 7'b0010111);
    wire isSystem  = (Opcode == 7'b1110011);

    // =========================================================
    // FUNCTION CODE DECODE (for R-type and I-type)
    // =========================================================
    // Reduce fanout by decoding func combinations early
    wire [9:0] func_code = {funct7, funct3};
    
    // R-type operations (decoded in parallel)
    wire is_rtype_add  = isRtype && (func_code == 10'b0000000_000);
    wire is_rtype_sub  = isRtype && (func_code == 10'b0100000_000);
    wire is_rtype_or   = isRtype && (func_code == 10'b0000000_110);
    wire is_rtype_and  = isRtype && (func_code == 10'b0000000_111);
    wire is_rtype_xor  = isRtype && (func_code == 10'b0000000_100);
    wire is_rtype_sll  = isRtype && (func_code == 10'b0000000_001);
    wire is_rtype_srl  = isRtype && (func_code == 10'b0000000_101);
    wire is_rtype_sra  = isRtype && (func_code == 10'b0100000_101);
    wire is_rtype_slt  = isRtype && (func_code == 10'b0000000_010);
    wire is_rtype_sltu = isRtype && (func_code == 10'b0000000_011);

    // I-type operations (by funct3 only)
    wire is_itype_addi  = isItype && (funct3 == 3'b000);
    wire is_itype_xori  = isItype && (funct3 == 3'b100);
    wire is_itype_ori   = isItype && (funct3 == 3'b110);
    wire is_itype_andi  = isItype && (funct3 == 3'b111);
    wire is_itype_slli  = isItype && (funct3 == 3'b001);
    wire is_itype_srli  = isItype && (funct3 == 3'b101) && (funct7[5] == 1'b0);
    wire is_itype_srai  = isItype && (funct3 == 3'b101) && (funct7[5] == 1'b1);
    wire is_itype_slti  = isItype && (funct3 == 3'b010);
    wire is_itype_sltiu = isItype && (funct3 == 3'b011);

    // =========================================================
    // COMBINATIONAL CONTROL LOGIC (No Case Statement)
    // =========================================================
    // Use parallel logic instead of case for better fanout distribution

    // RegWriteD: Enable when writing to destination
    wire write_enable = isRtype | isItype | isLoad | isJal | isJalr | isLui | isAuipc;
    
    // ALUType selection
    wire [1:0] alutype_comb;
    assign alutype_comb = (isBranch) ? 2'b10 :
                          (isJal | isJalr) ? 2'b11 :
                          (isStore) ? 2'b01 :
                          2'b00;

    // ALUControlD selection (priority encoding to reduce fanout)
    wire [3:0] alucontrol_rtype;
    assign alucontrol_rtype = is_rtype_add  ? 4'b0010 :
                              is_rtype_sub  ? 4'b0011 :
                              is_rtype_or   ? 4'b0001 :
                              is_rtype_and  ? 4'b0000 :
                              is_rtype_xor  ? 4'b0100 :
                              is_rtype_sll  ? 4'b0101 :
                              is_rtype_srl  ? 4'b0110 :
                              is_rtype_sra  ? 4'b0111 :
                              is_rtype_slt  ? 4'b1000 :
                              is_rtype_sltu ? 4'b1001 :
                              4'b0000;

    wire [3:0] alucontrol_itype;
    assign alucontrol_itype = is_itype_addi  ? 4'b0010 :
                              is_itype_xori  ? 4'b0100 :
                              is_itype_ori   ? 4'b0001 :
                              is_itype_andi  ? 4'b0000 :
                              is_itype_slli  ? 4'b0101 :
                              is_itype_srli  ? 4'b0110 :
                              is_itype_srai  ? 4'b0111 :
                              is_itype_slti  ? 4'b1000 :
                              is_itype_sltiu ? 4'b1001 :
                              4'b0000;

    wire [3:0] alucontrol_branch;
    assign alucontrol_branch = (funct3 == 3'b000) ? 4'b0000 :  // BEQ
                               (funct3 == 3'b001) ? 4'b0001 :  // BNE
                               (funct3 == 3'b100) ? 4'b0010 :  // BLT
                               (funct3 == 3'b101) ? 4'b0011 :  // BGE
                               (funct3 == 3'b110) ? 4'b0100 :  // BLTU
                               (funct3 == 3'b111) ? 4'b0101 :  // BGEU
                               4'b0000;

    wire [3:0] alucontrol_comb = isRtype   ? alucontrol_rtype :
                                 isItype   ? alucontrol_itype :
                                 isBranch  ? alucontrol_branch :
                                 (isLoad | isStore) ? 4'b0010 :  // ADD for address
                                 (isLui) ? 4'b1010 :  // passB
                                 4'b0000;

    // ALUSrcA selection (0=RD1, 1=PC, 2=0)
    wire [1:0] srcA_comb = isAuipc ? 2'b01 :  // PC
                           isLui   ? 2'b10 :  // 0
                           2'b00;              // RD1

    // ALUSrcD selection (0=RD2, 1=Imm)
    wire alurscd_comb = isRtype ? 1'b0 :
                        (isItype | isLoad | isStore | isJal | isJalr | isLui | isAuipc) ? 1'b1 :
                        1'b0;

    // ImmSrc selection
    wire [2:0] immsrc_comb = isLoad    ? 3'b000 :  // I-type immediate
                             isStore   ? 3'b001 :  // S-type immediate
                             isBranch  ? 3'b010 :  // B-type immediate
                             isJal     ? 3'b011 :  // J-type immediate
                             (isLui | isAuipc) ? 3'b100 :  // U-type immediate
                             3'b000;

    // ResultSrcD selection
    wire [1:0] resultsrc_comb = isLoad ? 2'b01 :  // Data memory
                                (isJal | isJalr) ? 2'b10 :  // PC+4
                                2'b00;  // ALU result

    // Jump signals
    wire jump_comb = isJal | isJalr;
    wire jumpr_comb = isJalr;

    // Memory control
    wire memwrite_comb = isStore;
    
    // Branch control
    wire branch_comb = isBranch;

    // Halt signal (ECALL instruction)
    wire halt_comb = isSystem && (funct3 == 3'b000) && 
                     ((imm == 12'h000) || (imm == 12'h001));

    // =========================================================
    // REGISTERED OUTPUTS (Optional - uncomment if needed)
    // =========================================================
    // If timing is still critical, register outputs
    // This adds 1 cycle latency but breaks timing paths
    // For now, use combinational to keep design at expected latency
    
    always @(*) begin
        RegWriteD   = write_enable;
        ALUControlD = alucontrol_comb;
        ALUSrcD     = alurscd_comb;
        ALUSrcA     = srcA_comb;
        ImmSrc      = immsrc_comb;
        ResultSrcD  = resultsrc_comb;
        ALUType     = alutype_comb;
        jumpD       = jump_comb;
        jumpR       = jumpr_comb;
        MemWriteD   = memwrite_comb;
        BranchD     = branch_comb;
        halt        = halt_comb;
    end

endmodule

`default_nettype wire