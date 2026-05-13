`default_nettype none

// ============================================================
// Adder — Reference only (NOT synthesised)
// ============================================================

module Adder (
    input  wire [31:0] pc_E,
    input  wire [31:0] rd1_E,
    input  wire [31:0] imm_2,
    input  wire        JumpR,
    output wire [31:0] PCTarget
);

    assign PCTarget = (JumpR)
        ? ((rd1_E + imm_2) & 32'hFFFF_FFFE)
        :  (pc_E + imm_2);

endmodule

`default_nettype wire










