`default_nettype none
`timescale 1ns/1ps

// ============================================================
//  DataMem.v — ASIC-safe Registered Read RAM + MMIO
//  Optimized for GF180MCU / wafer.space / Tiny Tapeout
//  Memory: 32 words (128 bytes) recommended
// ============================================================

module DataMem #(
    parameter integer DMEM_DEPTH  = 32,
    parameter integer DMEM_ADDR_W = 5
)(
    input  wire        clk,
    input  wire        reset,               // synchronous reset (use reset_sync from top)

    input  wire [31:0] aluAddress_in,
    input  wire [31:0] DataWriteM_in,
    input  wire [3:0]  byte_en,
    input  wire        memwriteM_in,

    output reg  [31:0] DataMem_out,

    // UART
    output reg  [7:0]  uart_out_data,
    output reg         uart_tx_start,
    input  wire        uart_tx_busy,

    // SPI2
    output reg  [7:0]  spi2_tx_data,
    output reg         spi2_start,
    output wire        spi2_pending_out,
    input  wire [7:0]  spi2_rx_data,
    input  wire        spi2_busy,
    input  wire        spi2_done,

    // GPIO
    output reg         gpio2_wr_en,
    output reg         gpio2_wdata
);

    // =========================================================
    // Address Decode
    // =========================================================
    wire sel_ram       = (aluAddress_in[31:8] == 24'h200000);   // 0x2000_0000 ~ 0x2000_007F
    wire sel_uart_tx   = (aluAddress_in == 32'h1000_0000);
    wire sel_uart_txst = (aluAddress_in == 32'h1000_0008);
    wire sel_spi2_tx   = (aluAddress_in == 32'h4000_0000);
    wire sel_spi2_txst = (aluAddress_in == 32'h4000_0004);
    wire sel_spi2_rx   = (aluAddress_in == 32'h4000_0008);
    wire sel_spi2_rxst = (aluAddress_in == 32'h4000_000C);
    wire sel_gpio2     = (aluAddress_in == 32'h3000_0004);

    wire [DMEM_ADDR_W-1:0] ram_word_idx = aluAddress_in[DMEM_ADDR_W+1:2];

    // =========================================================
    // On-chip RAM (Registered Read - better timing on 180nm)
    // =========================================================
    reg [31:0] dmem [0:DMEM_DEPTH-1];
    reg [31:0] ram_rdata_reg;

    // Write logic with byte enables
    always @(posedge clk) begin
        if (memwriteM_in && sel_ram) begin
            if (byte_en[0]) dmem[ram_word_idx][ 7: 0] <= DataWriteM_in[ 7: 0];
            if (byte_en[1]) dmem[ram_word_idx][15: 8] <= DataWriteM_in[15: 8];
            if (byte_en[2]) dmem[ram_word_idx][23:16] <= DataWriteM_in[23:16];
            if (byte_en[3]) dmem[ram_word_idx][31:24] <= DataWriteM_in[31:24];
        end
    end

    // Registered read (safer for timing)
    always @(posedge clk) begin
        if (reset)
            ram_rdata_reg <= 32'd0;
        else if (sel_ram)
            ram_rdata_reg <= dmem[ram_word_idx];
    end

    // =========================================================
    // SPI Done rising edge detection
    // =========================================================
    reg spi_done_prev;
    always @(posedge clk) begin
        if (reset)
            spi_done_prev <= 1'b0;
        else
            spi_done_prev <= spi2_done;
    end
    wire spi_done_rise = spi2_done & ~spi_done_prev;

    // =========================================================
    // UART TX with pending flag
    // =========================================================
    reg uart_pending;

    always @(posedge clk) begin
        if (reset) begin
            uart_out_data  <= 8'd0;
            uart_tx_start  <= 1'b0;
            uart_pending   <= 1'b0;
        end else begin
            uart_tx_start <= 1'b0;

            if (memwriteM_in && sel_uart_tx && !uart_pending) begin
                uart_out_data <= DataWriteM_in[7:0];
                uart_tx_start <= 1'b1;
                uart_pending  <= 1'b1;
            end

            if (uart_pending && !uart_tx_busy)
                uart_pending <= 1'b0;
        end
    end

    // =========================================================
    // SPI TX
    // =========================================================
    reg       spi_pending;
    reg       start_armed;
    reg [7:0] spi_buf;

    assign spi2_pending_out = spi_pending;

    always @(posedge clk) begin
        if (reset) begin
            spi2_start   <= 1'b0;
            spi_pending  <= 1'b0;
            start_armed  <= 1'b0;
            spi_buf      <= 8'd0;
        end else begin
            spi2_start <= 1'b0;

            if (memwriteM_in && sel_spi2_tx && !spi_pending && !spi2_busy) begin
                spi_buf      <= DataWriteM_in[7:0];
                spi_pending  <= 1'b1;
                start_armed  <= 1'b1;
            end

            if (start_armed && !spi2_busy) begin
                spi2_tx_data <= spi_buf;
                spi2_start   <= 1'b1;
                start_armed  <= 1'b0;
            end

            if (spi_done_rise)
                spi_pending <= 1'b0;
        end
    end

    // =========================================================
    // SPI RX (read clears valid flag)
    // =========================================================
    reg [7:0] spi_rx;
    reg       spi_rx_valid;

    always @(posedge clk) begin
        if (reset) begin
            spi_rx       <= 8'd0;
            spi_rx_valid <= 1'b0;
        end else begin
            if (spi_done_rise) begin
                spi_rx       <= spi2_rx_data;
                spi_rx_valid <= 1'b1;
            end

            // Clear valid when CPU reads RX data
            if (!memwriteM_in && sel_spi2_rx)
                spi_rx_valid <= 1'b0;
        end
    end

    // =========================================================
    // GPIO2
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            gpio2_wr_en <= 1'b0;
            gpio2_wdata <= 1'b1;        // default high (CS_N deasserted)
        end else begin
            gpio2_wr_en <= 1'b0;
            if (memwriteM_in && sel_gpio2) begin
                gpio2_wdata <= DataWriteM_in[0];
                gpio2_wr_en <= 1'b1;
            end
        end
    end

    // =========================================================
    // Read Output Mux
    // =========================================================
    always @(*) begin
        DataMem_out = 32'd0;

        if (!memwriteM_in) begin
            if (sel_uart_txst)
                DataMem_out = {30'd0, uart_tx_busy, uart_pending};
            else if (sel_spi2_txst)
                DataMem_out = {30'd0, spi_pending, spi2_busy};
            else if (sel_spi2_rx)
                DataMem_out = {24'd0, spi_rx};
            else if (sel_spi2_rxst)
                DataMem_out = {31'd0, spi_rx_valid};
            else if (sel_gpio2)
                DataMem_out = {31'd0, gpio2_wdata};
            else if (sel_ram)
                DataMem_out = ram_rdata_reg;
        end
    end

endmodule











