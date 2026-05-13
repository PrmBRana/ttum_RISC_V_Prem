`default_nettype none

// ============================================================
//  gpio_io.v — GPIO output drivers
//
//  gpio1_io : plain registered output (no peripheral dependency)
//  gpio2_io : SPI chip-select aware output (deasserts only when
//             the SPI bus is idle)
// ============================================================

// ------------------------------------------------------------
//  gpio1_io — General-purpose output register
//
//  - Reset drives the pin HIGH (safe / inactive default).
//  - wr_en1 latches wdata1 on the next rising clock edge.
//  - Pin holds its last value when wr_en1 is de-asserted.
// ------------------------------------------------------------
module gpio1_io (
    input  wire clk,
    input  wire reset,
    input  wire wr_en1,
    input  wire wdata1,
    output wire gpio_out1
);

    reg gpio_out_reg;

    always @(posedge clk) begin
        if (reset)
            gpio_out_reg <= 1'b1;       // safe default: HIGH on reset
        else if (wr_en1)
            gpio_out_reg <= wdata1;     // latch CPU write; else hold
    end

    assign gpio_out1 = gpio_out_reg;

endmodule

// ------------------------------------------------------------
//  gpio2_io — SPI chip-select aware output
//
//  - Reset drives the pin HIGH (CS deasserted).
//  - Writing 0 asserts CS immediately.
//  - Writing 1 deasserts CS only when the SPI bus is idle
//    (spi_busy == 0 && spi_pending == 0).  If the bus is still
//    active the deassert is held pending until it becomes idle.
// ------------------------------------------------------------
module gpio2_io (
    input  wire clk,
    input  wire reset,
    input  wire wr_en2,
    input  wire wdata2,
    input  wire spi_busy,
    input  wire spi_pending,
    output wire gpio_out2
);

    reg gpio_out_reg;
    reg deassert_pending;

    wire spi_idle = !spi_busy && !spi_pending;

    always @(posedge clk) begin
        if (reset) begin
            gpio_out_reg     <= 1'b1;
            deassert_pending <= 1'b0;
        end else begin

            // CPU-initiated write
            if (wr_en2) begin
                if (wdata2 == 1'b0) begin
                    // Assert CS immediately regardless of bus state
                    gpio_out_reg     <= 1'b0;
                    deassert_pending <= 1'b0;
                end else if (spi_idle) begin
                    // Deassert CS — bus is already idle
                    gpio_out_reg     <= 1'b1;
                    deassert_pending <= 1'b0;
                end else begin
                    // Bus still active — defer deassert
                    deassert_pending <= 1'b1;
                end
            end

            // Deferred deassert — fire as soon as bus goes idle
            if (deassert_pending && spi_idle) begin
                gpio_out_reg     <= 1'b1;
                deassert_pending <= 1'b0;
            end

        end
    end

    assign gpio_out2 = gpio_out_reg;

endmodule

`default_nettype wire
