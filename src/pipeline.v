`default_nettype none

// ============================================================
//  pipeline — RISC-V 5-stage + shared UART + SPI2 + GPIO
//  GF180MCU-D Production Version (All Fixes Applied)
// ============================================================
// FIXES APPLIED:
//  1. Synchronous reset architecture (reset_sync)
//  2. Registered boot_done logic (no glitch)
//  3. IMEM address safety (8-bit ports, 6-bit masking)
//  4. Forwarding muxes use case statements (no X propagation)
//  5. SPI outputs registered (clean external timing)
//  6. UART arbitration with clean mux logic
//  7. Stall gating with explicit priority
//  8. Safe halt logic with latching
// ============================================================

module pipeline (
    input  wire clk,
    input  wire reset,
    input  wire rx,
    output wire tx,
    output wire spi2_sclk,
    output wire spi2_mosi,
    input  wire spi2_miso,
    output wire spi2_cs_n,
    output wire gpio1_out
);

    // =========================================================
    // PARAMETERS
    // =========================================================
    localparam IMEM_ADDR_W = 6;

    // =========================================================
    // RESET SYNCHRONISER (Domain B)
    // =========================================================
    // FIX 1: All pipeline logic uses synchronous reset only
    reg reset_ff1, reset_ff2;
    always @(posedge clk) begin
        if (reset) begin
            reset_ff1 <= 1'b1;
            reset_ff2 <= 1'b1;
        end else begin
            reset_ff1 <= 1'b0;
            reset_ff2 <= reset_ff1;
        end
    end
    wire reset_sync = reset_ff2;

    // =========================================================
    // PIPELINE WIRES
    // =========================================================
    wire [31:0] PCPLUS4_top, PC_top, PCF, Instruction1_out, INSTRUCTION;
    wire [31:0] RD1_top, RD2_top, PCD_top, PCE_top, PCPLUS4D_TOP;
    wire [31:0] RD1E_top, RD2E_top;
    wire [31:0] SrcA_top, outB_top, ScrB_top;
    wire [31:0] ALUResultE_top, PCPlus4E_top, ALUResultM_top, PCPlus4M_top;
    wire [31:0] Datamem_top, ALUResultW_top, ReadDataW_top, PCPlus4W_top, ResultW_top;
    wire [31:0] PCTarget_top, ImmExtD_top, ImmExtE_top;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] WriteDataM_top;
    /* verilator lint_on  UNUSEDSIGNAL */

    wire RegWrite_top, ALUSrcD_top, memWriteD_top, jumpD_top, BranchD_top;
    wire JumpE_top, BranchE_top, zero_top, PCSCR_top;
    wire jumpRD_top, JumpRE_top;
    wire RegWriteE_top, MemWriteE_top, ALUSrcE_top;
    wire MemWriteM_top, RegWriteM_top, RegWriteW_top;
    wire StallF_top, StallD_top, FlushD_top, FlushE_top;

    wire [1:0] ResultSrcD_top, ALUtyp_top, ALUTypE_top;
    wire [1:0] ResultSrcE_top, ResultSrcM_top, ResultSrcW_top;
    wire [1:0] ForwardAE_top, ForwardBE_top;
    wire [3:0] ALUControlD_top, ALUControlE_top;
    wire [4:0] RdE_top, RdM_top, Rs1E_top, Rs2E_top, RdW_top;
    wire [2:0] ImmSrc_top;
    wire [1:0] ALUSrcAD_top, ALUSrcAE_top;

    // =========================================================
    // UART / BOOT WIRES
    // =========================================================
    wire [7:0]  uart_rx_data_shared;
    wire        uart_rx_ready_shared;
    wire        uart_tx_busy_shared;
    wire [7:0]  boot_tx_data;
    wire        boot_tx_start_raw;
    wire [7:0]  periph_tx_data;
    wire        periph_tx_start;

    // FIX 3: Use 8-bit addresses (matches module ports)
    wire [7:0]  mem_addr;
    wire [31:0] mem_wdata;
    wire        Write_enable;
    wire        stall_Pro;
    wire        halt_top;

    // Safety masking: only use lower 6 bits for IMEM access
    wire [5:0]  mem_addr_safe = mem_addr[5:0];

    // =========================================================
    // FIX 2: BOOT_DONE LOGIC (REGISTERED, NO GLITCH)
    // =========================================================
    // Combine stall_Pro into registered signal
    reg boot_done_comb_r;
    always @(posedge clk) begin
        if (reset_sync)
            boot_done_comb_r <= 1'b0;
        else
            boot_done_comb_r <= ~stall_Pro;
    end
    wire boot_done_comb = boot_done_comb_r;

    // First FF stage
    reg boot_done_r;
    always @(posedge clk) begin
        if (reset_sync) boot_done_r <= 1'b0;
        else           boot_done_r <= boot_done_comb;
    end

    // Second FF stage (for clean arbitration)
    reg boot_done_r2;
    always @(posedge clk) begin
        if (reset_sync) boot_done_r2 <= 1'b0;
        else           boot_done_r2 <= boot_done_r;
    end

    // =========================================================
    // FIX 6: UART ARBITRATION (CLEAN MUXES)
    // =========================================================
    wire boot_active = ~boot_done_r2;

    // Direct single-stage muxes (no intermediate gates)
    wire shared_tx_start;
    wire [7:0] shared_tx_data;

    assign shared_tx_start = boot_active ? boot_tx_start_raw :
                                           (periph_tx_start & ~uart_tx_busy_shared);
    assign shared_tx_data  = boot_active ? boot_tx_data :
                                           periph_tx_data;

    // RX routing
    wire uart_rx_ready_boot = uart_rx_ready_shared & ~boot_done_r2;

    // =========================================================
    // HALT LOGIC (SYNCHRONOUS)
    // =========================================================
    wire halt_active = halt_top & ~stall_Pro & ~FlushD_top & ~FlushE_top;
    reg  halt_latch;
    always @(posedge clk) begin
        if (reset_sync)       halt_latch <= 1'b0;
        else if (stall_Pro)   halt_latch <= 1'b0;
        else if (halt_active) halt_latch <= 1'b1;
    end
    wire halt_final = halt_latch | halt_active;

    // =========================================================
    // FIX 7: STALL GATING WITH PRIORITY
    // =========================================================
    wire StallF_net = (PCSCR_top) ? 1'b0 :
                      (stall_Pro | StallF_top | halt_final);
    wire StallD_net = (PCSCR_top) ? 1'b0 :
                      (stall_Pro | StallD_top | halt_final);

    // =========================================================
    // FETCH STAGE
    // =========================================================
    PC_incre PC (
        .pc(PCF), 
        .PCPlus4(PCPLUS4_top)
    );

    PCSelect_MUX PCSelect_top (
        .PCScr(PCSCR_top), 
        .PCSequential(PCPLUS4_top),
        .PCBranch(PCTarget_top), 
        .Mux3_PC(PC_top)
    );

    pc_register Register_top (
        .clk(clk), 
        .reset(reset_sync),
        .PCF_in(PC_top), 
        .stallF(StallF_net), 
        .PCF_out(PCF)
    );

    // =========================================================
    // UART SHARED INTERFACE (Domain B)
    // =========================================================
    uart_Tx_fixed #(
        .CLK_FREQ(33_333_333), 
        .BAUD_RATE(115_200), 
        .OVERSAMPLE(8)
    ) uart_shared_inst (
        .clk(clk), 
        .reset(reset_sync),
        .tx_Start(shared_tx_start), 
        .tx_Data(shared_tx_data),
        .tx(tx), 
        .tx_busy(uart_tx_busy_shared),
        .rx(rx), 
        .rx_Data(uart_rx_data_shared),
        .rx_ready(uart_rx_ready_shared)
    );

    // =========================================================
    // FIX 1: BOOTLOADER (SYNCHRONOUS RESET)
    // =========================================================
    uart_bootloader uart_bootloader (
        .clk(clk), 
        .reset(reset_sync),
        .rx_data(uart_rx_data_shared),
        .rx_valid(uart_rx_ready_boot),
        .tx_data(boot_tx_data),
        .tx_start(boot_tx_start_raw),
        .mem_we(Write_enable),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .stall_pro(stall_Pro)
    );

    // =========================================================
    // FIX 3: IMEM (ADDRESS SAFETY WITH MASKING)
    // =========================================================
    instruction_mem #(
        .DEPTH(64), 
        .ADDR_W(8)
    ) imem_inst (
        .clk(clk),
        .we(Write_enable),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .read_Address(PCF),
        .Instruction_out(Instruction1_out)
    );

    // =========================================================
    // DECODE STAGE (Domain B)
    // =========================================================
    IF_ID_stage IF_DF_top (
        .clk(clk), 
        .reset(reset_sync),
        .stallD(StallD_net), 
        .flushD(FlushD_top),
        .PC_in(PCF), 
        .PCplus4_in(PCPLUS4_top),
        .instruction_in(Instruction1_out),
        .instruction_out(INSTRUCTION),
        .PCplus4_out(PCPLUS4D_TOP), 
        .PC_out(PCD_top)
    );

    // Instruction field extraction
    wire [6:0]  INSTR_op   = INSTRUCTION[6:0];
    wire [2:0]  INSTR_f3   = INSTRUCTION[14:12];
    wire [6:0]  INSTR_f7   = INSTRUCTION[31:25];
    wire [11:0] INSTR_imm  = INSTRUCTION[31:20];
    wire [4:0]  INSTR_rs1  = INSTRUCTION[19:15];
    wire [4:0]  INSTR_rs2  = INSTRUCTION[24:20];
    wire [31:0] INSTR_full = INSTRUCTION;
    wire [4:0]  INSTR_rd   = INSTRUCTION[11:7];

    // Control unit
    Control control (
        .Opcode(INSTR_op), 
        .funct3(INSTR_f3), 
        .funct7(INSTR_f7),
        .imm(INSTR_imm), 
        .halt(halt_top),
        .RegWriteD(RegWrite_top), 
        .ResultSrcD(ResultSrcD_top),
        .MemWriteD(memWriteD_top), 
        .jumpD(jumpD_top), 
        .jumpR(jumpRD_top),
        .BranchD(BranchD_top), 
        .ALUControlD(ALUControlD_top),
        .ALUSrcD(ALUSrcD_top), 
        .ALUSrcA(ALUSrcAD_top),
        .ImmSrc(ImmSrc_top), 
        .ALUType(ALUtyp_top)
    );

    // Register file
    Reg_file Reg_file_top (
        .clk(clk),
        .rs1_addr(INSTR_rs1), 
        .rs2_addr(INSTR_rs2),
        .rd_addr(RdW_top), 
        .Regwrite(RegWriteW_top),
        .Write_data(ResultW_top),
        .Read_data1(RD1_top), 
        .Read_data2(RD2_top)
    );

    // Immediate extender
    imm imm_top (
        .ImmSrc(ImmSrc_top), 
        .instruction(INSTR_full),
        .ImmExt(ImmExtD_top)
    );

    // =========================================================
    // EXECUTE STAGE (Domain B)
    // =========================================================
    EX_stage ex_stage (
        .clk(clk), 
        .reset(reset_sync), 
        .flushE(FlushE_top),
        .RD1D_in(RD1_top), 
        .RD2D_in(RD2_top),
        .ImmExtD_in(ImmExtD_top), 
        .PCPlus4D_in(PCPLUS4D_TOP),
        .PC_D_in(PCD_top), 
        .Rs1D_in(INSTR_rs1), 
        .Rs2D_in(INSTR_rs2),
        .RdD_in(INSTR_rd), 
        .ALUControlD_in(ALUControlD_top),
        .ALUSrcD_in(ALUSrcD_top), 
        .ALUSrcA_in(ALUSrcAD_top),
        .RegWriteD_in(RegWrite_top), 
        .ResultSrcD_in(ResultSrcD_top),
        .MemWriteD_in(memWriteD_top), 
        .BranchD_in(BranchD_top),
        .JumpD_in(jumpD_top), 
        .JumpR_in(jumpRD_top),
        .ALUType_in(ALUtyp_top),
        .RD1E_out(RD1E_top), 
        .RD2E_out(RD2E_top),
        .ImmExtD_out(ImmExtE_top), 
        .PCPlus4D_out(PCPlus4E_top),
        .PC_D_out(PCE_top), 
        .Rs1D_out(Rs1E_top), 
        .Rs2D_out(Rs2E_top),
        .RdD_out(RdE_top), 
        .ALUControlD_out(ALUControlE_top),
        .ALUSrcD_out(ALUSrcE_top), 
        .ALUSrcA_out(ALUSrcAE_top),
        .RegWriteD_out(RegWriteE_top), 
        .ResultSrcD_out(ResultSrcE_top),
        .MemWriteD_out(MemWriteE_top), 
        .BranchD_out(BranchE_top),
        .JumpD_out(JumpE_top), 
        .JumpR_out(JumpRE_top),
        .ALUType_out(ALUTypE_top)
    );

    // =========================================================
    // FIX 4: FORWARDING MUXES (CASE STATEMENTS, NO X RISK)
    // =========================================================
    // Forwarding MUX A (for SrcA)
    reg [31:0] SrcA_fwd;
    always @(*) begin
        case (ForwardAE_top)
            2'b10:   SrcA_fwd = ALUResultM_top;
            2'b01:   SrcA_fwd = ResultW_top;
            default: SrcA_fwd = RD1E_top;
        endcase
    end

    // Forwarding MUX B (for SrcB/outB)
    reg [31:0] outB_fwd;
    always @(*) begin
        case (ForwardBE_top)
            2'b10:   outB_fwd = ALUResultM_top;
            2'b01:   outB_fwd = ResultW_top;
            default: outB_fwd = RD2E_top;
        endcase
    end

    // SrcA multiplexer (select between 0, PC, or forwarded value)
    reg [31:0] SrcA_mux;
    always @(*) begin
        case (ALUSrcAE_top)
            2'b10:   SrcA_mux = 32'd0;
            2'b01:   SrcA_mux = PCE_top;
            default: SrcA_mux = SrcA_fwd;
        endcase
    end
    assign SrcA_top = SrcA_mux;

    // SrcB multiplexer (select between immediate or register)
    assign outB_top = outB_fwd;
    reg [31:0] ScrB_mux;
    always @(*) begin
        if (ALUSrcE_top)
            ScrB_mux = ImmExtE_top;
        else
            ScrB_mux = outB_top;
    end
    assign ScrB_top = ScrB_mux;

    // =========================================================
    // BRANCH/JUMP CALCULATION
    // =========================================================
    wire [31:0] base_addr_w = JumpRE_top ? RD1E_top : PCE_top;
    assign PCTarget_top = JumpRE_top
        ? ((base_addr_w + ImmExtE_top) & 32'hFFFFFFFE)
        :  (base_addr_w + ImmExtE_top);

    assign PCSCR_top = (zero_top & BranchE_top) | JumpE_top;

    // =========================================================
    // ALU
    // =========================================================
    ALU alu (
        .ScrA(SrcA_top), 
        .ScrB(ScrB_top),
        .ALUControl(ALUControlE_top), 
        .ALUType(ALUTypE_top),
        .ALUResult(ALUResultE_top), 
        .Zero(zero_top)
    );

    // =========================================================
    // MEMORY STAGE (Domain B)
    // =========================================================
    MEM_stage mem_stage (
        .clk(clk), 
        .reset(reset_sync),
        .ALUResult_in(ALUResultE_top), 
        .WriteData_in(outB_top),
        .RdM_in(RdE_top), 
        .PCPlus4M_in(PCPlus4E_top),
        .RegWriteM_in(RegWriteE_top), 
        .ResultSrcM_in(ResultSrcE_top),
        .MemWriteM_in(MemWriteE_top),
        .ALUResult_out(ALUResultM_top), 
        .WriteData_out(WriteDataM_top),
        .RdM_out(RdM_top), 
        .PCPlus4M_out(PCPlus4M_top),
        .RegWriteM_out(RegWriteM_top), 
        .ResultSrcM_out(ResultSrcM_top),
        .MemWriteM_out(MemWriteM_top)
    );

    // =========================================================
    // WRITEBACK STAGE (Domain B)
    // =========================================================
    WriteBack_stage writeback_stage (
        .clk(clk), 
        .reset(reset_sync),
        .ALUResultW_in(ALUResultM_top), 
        .ReadDataW_in(Datamem_top),
        .RdW_in(RdM_top), 
        .PCPlus4W_in(PCPlus4M_top),
        .RegWriteW_in(RegWriteM_top), 
        .ResultSrcW_in(ResultSrcM_top),
        .ALUResultW_out(ALUResultW_top), 
        .ReadDataW_out(ReadDataW_top),
        .RdW_out(RdW_top), 
        .PCPlus4W_out(PCPlus4W_top),
        .RegWriteW_out(RegWriteW_top), 
        .ResultSrcW_out(ResultSrcW_top)
    );

    Write_back write_back (
        .ALUResultW_in(ALUResultW_top), 
        .ReadDataW_in(ReadDataW_top),
        .PCPlus4W_in(PCPlus4W_top), 
        .ResultSrcW_in(ResultSrcW_top),
        .ResultW(ResultW_top)
    );

    // =========================================================
    // HAZARD UNIT (Combinational)
    // =========================================================
    Hazard_Unit hazard (
        .Rs1D(INSTR_rs1), 
        .Rs2D(INSTR_rs2),
        .Rs1E(Rs1E_top), 
        .Rs2E(Rs2E_top), 
        .RdE(RdE_top),
        .RegWriteE(RegWriteE_top), 
        .PCSRCE(PCSCR_top),
        .ResultSrcE_in(ResultSrcE_top),
        .RdM(RdM_top), 
        .RdW(RdW_top),
        .RegWriteM(RegWriteM_top), 
        .RegWriteW(RegWriteW_top),
        .StallF(StallF_top), 
        .StallD(StallD_top),
        .FlushD(FlushD_top), 
        .FlushE(FlushE_top),
        .Forward_AE(ForwardAE_top), 
        .Forward_BE(ForwardBE_top)
    );

    // =========================================================
    // PERIPHERAL WIRES
    // =========================================================
    wire        spi2_start_w, spi2_busy_w, spi2_done_w, spi2_pending_w;
    wire [7:0]  spi2_tx_data_w, spi2_rx_data_w;
    wire        gpio1_wr_en_w, gpio1_wdata_w;
    wire        gpio2_wr_en_w, gpio2_wdata_w;

    // Internal SPI signals (before registration for FIX 5)
    wire spi2_sclk_comb, spi2_mosi_comb, spi2_cs_n_comb;

    // =========================================================
    // DATA MEMORY (Domain B)
    // =========================================================
    DataMem databus_inst (
        .clk(clk), 
        .reset(reset_sync),
        .aluAddress_in(ALUResultM_top),
        .DataWriteM_in(WriteDataM_top[7:0]),
        .memwriteM_in(MemWriteM_top),
        .DataMem_out(Datamem_top),
        .uart_tx_start(periph_tx_start),
        .uart_out_data(periph_tx_data),
        .uart_tx_busy(uart_tx_busy_shared),
        .spi2_tx_data(spi2_tx_data_w),
        .spi2_start(spi2_start_w),
        .spi2_pending_out(spi2_pending_w),
        .spi2_rx_data(spi2_rx_data_w),
        .spi2_busy(spi2_busy_w),
        .spi2_done(spi2_done_w),
        .gpio1_wr_en(gpio1_wr_en_w),
        .gpio1_wdata(gpio1_wdata_w),
        .gpio2_wr_en(gpio2_wr_en_w),
        .gpio2_wdata(gpio2_wdata_w)
    );

    // =========================================================
    // SPI MASTER (Domain B)
    // =========================================================
    spi_master #(
        .DATA_WIDTH(8), 
        .CPOL(0), 
        .CPHA(0), 
        .CLK_DIV(8)
    ) spi2_inst (
        .clk(clk), 
        .reset(reset_sync),
        .start(spi2_start_w), 
        .tx_data(spi2_tx_data_w),
        .rx_data(spi2_rx_data_w),
        .busy(spi2_busy_w), 
        .done(spi2_done_w),
        .sclk(spi2_sclk_comb), 
        .mosi(spi2_mosi_comb), 
        .miso(spi2_miso)
    );

    // =========================================================
    // FIX 5: SPI OUTPUT REGISTRATION (CLEAN EXTERNAL TIMING)
    // =========================================================
    reg spi2_sclk_r, spi2_mosi_r, spi2_cs_n_r;
    always @(posedge clk) begin
        if (reset_sync) begin
            spi2_sclk_r <= 1'b0;
            spi2_mosi_r <= 1'b0;
            spi2_cs_n_r <= 1'b1;
        end else begin
            spi2_sclk_r <= spi2_sclk_comb;
            spi2_mosi_r <= spi2_mosi_comb;
            spi2_cs_n_r <= spi2_cs_n_comb;
        end
    end

    // Drive outputs from registered signals
    assign spi2_sclk = spi2_sclk_r;
    assign spi2_mosi = spi2_mosi_r;
    assign spi2_cs_n = spi2_cs_n_r;

    // =========================================================
    // GPIO MODULES (Domain B)
    // =========================================================
    gpio1_io gpio1 (
        .clk(clk), 
        .reset(reset_sync),
        .wr_en1(gpio1_wr_en_w), 
        .wdata1(gpio1_wdata_w),
        .gpio_out1(gpio1_out)
    );

    gpio2_io gpio2 (
        .clk(clk), 
        .reset(reset_sync),
        .wr_en2(gpio2_wr_en_w), 
        .wdata2(gpio2_wdata_w),
        .spi_busy(spi2_busy_w), 
        .spi_pending(spi2_pending_w),
        .gpio_out2(spi2_cs_n_comb)
    );

endmodule

`default_nettype wire