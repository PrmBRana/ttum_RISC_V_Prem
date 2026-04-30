`default_nettype none
`timescale 1ns / 1ps

module Write_back (
    input  wire [31:0] ALUResultW_in,
    input  wire [31:0] ReadDataW_in,
    input  wire [31:0] PCPlus4W_in,
    input  wire [1:0]  ResultSrcW_in,
    output reg  [31:0] ResultW
);
    always @(*) begin
        case (ResultSrcW_in)
            2'b00:   ResultW = ALUResultW_in;
            2'b01:   ResultW = ReadDataW_in;
            2'b10:   ResultW = PCPlus4W_in;
            default: ResultW = ALUResultW_in;
        endcase
    end
endmodule







