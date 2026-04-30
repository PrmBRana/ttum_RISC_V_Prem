`default_nettype none
`timescale 1ns/1ps

module Hazard_Unit (
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
    input  wire        PCSRCE,        // Branch or Jump taken
    output reg         StallF,
    output reg         StallD,
    output reg         FlushD,
    output reg         FlushE,
    output reg  [1:0]  Forward_AE,
    output reg  [1:0]  Forward_BE
);

    // ====================== Forwarding Logic ======================
    always @(*) begin
        Forward_AE = 2'b00;
        Forward_BE = 2'b00;

        // Forward from MEM stage (higher priority)
        if (RegWriteM && (RdM != 5'd0)) begin
            if (RdM == Rs1E) Forward_AE = 2'b10;
            if (RdM == Rs2E) Forward_BE = 2'b10;
        end
        // Forward from WB stage
        else if (RegWriteW && (RdW != 5'd0)) begin
            if (RdW == Rs1E) Forward_AE = 2'b01;
            if (RdW == Rs2E) Forward_BE = 2'b01;
        end
    end

    // ====================== Hazard Detection ======================
    wire load_use_hazard = 
        (ResultSrcE_in == 2'b01) && RegWriteE && (RdE != 5'd0) &&
        ((Rs1D == RdE) || (Rs2D == RdE));

    always @(*) begin
        StallF = 1'b0;
        StallD = 1'b0;
        FlushD = 1'b0;
        FlushE = 1'b0;

        if (PCSRCE) begin
            // Control hazard: flush Decode and Execute stages
            FlushD = 1'b1;
            FlushE = 1'b1;
        end 
        else if (load_use_hazard) begin
            // Load-Use hazard: stall Fetch & Decode, flush Execute
            StallF = 1'b1;
            StallD = 1'b1;
            FlushE = 1'b1;
        end
    end

endmodule










