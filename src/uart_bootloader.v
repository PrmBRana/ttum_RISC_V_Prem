`default_nettype none

module uart_bootloader (
    input  wire        clk,
    input  wire        reset,

    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    output reg  [7:0]  tx_data,
    output reg         tx_start,

    output reg         mem_we,
    output reg [5:0]   mem_addr,
    output reg [31:0]  mem_wdata,

    output reg         stall_pro
);

    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;

    // state
    reg handshake_done;
    reg boot_done;

    // edge detect
    reg rx_valid_d;
    wire rx_edge = rx_valid & ~rx_valid_d;

    // buffers
    reg [31:0] buffer0, buffer1;
    reg        buffer_full0, buffer_full1;
    reg        buffer_sel;
    reg [1:0]  byte_count;

    // address counter (64 depth → 6 bits)
    reg [5:0] addr_count;

    // pipeline regs
    reg [31:0] mem_wdata_reg;
    reg [5:0]  mem_addr_reg;
    reg        mem_we_reg;

    always @(posedge clk) begin
        if (reset) begin
            rx_valid_d     <= 1'b0;

            tx_data        <= 8'd0;
            tx_start       <= 1'b0;

            mem_we         <= 1'b0;
            mem_addr       <= 6'd0;
            mem_wdata      <= 32'd0;

            mem_we_reg     <= 1'b0;
            mem_addr_reg   <= 6'd0;
            mem_wdata_reg  <= 32'd0;

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

        end else begin
            rx_valid_d <= rx_valid;

            // defaults
            tx_start <= 1'b0;

            mem_we    <= mem_we_reg;
            mem_addr  <= mem_addr_reg;
            mem_wdata <= mem_wdata_reg;

            stall_pro <= ~boot_done;

            // --------------------------
            // handshake
            // --------------------------
            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data        <= ACK;
                    tx_start       <= 1'b1;
                    handshake_done <= 1'b1;
                end else begin
                    tx_data  <= NACK;
                    tx_start <= 1'b1;
                end
            end

            // --------------------------
            // receive 32-bit words
            // --------------------------
            else if (handshake_done && rx_edge && !boot_done) begin

                if (!buffer_sel) begin
                    case (byte_count)
                        2'd0: buffer0[7:0]   <= rx_data;
                        2'd1: buffer0[15:8]  <= rx_data;
                        2'd2: buffer0[23:16] <= rx_data;
                        2'd3: begin
                            buffer0[31:24] <= rx_data;
                            buffer_full0   <= 1'b1;
                        end
                    endcase
                end else begin
                    case (byte_count)
                        2'd0: buffer1[7:0]   <= rx_data;
                        2'd1: buffer1[15:8]  <= rx_data;
                        2'd2: buffer1[23:16] <= rx_data;
                        2'd3: begin
                            buffer1[31:24] <= rx_data;
                            buffer_full1   <= 1'b1;
                        end
                    endcase
                end

                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0;
                    buffer_sel <= ~buffer_sel;
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            // --------------------------
            // memory write pipeline
            // --------------------------
            if (buffer_full0) begin
                mem_wdata_reg <= buffer0;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;

                addr_count    <= addr_count + 1'b1;
                buffer_full0  <= 1'b0;

                if (buffer0 == SENTINEL)
                    boot_done <= 1'b1;

            end else if (buffer_full1) begin
                mem_wdata_reg <= buffer1;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;

                addr_count    <= addr_count + 1'b1;
                buffer_full1  <= 1'b0;

                if (buffer1 == SENTINEL)
                    boot_done <= 1'b1;

            end else begin
                mem_we_reg <= 1'b0;
            end

        end
    end

endmodule

`default_nettype wire
