`default_nettype none

// ============================================================
//  uart_bootloader — RISC-V Bootloader via UART
//
//  TX behaviour: ACK/NACK only.
//    ACK  (0x55) — sent once when valid handshake byte (0x25)
//                  is received.
//    NACK (0xFF) — sent when an invalid handshake byte is
//                  received before handshake is complete.
//    Nothing else is ever transmitted.
//
//  FIXES (v2.0):
//  1. addr_count is 6-bit to support DEPTH=64 (0-63)
//  2. Address bounds checking: won't write beyond DEPTH-1
//  3. Proper masking of mem_addr output [5:0]
//  4. mem_addr port is [7:0] for pipeline compatibility
//     (bootloader only uses [5:0] safely)
//
// ============================================================
module uart_bootloader (
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    output reg         mem_we,
    output reg  [7:0]  mem_addr,
    output reg  [31:0] mem_wdata,
    output reg         stall_pro
);

    // ========================================================
    // PARAMETERS
    // ========================================================
    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;  // ECALL — marks end of program
    localparam IMEM_DEPTH            = 64;           // Must match instruction_mem DEPTH

    // ========================================================
    // INTERNAL STATE REGISTERS
    // ========================================================
    reg handshake_done;
    reg boot_done;
    reg rx_valid_d;

    // Dual buffers for instruction words
    reg [31:0] buffer0, buffer1;
    reg        buffer_full0, buffer_full1;
    reg        buffer_sel;
    reg [1:0]  byte_count;

    // Address counter: 6-bit to support DEPTH=64 (addresses 0-63)
    reg [5:0]  addr_count;

    // Internal pipeline registers (for registered memory write)
    reg [31:0] mem_wdata_reg;
    reg [5:0]  mem_addr_reg;
    reg        mem_we_reg;

    // ========================================================
    // EDGE DETECTION
    // ========================================================
    wire rx_edge = rx_valid & ~rx_valid_d;

    // ========================================================
    // MAIN ALWAYS BLOCK
    // ========================================================
    always @(posedge clk) begin
        if (reset) begin
            // Reset all state
            rx_valid_d     <= 1'b0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
            mem_we         <= 1'b0;
            mem_addr       <= 8'd0;
            mem_wdata      <= 32'd0;
            handshake_done <= 1'b0;
            boot_done      <= 1'b0;
            buffer0        <= 32'd0;
            buffer1        <= 32'd0;
            buffer_full0   <= 1'b0;
            buffer_full1   <= 1'b0;
            buffer_sel     <= 1'b0;
            byte_count     <= 2'd0;
            addr_count     <= 6'd0;
            stall_pro      <= 1'b1;
            mem_wdata_reg  <= 32'd0;
            mem_addr_reg   <= 6'd0;
            mem_we_reg     <= 1'b0;
        end else begin
            // ── Synchronize rx_valid for edge detection ──
            rx_valid_d <= rx_valid;

            // ── Default: no TX ──
            tx_start <= 1'b0;

            // ── Register outputs from pipeline ──
            mem_we    <= mem_we_reg;
            mem_addr  <= {2'b00, mem_addr_reg};    // FIX: properly masked to [7:0]
            mem_wdata <= mem_wdata_reg;
            stall_pro <= ~boot_done;

            // ────────────────────────────────────────────────────
            // HANDSHAKE PHASE (before data reception)
            // ────────────────────────────────────────────────────
            // Only place that asserts tx_start (for ACK or NACK)
            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data        <= ACK;
                    tx_start       <= 1'b1;
                    handshake_done <= 1'b1;
                    // Ready to receive program data
                end else begin
                    // Invalid handshake byte, send NACK
                    tx_data  <= NACK;
                    tx_start <= 1'b1;
                    // Do not set handshake_done; wait for correct byte
                end
            end

            // ────────────────────────────────────────────────────
            // DATA RECEPTION PHASE (after handshake, before boot_done)
            // ────────────────────────────────────────────────────
            // Assemble 4 bytes into 32-bit instruction words
            else if (handshake_done && rx_edge && !boot_done) begin
                if (!buffer_sel) begin
                    // Buffer 0: receive bytes LSB → MSB
                    case (byte_count)
                        2'd0: buffer0[7:0]   <= rx_data;
                        2'd1: buffer0[15:8]  <= rx_data;
                        2'd2: buffer0[23:16] <= rx_data;
                        2'd3: begin
                            buffer0[31:24] <= rx_data;
                            buffer_full0   <= 1'b1;
                        end
                        default: ;
                    endcase
                end else begin
                    // Buffer 1: receive bytes LSB → MSB
                    case (byte_count)
                        2'd0: buffer1[7:0]   <= rx_data;
                        2'd1: buffer1[15:8]  <= rx_data;
                        2'd2: buffer1[23:16] <= rx_data;
                        2'd3: begin
                            buffer1[31:24] <= rx_data;
                            buffer_full1   <= 1'b1;
                        end
                        default: ;
                    endcase
                end

                // Advance byte counter, toggle buffer when word is complete
                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0;
                    buffer_sel <= ~buffer_sel;
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            // ────────────────────────────────────────────────────
            // MEMORY WRITE PIPELINE
            // ────────────────────────────────────────────────────
            // When a buffer is full, write it to IMEM
            // FIX: Add bounds checking (don't write beyond DEPTH-1)
            if (buffer_full0 && (addr_count < IMEM_DEPTH)) begin
                mem_wdata_reg <= buffer0;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;
                addr_count    <= addr_count + 1'b1;
                buffer_full0  <= 1'b0;
                if (buffer0 == SENTINEL) boot_done <= 1'b1;
            end else if (buffer_full1 && (addr_count < IMEM_DEPTH)) begin
                mem_wdata_reg <= buffer1;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;
                addr_count    <= addr_count + 1'b1;
                buffer_full1  <= 1'b0;
                if (buffer1 == SENTINEL) boot_done <= 1'b1;
            end else begin
                mem_we_reg <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire

