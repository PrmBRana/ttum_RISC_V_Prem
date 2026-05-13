`default_nettype none

module tt_um_prem_pipeline_test (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    wire reset = ~rst_n;

    // --------------------------------------------------
    // UART
    // --------------------------------------------------
    wire uart_rx = ui_in[3];
    wire uart_tx;

    // --------------------------------------------------
    // SPI
    // --------------------------------------------------
    wire spi2_mosi;
    wire spi2_sclk;
    wire spi2_cs_n;
    wire spi2_miso = uio_in[7];

    // --------------------------------------------------
    // GPIO (FIX: was missing)
    // --------------------------------------------------
    wire gpio1_out;

    // --------------------------------------------------
    // Unused signals cleanup
    // --------------------------------------------------
    wire _unused = &{ui_in[7:4], ui_in[2:0], uio_in[6:0], ena};

    // --------------------------------------------------
    // Output (UART only on uo_out[0])
    // --------------------------------------------------
    assign uo_out = {7'b0000000, uart_tx};

    // --------------------------------------------------
    // UIO mapping (FIXED to 8 bits)
    //
    // [0] UART TX
    // [1] MOSI
    // [2] SCLK
    // [3] CS
    // [4] GPIO
    // [5] 0
    // [6] 0
    // [7] 0
    // --------------------------------------------------
    assign uio_out = {
        1'b0,         // [7]
        1'b0,         // [6]
        1'b0,         // [5]
        gpio1_out,    // [4]
        spi2_cs_n,    // [3]
        spi2_sclk,    // [2]
        spi2_mosi,    // [1]
        uart_tx       // [0]
    };

    // Enable only used outputs: uart + spi + gpio
    assign uio_oe = 8'b00011111;

    // --------------------------------------------------
    // Pipeline core
    // --------------------------------------------------
    pipeline Top_inst (
        .clk(clk),
        .reset(reset),

        .rx(uart_rx),
        .tx(uart_tx),

        .spi2_cs_n(spi2_cs_n),
        .spi2_sclk(spi2_sclk),
        .spi2_mosi(spi2_mosi),
        .spi2_miso(spi2_miso),

        .gpio1_out(gpio1_out)
    );

endmodule

`default_nettype wire