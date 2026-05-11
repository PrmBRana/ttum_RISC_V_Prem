`default_nettype none

module tt_um_prem_pipeline_test (
    input  wire [7:0] ui_in,     // Dedicated inputs
    output wire [7:0] uo_out,    // Dedicated outputs
    input  wire [7:0] uio_in,    // IOs: Input path
    output wire [7:0] uio_out,   // IOs: Output path
    output wire [7:0] uio_oe,    // IOs: Output enable (1=output)
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // =========================================================
    // Unused signals suppression (Verilator + synthesis clean)
    // =========================================================
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{
        1'b0,
        ui_in[7:5],     // unused input bits
        ui_in[2:0],     // unused input bits
        uio_in[6:0],    // all except [7] which is SPI2 MISO
        ena             // Tiny Tapeout power enable (always 1)
    };
    /* verilator lint_on UNUSEDSIGNAL */

    wire reset = ~rst_n;

    // ── UART signals ─────────────────────────────────────
    wire uart1_rx = ui_in[3];   // Bootloader RX
    wire uart2_rx = ui_in[4];   // Peripheral UART RX
    wire uart1_tx;
    wire uart2_tx;

    // ── SPI2 signals ─────────────────────────────────────
    wire spi2_miso_w = uio_in[7];

    // ── GPIO signals ─────────────────────────────────────
    wire spi1_cs_n_w;
    wire spi2_cs_n_w;
    wire spi2_mosi_w;
    wire spi2_sclk_w;

    // ── Output assignments ───────────────────────────────
    assign uo_out[0]   = uart1_tx;      // Bootloader TX
    assign uo_out[1]   = uart2_tx;      // Peripheral TX
    assign uo_out[7:2] = 6'b000000;     // unused

    // uio_out
    assign uio_out[0] = spi1_cs_n_w;    // SPI1 CS_N
    assign uio_out[1] = 1'b0;
    assign uio_out[2] = spi2_mosi_w;    // SPI2 MOSI
    assign uio_out[3] = spi2_sclk_w;    // SPI2 SCLK
    assign uio_out[4] = spi2_cs_n_w;    // SPI2 CS_N
    assign uio_out[7:5] = 3'b000;

    // uio_oe (1 = output)
    assign uio_oe[0] = 1'b1;   // SPI1 CS_N
    assign uio_oe[1] = 1'b0;
    assign uio_oe[2] = 1'b1;   // SPI2 MOSI
    assign uio_oe[3] = 1'b1;   // SPI2 SCLK
    assign uio_oe[4] = 1'b1;   // SPI2 CS_N
    assign uio_oe[7:5] = 3'b000;

    // =========================================================
    // Core instantiation
    // =========================================================
    pipeline Top_inst (
        .clk          (clk),
        .reset        (reset),

        // Bootloader UART
        .rx           (uart1_rx),
        .tx           (uart1_tx),

        // Peripheral UART
        .UART_tx      (uart2_tx),
        .UART_rx_line (uart2_rx),

        // SPI2
        .spi2_sclk    (spi2_sclk_w),
        .spi2_mosi    (spi2_mosi_w),
        .spi2_miso    (spi2_miso_w),
        .spi2_cs_n    (spi2_cs_n_w),

        // SPI1 CS (from GPIO1)
        .spi1_cs_n    (spi1_cs_n_w)
    );

endmodule

`default_nettype wire





