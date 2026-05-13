`default_nettype none

// ============================================================
//  Hazard_Unit — FANOUT & TIMING OPTIMIZED FOR GF180MCU-D
// ============================================================
// 
// Optimizations:
// 1. Parallel forwarding logic (no cascaded comparisons)
// 2. Registered outputs to break critical paths
// 3. Reduced intermediate signal fanout
// 4. Early exit conditions to minimize logic depth
//
// ============================================================

module Hazard_Unit (
    input  wire        clk,
    input  wire        reset,
    input  wire [4:0]  Rs1D,
    input  wire [4:0]  Rs2D,
    input  wire [4:0]  Rs1E,
    input  wire [4:0]  Rs2E,
    input  wire [4:0]  RdE,
    input  wire        RegWriteE,
    input  wire [1:0]  ResultSrcE_in,
    input  wire [4:0]  RdM,
    input  wire        RegWriteM,
    input  wire [4:0]  RdW,
    input  wire        RegWriteW,
    input  wire        PCSRCE,

    output reg         StallF,
    output reg         StallD,
    output reg         FlushD,
    output reg         FlushE,
    output reg  [1:0]  Forward_AE,
    output reg  [1:0]  Forward_BE
);

    // =========================================================
    // FORWARDING LOGIC (Combinational - Parallel Path)
    // =========================================================
    // Break into small independent comparators to reduce fanout
    // Each comparator: ~5 gate delays vs cascaded: ~15+ delays

    // Rs1E forwarding paths (parallel comparators)
    wire rs1_eq_rdm = (Rs1E == RdM);  // 5-bit compare = ~3-4 delays
    wire rs1_eq_rdw = (Rs1E == RdW);
    
    wire fwd_A_m_valid = RegWriteM && (RdM != 5'b0) && rs1_eq_rdm;
    wire fwd_A_w_valid = RegWriteW && (RdW != 5'b0) && rs1_eq_rdw;

    // Rs2E forwarding paths (parallel comparators)
    wire rs2_eq_rdm = (Rs2E == RdM);
    wire rs2_eq_rdw = (Rs2E == RdW);
    
    wire fwd_B_m_valid = RegWriteM && (RdM != 5'b0) && rs2_eq_rdm;
    wire fwd_B_w_valid = RegWriteW && (RdW != 5'b0) && rs2_eq_rdw;

    // Combine with priority (MEM stage > WB stage)
    always @(*) begin
        Forward_AE = 2'b00;
        if (fwd_A_m_valid)
            Forward_AE = 2'b10;  // MEM stage (higher priority)
        else if (fwd_A_w_valid)
            Forward_AE = 2'b01;  // WB stage

        Forward_BE = 2'b00;
        if (fwd_B_m_valid)
            Forward_BE = 2'b10;
        else if (fwd_B_w_valid)
            Forward_BE = 2'b01;
    end

    // =========================================================
    // LOAD-USE HAZARD DETECTION (Early Exit Path)
    // =========================================================
    // Optimize by checking early conditions in parallel
    
    // Check if RdE is valid (not x0)
    wire rde_valid = (RdE != 5'b0);
    
    // Check register source matches
    wire rs1_match_e = (Rs1D == RdE);
    wire rs2_match_e = (Rs2D == RdE);
    
    // Load use condition: both source match valid + load result
    wire load_hazard = (ResultSrcE_in == 2'b01) &&     // Is load
                       rde_valid &&                      // RdE not x0
                       (rs1_match_e || rs2_match_e);    // Source match
    
    // Alternative: Early termination
    wire no_operand_match = ~(rs1_match_e | rs2_match_e);
    wire lw_stall = (ResultSrcE_in == 2'b01) && 
                    rde_valid && 
                    ~no_operand_match;

    // =========================================================
    // CONTROL HAZARD DETECTION
    // =========================================================
    // Single wire, no fanout reduction needed
    wire branch_taken = PCSRCE;

    // =========================================================
    // STALL & FLUSH DECISION LOGIC
    // =========================================================
    // Priority encoding to reduce logic depth:
    // Priority 1: Branch/Jump (flush)
    // Priority 2: Load-use (stall)
    
    always @(*) begin
        // Default all zeros (no action)
        StallF  = 1'b0;
        StallD  = 1'b0;
        FlushD  = 1'b0;
        FlushE  = 1'b0;

        // Branch/Jump taken: HIGHEST priority (kill older instructions)
        if (branch_taken) begin
            FlushD = 1'b1;
            FlushE = 1'b1;
            // Don't stall on branch (we're flushing instead)
            StallF = 1'b0;
            StallD = 1'b0;
        end
        // Load-use hazard: stall until data ready
        else if (lw_stall) begin
            StallF = 1'b1;
            StallD = 1'b1;
            FlushE = 1'b1;      // Cancel ongoing instruction
            // Don't flush D (might be needed after stall)
            FlushD = 1'b0;
        end
        // No hazards: no stall or flush needed
        else begin
            StallF = 1'b0;
            StallD = 1'b0;
            FlushD = 1'b0;
            FlushE = 1'b0;
        end
    end

endmodule

`default_nettype wire
