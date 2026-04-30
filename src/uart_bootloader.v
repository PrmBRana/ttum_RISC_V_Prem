`default_nettype none
`timescale 1ns / 1ps

module uart_bootloader (
    input  wire        clk,
    input  wire        reset,

    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    output reg  [7:0]  tx_data,
    output reg         tx_start,

    output reg         mem_we,
    output reg  [5:0]  mem_addr,
    output reg  [31:0] mem_wdata,

    output wire        stall_pro
);

    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;

    reg        handshake_done;
    reg        boot_done;
    reg        rx_valid_d;
    // ─────────────────────────────────────────────────────────
    // rx_seen: goes HIGH when we consume a byte, stays HIGH
    // until rx_valid goes LOW again — prevents re-triggering
    // on a multi-cycle rx_valid pulse
    // ─────────────────────────────────────────────────────────
    reg        rx_seen;

    reg [23:0] word_buf;
    reg [1:0]  byte_idx;
    reg [5:0]  addr_count;

    // Rising edge AND not already seen this pulse
    wire rx_edge = rx_valid & ~rx_valid_d & ~rx_seen;

    assign stall_pro = ~boot_done;

    always @(posedge clk) begin
        if (reset) begin
            handshake_done <= 1'b0;
            boot_done      <= 1'b0;
            rx_valid_d     <= 1'b0;
            rx_seen        <= 1'b0;
            tx_data        <= 8'b0;
            tx_start       <= 1'b0;
            mem_we         <= 1'b0;
            mem_addr       <= 6'b0;
            mem_wdata      <= 32'b0;
            word_buf       <= 24'b0;
            byte_idx       <= 2'b0;
            addr_count     <= 6'b0;
        end else begin
            rx_valid_d <= rx_valid;
            tx_start   <= 1'b0;
            mem_we     <= 1'b0;

            // Clear rx_seen when rx_valid goes LOW
            // Ready to accept next byte
            if (!rx_valid)
                rx_seen <= 1'b0;

            // Handshake phase
            if (!handshake_done && rx_edge) begin
                rx_seen <= 1'b1;
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data        <= ACK;
                    tx_start       <= 1'b1;
                    handshake_done <= 1'b1;
                end else begin
                    tx_data  <= NACK;
                    tx_start <= 1'b1;
                end

            // Receive & write phase
            end else if (handshake_done && !boot_done && rx_edge) begin
                rx_seen <= 1'b1;

                case (byte_idx)
                    2'd0: word_buf[ 7: 0] <= rx_data;
                    2'd1: word_buf[15: 8] <= rx_data;
                    2'd2: word_buf[23:16] <= rx_data;
                    default: ;
                endcase

                if (byte_idx == 2'd3) begin
                    mem_wdata <= {rx_data,
                                  word_buf[23:16],
                                  word_buf[15: 8],
                                  word_buf[ 7: 0]};
                    mem_addr  <= addr_count;
                    mem_we    <= 1'b1;

                    if ({rx_data,
                         word_buf[23:16],
                         word_buf[15: 8],
                         word_buf[ 7: 0]} == SENTINEL) begin
                        boot_done <= 1'b1;
                    end else if (addr_count != 6'd63) begin
                        addr_count <= addr_count + 6'd1;
                    end

                    byte_idx <= 2'd0;
                end else begin
                    byte_idx <= byte_idx + 2'd1;
                end
            end
        end
    end

endmodule
















