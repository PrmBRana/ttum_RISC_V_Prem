`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  uart_Tx_fixed.v — Shared UART (TX + RX, oversampled x16)
//
//  FIXES applied in this version:
//
//  WARN 1 FIXED: baud_tick_tx and baud_tick_rx were identical
//    registered copies of baud_tick — wasting 2 DFFs and routing
//    budget on GF180MCU for no benefit. Replaced with a single
//    registered copy baud_tick_r used by both FSMs.
//
//  WARN 2 FIXED: tx_Data was sampled inside TX_IDLE state, one
//    full baud_tick cycle after tx_pending was set. If the CPU
//    changed tx_Data between those two cycles, the wrong byte
//    was transmitted. tx_Data is now captured into tx_latch_reg
//    in the same cycle tx_pending is set (in the tx_pending
//    always block), so the TX FSM always sees stable data
//    regardless of when it actually enters TX_START.
//
//  Existing fix retained: RX majority vote uses one_counts_next
//    which includes the current sample, giving a correct 16-
//    sample vote rather than the previous 15-sample vote.
// ============================================================

module uart_Tx_fixed #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter OVERSAMPLE = 16
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_Start,
    input  wire [7:0] tx_Data,
    output reg        tx,
    output wire       tx_busy,
    input  wire       rx,
    output reg  [7:0] rx_Data,
    output reg        rx_ready
);

    // ── RX synchronizer ──────────────────────────────────────
    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        if (reset) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= rx;
            rx_s2 <= rx_s1;
        end
    end

    // ── Baud generator ───────────────────────────────────────
    localparam integer BAUD_DIV     = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNT_WIDTH    = $clog2(BAUD_DIV);
    localparam integer BAUD_LAST_32 = BAUD_DIV - 1;
    localparam [CNT_WIDTH-1:0] BAUD_LAST = BAUD_LAST_32[CNT_WIDTH-1:0];
    localparam integer OS_LAST_32   = OVERSAMPLE - 1;
    localparam [3:0]   OS_LAST      = OS_LAST_32[3:0];

    // Majority threshold: >=8 out of 16 samples
    localparam integer RX_MAJ = OVERSAMPLE / 2;

    reg [CNT_WIDTH-1:0] baud_cnt;
    reg                 baud_tick;

    always @(posedge clk) begin
        if (reset) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == BAUD_LAST) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1'b1;
            baud_tick <= 1'b0;
        end
    end

    // ── FIX WARN 1: single registered baud tick copy ─────────
    // Both TX and RX FSMs now share baud_tick_r.
    // Previously two identical copies (baud_tick_tx, baud_tick_rx)
    // were registered — wasting 2 DFFs on GF180MCU for no benefit.
    reg baud_tick_r;
    always @(posedge clk) begin
        if (reset)
            baud_tick_r <= 1'b0;
        else
            baud_tick_r <= baud_tick;
    end

    // ── TX FSM ───────────────────────────────────────────────
    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [7:0] tx_shift_reg;
    reg [7:0] tx_latch_reg;   // FIX WARN 2: data captured at pending-set time
    reg [2:0] tx_bit_cnt;
    reg [3:0] tx_oversample_cnt;
    reg       tx_pending;

    wire tx_active = (tx_state != TX_IDLE) || tx_pending;
    reg  tx_hold0, tx_hold1;
    always @(posedge clk) begin
        if (reset) begin
            tx_hold0 <= 1'b0;
            tx_hold1 <= 1'b0;
        end else begin
            tx_hold0 <= tx_active;
            tx_hold1 <= tx_hold0;
        end
    end
    assign tx_busy = tx_active | tx_hold0 | tx_hold1;

    // ── FIX WARN 2: capture tx_Data when tx_pending is set ───
    // Previously tx_Data was read inside TX_IDLE (one baud_tick
    // later). If the CPU changed tx_Data in between, the wrong
    // byte was sent. Latching here guarantees stable data for
    // the FSM regardless of when it fires.
    always @(posedge clk) begin
        if (reset) begin
            tx_pending   <= 1'b0;
            tx_latch_reg <= 8'd0;
        end else begin
            if (tx_Start) begin
                tx_pending   <= 1'b1;
                tx_latch_reg <= tx_Data;   // FIX: capture data immediately
            end else if (tx_state == TX_START && baud_tick_r) begin
                tx_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            tx                <= 1'b1;
            tx_state          <= TX_IDLE;
            tx_shift_reg      <= 8'd0;
            tx_bit_cnt        <= 3'd0;
            tx_oversample_cnt <= 4'd0;
        end else if (baud_tick_r) begin
            case (tx_state)
                TX_IDLE: begin
                    tx                <= 1'b1;
                    tx_oversample_cnt <= 4'd0;
                    if (tx_pending) begin
                        tx_shift_reg <= tx_latch_reg;  // FIX: use latched data
                        tx_state     <= TX_START;
                    end
                end
                TX_START: begin
                    tx <= 1'b0;
                    if (tx_oversample_cnt == OS_LAST) begin
                        tx_state          <= TX_DATA;
                        tx_bit_cnt        <= 3'd0;
                        tx_oversample_cnt <= 4'd0;
                    end else
                        tx_oversample_cnt <= tx_oversample_cnt + 1'b1;
                end
                TX_DATA: begin
                    tx <= tx_shift_reg[tx_bit_cnt];
                    if (tx_oversample_cnt == OS_LAST) begin
                        tx_oversample_cnt <= 4'd0;
                        if (tx_bit_cnt == 3'd7)
                            tx_state   <= TX_STOP;
                        else
                            tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    end else
                        tx_oversample_cnt <= tx_oversample_cnt + 1'b1;
                end
                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_oversample_cnt == OS_LAST) begin
                        tx_state          <= TX_IDLE;
                        tx_oversample_cnt <= 4'd0;
                    end else
                        tx_oversample_cnt <= tx_oversample_cnt + 1'b1;
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ── RX FSM ───────────────────────────────────────────────
    // Majority vote uses one_counts_next which includes the
    // current sample — correct 16-sample vote (existing fix).
    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    reg [1:0] rx_state;
    reg [7:0] rx_shift_reg;
    reg [2:0] rx_bit_cnt;
    reg [3:0] rx_sample_cnt;

    // one_counts is 5 bits to safely hold 0..16
    reg [4:0] one_counts;

    wire [4:0] one_counts_next_start = one_counts + {4'd0, ~rx_s2};
    wire [4:0] one_counts_next_data  = one_counts + {4'd0,  rx_s2};
    wire [4:0] one_counts_next_stop  = one_counts + {4'd0,  rx_s2};

    always @(posedge clk) begin
        if (reset) begin
            rx_state      <= RX_IDLE;
            rx_shift_reg  <= 8'd0;
            rx_bit_cnt    <= 3'd0;
            rx_sample_cnt <= 4'd0;
            one_counts    <= 5'd0;
            rx_Data       <= 8'd0;
            rx_ready      <= 1'b0;
        end else if (baud_tick_r) begin
            case (rx_state)

                RX_IDLE: begin
                    rx_ready      <= 1'b0;
                    rx_sample_cnt <= 4'd0;
                    one_counts    <= 5'd0;
                    if (!rx_s2)
                        rx_state <= RX_START;
                end

                RX_START: begin
                    one_counts <= one_counts_next_start;
                    if (rx_sample_cnt == OS_LAST) begin
                        if (one_counts_next_start >= RX_MAJ[4:0])
                            rx_state  <= RX_DATA;
                        else
                            rx_state  <= RX_IDLE;
                        rx_sample_cnt <= 4'd0;
                        one_counts    <= 5'd0;
                        rx_bit_cnt    <= 3'd0;
                    end else begin
                        rx_sample_cnt <= rx_sample_cnt + 1'b1;
                    end
                end

                RX_DATA: begin
                    one_counts <= one_counts_next_data;
                    if (rx_sample_cnt == OS_LAST) begin
                        rx_shift_reg  <= {(one_counts_next_data >= RX_MAJ[4:0]),
                                           rx_shift_reg[7:1]};
                        rx_sample_cnt <= 4'd0;
                        one_counts    <= 5'd0;
                        if (rx_bit_cnt == 3'd7)
                            rx_state  <= RX_STOP;
                        else
                            rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    end else begin
                        rx_sample_cnt <= rx_sample_cnt + 1'b1;
                    end
                end

                RX_STOP: begin
                    one_counts <= one_counts_next_stop;
                    if (rx_sample_cnt == OS_LAST) begin
                        if (one_counts_next_stop >= RX_MAJ[4:0]) begin
                            rx_Data  <= rx_shift_reg;
                            rx_ready <= 1'b1;
                        end
                        rx_state      <= RX_IDLE;
                        rx_sample_cnt <= 4'd0;
                        one_counts    <= 5'd0;
                    end else begin
                        rx_sample_cnt <= rx_sample_cnt + 1'b1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule







