`default_nettype none

// ============================================================
//  spi_master.v
//  Fix applied (Verilator / LibreLane GF180MCU-D clean):
//
//  WIDTHTRUNC (lines 27-28):
//    localparam [$clog2(CLK_DIV)-1:0] HALF_DIV = (CLK_DIV/2) - 1;
//    localparam [$clog2(CLK_DIV)-1:0] FULL_DIV  = CLK_DIV - 1;
//
//  Both right-hand-side expressions are evaluated as full 32-bit
//  integer arithmetic and then truncated into a narrower
//  localparam, which Verilator flags as WIDTHTRUNC.
//
//  Fix: explicitly cast the RHS to the required width using a
//  Verilog part-select / width-cast idiom:
//    HALF_DIV = ($clog2(CLK_DIV))'( (CLK_DIV/2) - 1 )
//  This syntax is valid in IEEE 1800-2012 (SystemVerilog, which
//  LibreLane / Verilator accept) and makes the truncation
//  intentional and warning-free.
//
//  No logic changes — all FSM / shift-register behaviour is
//  identical to the original.
// ============================================================

module spi_master #(
    parameter DATA_WIDTH = 8,
    parameter CPOL       = 0,
    parameter CPHA       = 0,
    parameter CLK_DIV    = 8
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  start,
    input  wire [DATA_WIDTH-1:0] tx_data,
    output reg  [DATA_WIDTH-1:0] rx_data,
    output reg                   busy,
    output reg                   done,
    output reg                   sclk,
    output reg                   mosi,
    input  wire                  miso
);

    // ── Internal shift registers / counters ──────────────────
    reg [DATA_WIDTH-1:0]           tx_shift, rx_shift;
    reg [$clog2(DATA_WIDTH+1)-1:0] bit_cnt;
    reg [$clog2(CLK_DIV)-1:0]      clk_div;
    reg                            sclk_en, sclk_d;
    reg [1:0]                      state;

    // ── Clock-divider thresholds ──────────────────────────────
    // RHS cast to [$clog2(CLK_DIV)] bits explicitly so Verilator
    // does not emit WIDTHTRUNC (the 32-bit integer subtraction
    // result is intentionally narrowed to the counter width).
    localparam [$clog2(CLK_DIV)-1:0] HALF_DIV =
        ($clog2(CLK_DIV))'((CLK_DIV / 2) - 1);
    localparam [$clog2(CLK_DIV)-1:0] FULL_DIV =
        ($clog2(CLK_DIV))'(CLK_DIV - 1);

    // ── FSM state encoding ────────────────────────────────────
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] TRANSFER = 2'b01;
    localparam [1:0] FINISH   = 2'b10;

    // ── MISO 2-FF synchroniser ────────────────────────────────
    reg miso_s1, miso_s2;
    always @(posedge clk) begin
        if (reset) begin
            miso_s1 <= 1'b0;
            miso_s2 <= 1'b0;
        end else begin
            miso_s1 <= miso;
            miso_s2 <= miso_s1;
        end
    end

    // ── Clock divider ─────────────────────────────────────────
    always @(posedge clk) begin
        if (reset) begin
            clk_div <= {$clog2(CLK_DIV){1'b0}};
            sclk    <= CPOL[0];
        end else if (sclk_en) begin
            if (clk_div == FULL_DIV) begin
                clk_div <= {$clog2(CLK_DIV){1'b0}};
                sclk    <= ~sclk;
            end else begin
                clk_div <= clk_div + 1'b1;
                if (clk_div == HALF_DIV)
                    sclk <= ~sclk;
            end
        end else begin
            clk_div <= {$clog2(CLK_DIV){1'b0}};
            sclk    <= CPOL[0];
        end
    end

    // ── SCLK edge detect ─────────────────────────────────────
    always @(posedge clk) begin
        if (reset) sclk_d <= CPOL[0];
        else       sclk_d <= sclk;
    end

    wire sclk_rise =  sclk & ~sclk_d;
    wire sclk_fall = ~sclk &  sclk_d;

    wire sample_edge = (CPHA == 0) ? sclk_rise : sclk_fall;
    wire shift_edge  = (CPHA == 0) ? sclk_fall : sclk_rise;

    // ── Main FSM ──────────────────────────────────────────────
    always @(posedge clk) begin
        if (reset) begin
            state    <= IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            sclk_en  <= 1'b0;
            mosi     <= 1'b0;
            rx_data  <= {DATA_WIDTH{1'b0}};
            tx_shift <= {DATA_WIDTH{1'b0}};
            rx_shift <= {DATA_WIDTH{1'b0}};
            bit_cnt  <= {$clog2(DATA_WIDTH+1){1'b0}};
        end else begin
            case (state)

                IDLE: begin
                    done    <= 1'b0;
                    busy    <= 1'b0;
                    sclk_en <= 1'b0;
                    mosi    <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        sclk_en  <= 1'b1;
                        tx_shift <= tx_data;
                        rx_shift <= {DATA_WIDTH{1'b0}};
                        bit_cnt  <= ($clog2(DATA_WIDTH+1))'(DATA_WIDTH);
                        mosi     <= tx_data[DATA_WIDTH-1];
                        state    <= TRANSFER;
                    end
                end

                TRANSFER: begin
                    if (sample_edge)
                        rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso_s2};

                    if (shift_edge) begin
                        bit_cnt <= bit_cnt - 1'b1;
                        if (bit_cnt == 1) begin
                            sclk_en <= 1'b0;
                            state   <= FINISH;
                        end else begin
                            tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            mosi     <= tx_shift[DATA_WIDTH-2];
                        end
                    end
                end

                FINISH: begin
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    rx_data <= rx_shift;
                    mosi    <= 1'b0;
                    state   <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire

