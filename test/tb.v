`timescale 1ns/1ps
`default_nettype none

module tb();

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end

    // --------------------------------------------------
    // Clock / Reset
    // --------------------------------------------------
    reg clk;
    reg rst_n;
    reg ena;

    // --------------------------------------------------
    // UART
    // --------------------------------------------------
    reg  rx;
    wire tx;

    // --------------------------------------------------
    // SPI
    // --------------------------------------------------
    reg  spi2_miso;
    wire spi2_mosi;
    wire spi2_sclk;
    wire spi2_cs_n;

    // --------------------------------------------------
    // GPIO (FIX: was missing)
    // --------------------------------------------------
    wire gpio1_out;

    // --------------------------------------------------
    // IO buses
    // --------------------------------------------------
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg  [7:0] uio_in;

    // --------------------------------------------------
    // ui_in mapping
    // --------------------------------------------------
    always @(*) begin
        ui_in = 8'b0;
        ui_in[3] = rx;
    end

    // --------------------------------------------------
    // uio_in mapping
    // --------------------------------------------------
    always @(*) begin
        uio_in = 8'b0;
        uio_in[7] = spi2_miso;
    end

    // --------------------------------------------------
    // Correct output mapping (FIXED)
    // --------------------------------------------------
    assign tx          = uo_out[0];

    assign spi2_mosi   = uio_out[1];
    assign spi2_sclk   = uio_out[2];
    assign spi2_cs_n   = uio_out[3];
    assign gpio1_out   = uio_out[4];

    // --------------------------------------------------
    // Clock (45 MHz)
    // --------------------------------------------------
    always #11.11 clk = ~clk;

    // --------------------------------------------------
    // Initial
    // --------------------------------------------------
    initial begin
        clk = 0;
        rst_n = 0;
        ena = 1;

        rx = 1'b1;
        spi2_miso = 1'b1;

        #100;
        rst_n = 1;
    end

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------
    tt_um_prem_pipeline_test dut (
`ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

endmodule

`default_nettype wire