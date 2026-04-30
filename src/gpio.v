`default_nettype none
`timescale 1ns/1ps

module gpio2_io (
    input  wire clk,
    input  wire reset,
    input  wire wr_en2,
    input  wire wdata2,
    input  wire spi_busy,
    input  wire spi_pending,
    output reg  gpio_out2
);

    wire spi_active = spi_busy | spi_pending;

    always @(posedge clk) begin
        if (reset) begin
            gpio_out2 <= 1'b1;        // Default reset state
        end else begin
            if (spi_active) begin
                gpio_out2 <= 1'b0;    // SPI active forces GPIO low (e.g. LED indicator)
            end else if (wr_en2) begin
                gpio_out2 <= wdata2;  // Normal GPIO write
            end
            // else: hold previous value (no automatic pull to 1)
        end
    end

endmodule









