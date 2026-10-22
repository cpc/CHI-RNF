// cva6_chi_fpga_top.sv — board-level top for the VCU118 prototype.
//
// Brings up:
//   - clk_wiz_0           : 156.25 MHz LVDS → 50 MHz CHI/CVA6 clock
//   - reset synchroniser  : push-button rst, sync-deasserted
//   - cva6_debug_subsystem: PMOD JTAG → dmi_jtag → dm_top → debug_req[NUM_RNFS]
//   - rnf_wrapper         : NUM_RNFS × {CVA6 + L1.5 + rnf_link}
//   - chi_icn_mesh        : 2×2 OpenNoC; mesh slots [NUM_RNFS..CORE_COUNT-1]
//                           are tied off when NUM_RNFS < CORE_COUNT
//   - hnf                 : RTL HN-F (L3 + snoop filter)
//   - snf                 : raw SN-F; AXI master exposed at the top for MIG
//
// Multi-hart JTAG topology: one physical TAP (PMOD1) → one dmi_jtag → one
// dm_top with NrHarts=NUM_RNFS.  OpenOCD selects a hart via the DM's
// `hartsel` register (OpenOCD `targets <n>` / `targets <name>` command).
//
// Notes:
//   * MIG/DDR4 hookup is pending; the SN-F AXI master comes out at top level.
//   * UART is stubbed (user direction: not critical now).

`include "chie_defines.v"
`include "hnf_param.v"
`include "snf_param.v"

module cva6_chi_fpga_top #(
    // Number of RN-Fs (CVA6 cores) instantiated.  Bounded by the mesh's
    // CORE_COUNT (= 2 with the 2×2 mesh_wrapper_2x2).  All RN-Fs share a
    // single JTAG TAP and a single dm_top with NrHarts=NUM_RNFS; the host
    // selects which hart to drive via the DM's `hartsel` register.
    parameter int NUM_RNFS = 1
) (
    // ── System clock + reset (matches openpiton VCU118 XDC) ─────────────────
    input  wire        sys_clk_p,    // 156.25 MHz LVDS DIFF_SSTL12 @ F31/G31
    input  wire        sys_clk_n,
    input  wire        sys_rst_n,    // active-HIGH push button (despite name)

    // ── JTAG TAP for RISC-V Debug Module (PMOD1 / J53) ──────────────────────
    input  wire        tck_i,
    input  wire        tms_i,
    input  wire        td_i,
    output wire        td_o,
    input  wire        trst_ni,

    // ── SN-F AXI master ─ destined for MIG/DDR4 (kept at top until MIG wired) ─
    // Bit-widths follow the snf parameter pass-through below
    // (AXI4_AXDATA_WIDTH_PARAM=128, AXI4_PA_WIDTH_PARAM=44; ID is hardcoded 11).
    output wire [10:0] snf_axi_ar_id,
    output wire [43:0] snf_axi_ar_addr,
    output wire  [7:0] snf_axi_ar_len,
    output wire  [2:0] snf_axi_ar_size,
    output wire  [1:0] snf_axi_ar_burst,
    output wire        snf_axi_ar_lock,
    output wire  [3:0] snf_axi_ar_cache,
    output wire  [2:0] snf_axi_ar_prot,
    output wire  [3:0] snf_axi_ar_qos,
    output wire  [3:0] snf_axi_ar_region,
    output wire        snf_axi_ar_valid,
    input  wire        snf_axi_ar_ready,
    input  wire [10:0] snf_axi_r_id,
    input  wire [127:0] snf_axi_r_data,
    input  wire  [1:0] snf_axi_r_resp,
    input  wire        snf_axi_r_last,
    input  wire        snf_axi_r_valid,
    output wire        snf_axi_r_ready,
    output wire [10:0] snf_axi_aw_id,
    output wire [43:0] snf_axi_aw_addr,
    output wire  [7:0] snf_axi_aw_len,
    output wire  [2:0] snf_axi_aw_size,
    output wire  [1:0] snf_axi_aw_burst,
    output wire        snf_axi_aw_lock,
    output wire  [3:0] snf_axi_aw_cache,
    output wire  [2:0] snf_axi_aw_prot,
    output wire  [3:0] snf_axi_aw_qos,
    output wire  [3:0] snf_axi_aw_region,
    output wire        snf_axi_aw_valid,
    input  wire        snf_axi_aw_ready,
    output wire [127:0] snf_axi_w_data,
    output wire [15:0] snf_axi_w_strb,
    output wire        snf_axi_w_last,
    output wire        snf_axi_w_valid,
    input  wire        snf_axi_w_ready,
    input  wire [10:0] snf_axi_b_id,
    input  wire  [1:0] snf_axi_b_resp,
    input  wire        snf_axi_b_valid,
    output wire        snf_axi_b_ready,

    // ── Status LEDs ─────────────────────────────────────────────────────────
    output wire  [7:0] leds
);

    // ════════════════════════════════════════════════════════════════════════
    // ── CHI parameter block (mirrors tlm_rnf_hnf_tb's mesh+memss config) ────
    // ════════════════════════════════════════════════════════════════════════
    localparam int CORE_COUNT                       = 2;   // 2-slot mesh, RNF[1] tied
    localparam int CHIE_REQ_ADDR_WIDTH_PARAM        = 44;
    localparam int CHIE_SNP_ADDR_WIDTH_PARAM        = 41;
    localparam int CHIE_NID_WIDTH_PARAM             = 7;
    localparam int CHIE_DATA_WIDTH_PARAM            = 256;
    localparam int CHIE_BE_WIDTH_PARAM              = 32;
    localparam int CHIE_DATACHECK_WIDTH_PARAM       = 0;
    localparam int CHIE_POISON_WIDTH_PARAM          = 0;
    localparam int CHIE_REQ_RSVDC_WIDTH_PARAM       = 0;
    localparam int CHIE_DAT_RSVDC_WIDTH_PARAM       = 0;
    localparam int HNF_MSHR_RNF_NUM_PARAM           = 4;
    localparam int HNF_MSHR_RNI_NUM_PARAM           = 0;
    // Pad unused slots with reserved NIDs (127, 126) so the HN-F's NID-lookup
    // doesn't self-match the requester via zero-padded entries.  See
    // tlm_rnf_hnf_tb.sv for the matching testbench-side override.
    localparam     RNF_NID_LIST_PARAM               = {7'd127, 7'd126, 7'd1, 7'd0};
    localparam     RNI_NID_LIST_PARAM               = {7'd64};
    // Mesh NID encoding = {X[2:0], Y[2:0], port[0]}.
    localparam int HNF_NID_PARAM                    = 16;  // XP(1,0)/P0
    localparam int SNF_NID_PARAM                    = 18;  // XP(1,1)/P0
    localparam int XP_LCRD_NUM_PARAM                = 15;
    // ── FPGA-sized HN-F caches ──────────────────────────────────────────────
    // The simulation defaults (L3 = 4 MB, SF = 131072 × 16) blow up to
    // ~620k SLICEM LUTs of distributed RAM on this device because the
    // OpenNoC SRAMs use async read (data_out = mem[addr]), which Vivado
    // can't map to BRAM.  Shrinking to bring-up-friendly sizes keeps the
    // design well inside the device while we evaluate the upstream
    // HNF_DELAY_ONE_CYCLE path (see HNF_USE_BRAM in scripts/settings.tcl).
    localparam int HNF_SF_ENTRIES_NUM_PARAM         = 1024;     // was 131072
    localparam int HNF_SF_WAY_NUM_PARAM             = 4;        // was 16
    localparam int HNF_MSHR_EXCL_RN_NUM_PARAM       = 32;
    localparam int HNF_MSHR_EXCL_RN_WIDTH_PARAM     = 5;
    localparam int HNF_MSHR_ENTRIES_NUM_PARAM       = 32;
    localparam int HNF_MSHR_ENTRIES_WIDTH_PARAM     = 5;
    localparam int HNF_L3_CACHE_SIZE_PARAM          = 64;       // KB; was 4096
    localparam int HNF_L3_WAY_NUM_PARAM             = 4;        // was 16

    // SN-F AXI master dimensions (passed to snf #(...) below; port widths in
    // the module header must match these).
    //
    // AXI4_AXDATA_WIDTH=128 (NOT 256): snf_data_buffer.v:573-578 has a
    // ternary that picks between 128-bit and wide AXI paths.  The "wide"
    // branch part-selects dbf_data_q[entry][2*AXI4_WDATA_WIDTH +: ...]
    // which exceeds dbf_data_q's 512-bit declared width whenever AXI is
    // > 128b.  Vivado statically elaborates both branches and errors out
    // (Synth 8-524) even though that branch is unreachable.  Forcing 128b
    // keeps everything inside the buffer; MIG just transfers 2 AXI beats
    // per CHI cache line.
    //
    // AXI4_PA_WIDTH=CHIE_REQ_ADDR_WIDTH=44: snf_mshr.v:567-579 part-selects
    // the CHI-sized rxreq_addr_s0 (44b) at [AXI4_AXADDR_WIDTH-1:6].  If
    // AXI addr were 64b, that becomes [63:6] -- out of range on the 44b
    // signal.  Matching the two widths keeps the part-selects valid; the
    // MIG bridge (future) zero-extends 44b -> the MIG-required width.
    localparam int AXI_DATA_WIDTH                   = 128;
    localparam int AXI_ADDR_WIDTH                   = 44;

    // ════════════════════════════════════════════════════════════════════════
    // ── 1. Clock + reset generation ─────────────────────────────────────────
    // ════════════════════════════════════════════════════════════════════════
    wire clk_sys;       // 50 MHz CHI/CVA6 clock
    wire clk_ddr_ref;   // 200 MHz DDR4 IO ref (unused until MIG hooks up)
    wire pll_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1_p (sys_clk_p),
        .clk_in1_n (sys_clk_n),
        .clk_out1  (clk_sys),
        .clk_out2  (clk_ddr_ref),
        // clk_wiz_0 is configured with RESET_TYPE=ACTIVE_HIGH; the port is
        // named `reset`.  sys_rst_n on VCU118 is active-HIGH (board labels
        // it CPU_RESET — the `_n` suffix is misleading), so feed directly.
        .reset     (sys_rst_n),
        .locked    (pll_locked)
    );

    // Synchronously-deasserted, asynchronously-asserted reset.
    // Note: `sys_rst_n` pin is *active-HIGH* on VCU118 (board labels it CPU_RESET).
    logic [3:0] rst_sync_q;
    wire        rst_async = ~pll_locked | sys_rst_n;
    always_ff @(posedge clk_sys or posedge rst_async) begin
        if (rst_async) rst_sync_q <= 4'b0000;
        else           rst_sync_q <= {rst_sync_q[2:0], 1'b1};
    end
    wire rst_n = rst_sync_q[3];
    wire rst   = ~rst_n;

    // ════════════════════════════════════════════════════════════════════════
    // ── 2. RISC-V Debug subsystem (PMOD JTAG → dmi_jtag → dm_top) ───────────
    // ════════════════════════════════════════════════════════════════════════
    wire                  ndmreset;
    wire                  dmactive;
    wire [NUM_RNFS-1:0]   debug_req;     // one bit per hart

    // Slave/master ports of dm_top — not yet wired to CHI fabric.  Today's
    // first-pass tie-offs leave the DM CSR window inaccessible from a CHI
    // master; OpenOCD is forced to use the abstract-command path (program
    // buffer + halt/resume), which is enough for code-load + run.
    wire        dm_slave_req_tie       = 1'b0;
    wire        dm_slave_we_tie        = 1'b0;
    wire [31:0] dm_slave_addr_tie      = 32'b0;
    wire  [3:0] dm_slave_be_tie        = 4'b0;
    wire [31:0] dm_slave_wdata_tie     = 32'b0;
    wire [31:0] dm_slave_rdata_unused;

    wire        dm_master_req_unused;
    wire [31:0] dm_master_addr_unused;
    wire        dm_master_we_unused;
    wire [31:0] dm_master_wdata_unused;
    wire  [3:0] dm_master_be_unused;
    wire        dm_master_gnt_tie      = 1'b1;
    wire        dm_master_r_valid_tie  = 1'b0;
    wire [31:0] dm_master_r_rdata_tie  = 32'b0;

    cva6_debug_subsystem #(
        .NrHarts (NUM_RNFS)
    ) u_dbg (
        .clk_i              (clk_sys),
        .rst_ni             (rst_n),

        .tck_i              (tck_i),
        .tms_i              (tms_i),
        .tdi_i              (td_i),
        .tdo_o              (td_o),
        .trst_ni            (trst_ni),

        .ndmreset_o         (ndmreset),
        .dmactive_o         (dmactive),
        .debug_req_o        (debug_req),

        .slave_req_i        (dm_slave_req_tie),
        .slave_we_i         (dm_slave_we_tie),
        .slave_addr_i       (dm_slave_addr_tie),
        .slave_be_i         (dm_slave_be_tie),
        .slave_wdata_i      (dm_slave_wdata_tie),
        .slave_rdata_o      (dm_slave_rdata_unused),

        .master_req_o       (dm_master_req_unused),
        .master_addr_o      (dm_master_addr_unused),
        .master_we_o        (dm_master_we_unused),
        .master_wdata_o     (dm_master_wdata_unused),
        .master_be_o        (dm_master_be_unused),
        .master_gnt_i       (dm_master_gnt_tie),
        .master_r_valid_i   (dm_master_r_valid_tie),
        .master_r_rdata_i   (dm_master_r_rdata_tie)
    );

    // Combined hart reset: external reset OR non-debug-module reset from DM.
    wire rst_n_core = rst_n & ~ndmreset;

    // ════════════════════════════════════════════════════════════════════════
    // ── 3. RN-Fs (CVA6 + L1.5 + rnf_link, NUM_RNFS instances via rnf_wrapper)
    // ════════════════════════════════════════════════════════════════════════
    // rnf_wrapper internally instantiates `corecount_g` rnf_tops with
    // RNF_NID = generate-index.  Vectorised buses match chi_icn_mesh's
    // CORE_COUNT-wide ports exactly when NUM_RNFS == CORE_COUNT; for
    // NUM_RNFS < CORE_COUNT we tie off the unused slots in the bridge below.
    initial begin
        if (NUM_RNFS > CORE_COUNT) begin
            $fatal(1, "NUM_RNFS=%0d exceeds mesh CORE_COUNT=%0d", NUM_RNFS, CORE_COUNT);
        end
    end

    wire [NUM_RNFS-1:0]                                rnfw_txreqflitv;
    wire [NUM_RNFS-1:0][`CHIE_REQ_FLIT_WIDTH-1:0]     rnfw_txreqflit;
    wire [NUM_RNFS-1:0]                                rnfw_txreqflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_txreqlcrdv;

    wire [NUM_RNFS-1:0]                                rnfw_txrspflitv;
    wire [NUM_RNFS-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]     rnfw_txrspflit;
    wire [NUM_RNFS-1:0]                                rnfw_txrspflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_txrsplcrdv;

    wire [NUM_RNFS-1:0]                                rnfw_txdatflitv;
    wire [NUM_RNFS-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]     rnfw_txdatflit;
    wire [NUM_RNFS-1:0]                                rnfw_txdatflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_txdatlcrdv;

    wire [NUM_RNFS-1:0]                                rnfw_rxrspflitv;
    wire [NUM_RNFS-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]     rnfw_rxrspflit;
    wire [NUM_RNFS-1:0]                                rnfw_rxrspflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_rxrsplcrdv;

    wire [NUM_RNFS-1:0]                                rnfw_rxdatflitv;
    wire [NUM_RNFS-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]     rnfw_rxdatflit;
    wire [NUM_RNFS-1:0]                                rnfw_rxdatflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_rxdatlcrdv;

    wire [NUM_RNFS-1:0]                                rnfw_rxsnpflitv;
    wire [NUM_RNFS-1:0][`CHIE_SNP_FLIT_WIDTH-1:0]     rnfw_rxsnpflit;
    wire [NUM_RNFS-1:0]                                rnfw_rxsnpflitpend;
    wire [NUM_RNFS-1:0]                                rnfw_rxsnplcrdv;

    wire [NUM_RNFS-1:0] rnfw_txlinkactivereq, rnfw_txlinkactiveack;
    wire [NUM_RNFS-1:0] rnfw_rxlinkactivereq, rnfw_rxlinkactiveack;
    wire [NUM_RNFS-1:0] rnfw_txactive,        rnfw_rxactive;

    rnf_wrapper #(
        .corecount_g                  (NUM_RNFS),
        .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
        .HNF_NID_PARAM                (HNF_NID_PARAM),
        .SNF_NID_PARAM                (SNF_NID_PARAM)
    ) u_rnf_wrap (
        .clk             (clk_sys),
        .rst_n           (rst_n_core),
        .clk_en          (1'b1),
        .debug_req_i     (debug_req),

        // ICN → RNF
        .rxrspflitv      (rnfw_rxrspflitv),
        .rxrspflit       (rnfw_rxrspflit),
        .rxrspflitpend   (rnfw_rxrspflitpend),
        .rxdatflitv      (rnfw_rxdatflitv),
        .rxdatflit       (rnfw_rxdatflit),
        .rxdatflitpend   (rnfw_rxdatflitpend),
        .rxsnpflitv      (rnfw_rxsnpflitv),
        .rxsnpflit       (rnfw_rxsnpflit),
        .rxsnpflitpend   (rnfw_rxsnpflitpend),

        .txreqlcrdv      (rnfw_txreqlcrdv),
        .txrsplcrdv      (rnfw_txrsplcrdv),
        .txdatlcrdv      (rnfw_txdatlcrdv),

        // RNF → ICN
        .rxrsplcrdv      (rnfw_rxrsplcrdv),
        .rxdatlcrdv      (rnfw_rxdatlcrdv),
        .rxsnplcrdv      (rnfw_rxsnplcrdv),
        .txreqflitv      (rnfw_txreqflitv),
        .txreqflit       (rnfw_txreqflit),
        .txreqflitpend   (rnfw_txreqflitpend),
        .txrspflitv      (rnfw_txrspflitv),
        .txrspflit       (rnfw_txrspflit),
        .txrspflitpend   (rnfw_txrspflitpend),
        .txdatflitv      (rnfw_txdatflitv),
        .txdatflit       (rnfw_txdatflit),
        .txdatflitpend   (rnfw_txdatflitpend),

        .txlinkactivereq (rnfw_txlinkactivereq),
        .txlinkactiveack (rnfw_txlinkactiveack),
        .rxlinkactivereq (rnfw_rxlinkactivereq),
        .rxlinkactiveack (rnfw_rxlinkactiveack),
        .txactive        (rnfw_txactive),
        .rxactive        (rnfw_rxactive)
    );

    // ════════════════════════════════════════════════════════════════════════
    // ── 4. CHI 2×2 mesh interconnect (chi_icn_mesh)  ────────────────────────
    // ════════════════════════════════════════════════════════════════════════
    // The mesh expects a 2-element vector for RNF traffic (XP_0_0.P0 and
    // XP_0_0.P1).  Single-core build: RNF[1] is tied off.
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txreqflitv;
    wire [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0]      mesh_rnf_txreqflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txreqlcrdv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txrspflitv;
    wire [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]      mesh_rnf_txrspflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txrsplcrdv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txdatflitv;
    wire [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]      mesh_rnf_txdatflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txdatlcrdv;

    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxsnpflitv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxsnppend;
    wire [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0]      mesh_rnf_rxsnpflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxsnplcrdv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxrspflitv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxrsppend;
    wire [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]      mesh_rnf_rxrspflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxrsplcrdv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxdatflitv;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxdatpend;
    wire [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]      mesh_rnf_rxdatflit;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxdatlcrdv;

    wire [CORE_COUNT-1:0]                                 mesh_rnf_txlinkactivereq;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txlinkactiveack;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxlinkactivereq;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxlinkactiveack;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_txactive;
    wire [CORE_COUNT-1:0]                                 mesh_rnf_rxactive;

    // Bridge rnf_wrapper outputs (NUM_RNFS-wide) to the mesh's CORE_COUNT-wide
    // RNF ports.  Active slots pass through; unused slots are tied off.
    generate
        for (genvar i = 0; i < CORE_COUNT; i++) begin : g_mesh_rnf_bridge
            if (i < NUM_RNFS) begin : g_active
                // RNF → mesh (TX path)
                assign mesh_rnf_txreqflitv[i]        = rnfw_txreqflitv[i];
                assign mesh_rnf_txreqflit[i]         = rnfw_txreqflit[i];
                assign rnfw_txreqlcrdv[i]            = mesh_rnf_txreqlcrdv[i];
                assign mesh_rnf_txrspflitv[i]        = rnfw_txrspflitv[i];
                assign mesh_rnf_txrspflit[i]         = rnfw_txrspflit[i];
                assign rnfw_txrsplcrdv[i]            = mesh_rnf_txrsplcrdv[i];
                assign mesh_rnf_txdatflitv[i]        = rnfw_txdatflitv[i];
                assign mesh_rnf_txdatflit[i]         = rnfw_txdatflit[i];
                assign rnfw_txdatlcrdv[i]            = mesh_rnf_txdatlcrdv[i];

                // mesh → RNF (RX path)
                assign rnfw_rxsnpflitv[i]            = mesh_rnf_rxsnpflitv[i];
                assign rnfw_rxsnpflit[i]             = mesh_rnf_rxsnpflit[i];
                assign rnfw_rxsnpflitpend[i]         = mesh_rnf_rxsnppend[i];
                assign mesh_rnf_rxsnplcrdv[i]        = rnfw_rxsnplcrdv[i];
                assign rnfw_rxrspflitv[i]            = mesh_rnf_rxrspflitv[i];
                assign rnfw_rxrspflit[i]             = mesh_rnf_rxrspflit[i];
                assign rnfw_rxrspflitpend[i]         = mesh_rnf_rxrsppend[i];
                assign mesh_rnf_rxrsplcrdv[i]        = rnfw_rxrsplcrdv[i];
                assign rnfw_rxdatflitv[i]            = mesh_rnf_rxdatflitv[i];
                assign rnfw_rxdatflit[i]             = mesh_rnf_rxdatflit[i];
                assign rnfw_rxdatflitpend[i]         = mesh_rnf_rxdatpend[i];
                assign mesh_rnf_rxdatlcrdv[i]        = rnfw_rxdatlcrdv[i];

                // Link activate
                assign mesh_rnf_txlinkactivereq[i]   = rnfw_txlinkactivereq[i];
                assign rnfw_txlinkactiveack[i]       = mesh_rnf_txlinkactiveack[i];
                assign rnfw_rxlinkactivereq[i]       = mesh_rnf_rxlinkactivereq[i];
                assign mesh_rnf_rxlinkactiveack[i]   = rnfw_rxlinkactiveack[i];
                assign mesh_rnf_txactive[i]          = rnfw_txactive[i];
                assign rnfw_rxactive[i]              = mesh_rnf_rxactive[i];
            end else begin : g_tied
                assign mesh_rnf_txreqflitv[i]        = 1'b0;
                assign mesh_rnf_txreqflit[i]         = '0;
                assign mesh_rnf_txrspflitv[i]        = 1'b0;
                assign mesh_rnf_txrspflit[i]         = '0;
                assign mesh_rnf_txdatflitv[i]        = 1'b0;
                assign mesh_rnf_txdatflit[i]         = '0;
                assign mesh_rnf_rxsnplcrdv[i]        = 1'b0;
                assign mesh_rnf_rxrsplcrdv[i]        = 1'b0;
                assign mesh_rnf_rxdatlcrdv[i]        = 1'b0;
                assign mesh_rnf_txlinkactivereq[i]   = 1'b0;
                assign mesh_rnf_rxlinkactiveack[i]   = 1'b0;
                assign mesh_rnf_txactive[i]          = 1'b0;
            end
        end
    endgenerate

    // HNF endpoint wires
    wire                            mesh_hnf_rxreqflitv;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0] mesh_hnf_rxreqflit;
    wire                            mesh_hnf_rxreqpend;
    wire                            mesh_hnf_rxreqlcrdv;
    wire                            mesh_hnf_rxrspflitv;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0] mesh_hnf_rxrspflit;
    wire                            mesh_hnf_rxrsppend;
    wire                            mesh_hnf_rxrsplcrdv;
    wire                            mesh_hnf_rxdatflitv;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0] mesh_hnf_rxdatflit;
    wire                            mesh_hnf_rxdatpend;
    wire                            mesh_hnf_rxdatlcrdv;

    wire                            hnf_txsnpflitv;
    wire [`HNF_SNP_FLIT_WIDTH-1:0]  hnf_txsnpflit;
    wire                            hnf_txsnpflitpend;
    wire                            hnf_txsnplcrdv;
    wire                            hnf_txreqflitv;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_txreqflit;
    wire                            hnf_txreqflitpend;
    wire                            hnf_txreqlcrdv;
    wire                            hnf_txrspflitv;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_txrspflit;
    wire                            hnf_txrspflitpend;
    wire                            hnf_txrsplcrdv;
    wire                            hnf_txdatflitv;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_txdatflit;
    wire                            hnf_txdatflitpend;
    wire                            hnf_txdatlcrdv;

    // SNF endpoint wires
    wire                            snf_rxreqflitv;
    wire [`CHIE_REQ_FLIT_WIDTH-1:0] snf_rxreqflit;
    wire                            snf_rxreqlcrdv;
    wire                            snf_rxdatflitv;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0] snf_rxdatflit;
    wire                            snf_rxdatlcrdv;
    wire                            snf_txrspflitv;
    wire [`CHIE_RSP_FLIT_WIDTH-1:0] snf_txrspflit;
    wire                            snf_txrsplcrdv;
    wire                            snf_txdatflitv;
    wire [`CHIE_DAT_FLIT_WIDTH-1:0] snf_txdatflit;
    wire                            snf_txdatlcrdv;
    wire                            snf_txlinkactivereq, snf_txlinkactiveack;
    wire                            snf_rxlinkactivereq, snf_rxlinkactiveack;
    wire                            snf_txactive,        snf_rxactive;

    chi_icn_mesh #(
        .CORE_COUNT                  (CORE_COUNT),
        .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
        .HNF_NID_PARAM               (HNF_NID_PARAM),
        .SNF_NID_PARAM               (SNF_NID_PARAM),
        .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
        .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM)
    ) u_chi_icn (
        .clk                  (clk_sys),
        .rst                  (rst),

        .rnf_txreqflitv       (mesh_rnf_txreqflitv),
        .rnf_txreqflit        (mesh_rnf_txreqflit),
        .rnf_txreqlcrdv       (mesh_rnf_txreqlcrdv),
        .rnf_txrspflitv       (mesh_rnf_txrspflitv),
        .rnf_txrspflit        (mesh_rnf_txrspflit),
        .rnf_txrsplcrdv       (mesh_rnf_txrsplcrdv),
        .rnf_txdatflitv       (mesh_rnf_txdatflitv),
        .rnf_txdatflit        (mesh_rnf_txdatflit),
        .rnf_txdatlcrdv       (mesh_rnf_txdatlcrdv),

        .rnf_rxsnpflitv       (mesh_rnf_rxsnpflitv),
        .rnf_rxsnppend        (mesh_rnf_rxsnppend),
        .rnf_rxsnpflit        (mesh_rnf_rxsnpflit),
        .rnf_rxsnplcrdv       (mesh_rnf_rxsnplcrdv),
        .rnf_rxrspflitv       (mesh_rnf_rxrspflitv),
        .rnf_rxrsppend        (mesh_rnf_rxrsppend),
        .rnf_rxrspflit        (mesh_rnf_rxrspflit),
        .rnf_rxrsplcrdv       (mesh_rnf_rxrsplcrdv),
        .rnf_rxdatflitv       (mesh_rnf_rxdatflitv),
        .rnf_rxdatpend        (mesh_rnf_rxdatpend),
        .rnf_rxdatflit        (mesh_rnf_rxdatflit),
        .rnf_rxdatlcrdv       (mesh_rnf_rxdatlcrdv),

        .rnf_txlinkactivereq  (mesh_rnf_txlinkactivereq),
        .rnf_txlinkactiveack  (mesh_rnf_txlinkactiveack),
        .rnf_rxlinkactivereq  (mesh_rnf_rxlinkactivereq),
        .rnf_rxlinkactiveack  (mesh_rnf_rxlinkactiveack),
        .rnf_txactive         (mesh_rnf_txactive),
        .rnf_rxactive         (mesh_rnf_rxactive),

        // HNF endpoint
        .hnf_rxreqflitv       (mesh_hnf_rxreqflitv),
        .hnf_rxreqflit        (mesh_hnf_rxreqflit),
        .hnf_rxreqpend        (mesh_hnf_rxreqpend),
        .hnf_rxreqlcrdv       (mesh_hnf_rxreqlcrdv),
        .hnf_rxrspflitv       (mesh_hnf_rxrspflitv),
        .hnf_rxrspflit        (mesh_hnf_rxrspflit),
        .hnf_rxrsppend        (mesh_hnf_rxrsppend),
        .hnf_rxrsplcrdv       (mesh_hnf_rxrsplcrdv),
        .hnf_rxdatflitv       (mesh_hnf_rxdatflitv),
        .hnf_rxdatflit        (mesh_hnf_rxdatflit),
        .hnf_rxdatpend        (mesh_hnf_rxdatpend),
        .hnf_rxdatlcrdv       (mesh_hnf_rxdatlcrdv),

        .hnf_txsnpflitv       (hnf_txsnpflitv),
        .hnf_txsnpflit        (hnf_txsnpflit),
        .hnf_txsnppend        (hnf_txsnpflitpend),
        .hnf_txsnplcrdv       (hnf_txsnplcrdv),
        .hnf_txreqflitv       (hnf_txreqflitv),
        .hnf_txreqflit        (hnf_txreqflit),
        .hnf_txreqpend        (hnf_txreqflitpend),
        .hnf_txreqlcrdv       (hnf_txreqlcrdv),
        .hnf_txrspflitv       (hnf_txrspflitv),
        .hnf_txrspflit        (hnf_txrspflit),
        .hnf_txrsppend        (hnf_txrspflitpend),
        .hnf_txrsplcrdv       (hnf_txrsplcrdv),
        .hnf_txdatflitv       (hnf_txdatflitv),
        .hnf_txdatflit        (hnf_txdatflit),
        .hnf_txdatpend        (hnf_txdatflitpend),
        .hnf_txdatlcrdv       (hnf_txdatlcrdv),

        // SNF endpoint
        .snf_rxreqflitv       (snf_rxreqflitv),
        .snf_rxreqflit        (snf_rxreqflit),
        .snf_rxreqlcrdv       (snf_rxreqlcrdv),
        .snf_rxdatflitv       (snf_rxdatflitv),
        .snf_rxdatflit        (snf_rxdatflit),
        .snf_rxdatlcrdv       (snf_rxdatlcrdv),
        .snf_txrspflitv       (snf_txrspflitv),
        .snf_txrspflit        (snf_txrspflit),
        .snf_txrsplcrdv       (snf_txrsplcrdv),
        .snf_txdatflitv       (snf_txdatflitv),
        .snf_txdatflit        (snf_txdatflit),
        .snf_txdatlcrdv       (snf_txdatlcrdv),
        .snf_txlinkactivereq  (snf_txlinkactivereq),
        .snf_txlinkactiveack  (snf_txlinkactiveack),
        .snf_rxlinkactivereq  (snf_rxlinkactivereq),
        .snf_rxlinkactiveack  (snf_rxlinkactiveack),
        .snf_txactive         (snf_txactive),
        .snf_rxactive         (snf_rxactive)
    );

    // ════════════════════════════════════════════════════════════════════════
    // ── 5. HN-F (RTL hnf module) ────────────────────────────────────────────
    // ════════════════════════════════════════════════════════════════════════
    wire hnf_notify_unused;

    hnf `HNF_PARAM_INST u_hnf (
        .CLK              (clk_sys),
        .RST              (rst),

        // ICN → HNF
        .RXREQFLITV       (mesh_hnf_rxreqflitv),
        .RXREQFLIT        (mesh_hnf_rxreqflit),
        .RXREQFLITPEND    (mesh_hnf_rxreqpend),
        .RXRSPFLITV       (mesh_hnf_rxrspflitv),
        .RXRSPFLIT        (mesh_hnf_rxrspflit),
        .RXRSPFLITPEND    (mesh_hnf_rxrsppend),
        .RXDATFLITV       (mesh_hnf_rxdatflitv),
        .RXDATFLIT        (mesh_hnf_rxdatflit),
        .RXDATFLITPEND    (mesh_hnf_rxdatpend),

        // HNF → ICN
        .TXREQFLITV       (hnf_txreqflitv),
        .TXREQFLIT        (hnf_txreqflit),
        .TXREQFLITPEND    (hnf_txreqflitpend),
        .TXRSPFLITV       (hnf_txrspflitv),
        .TXRSPFLIT        (hnf_txrspflit),
        .TXRSPFLITPEND    (hnf_txrspflitpend),
        .TXSNPFLITV       (hnf_txsnpflitv),
        .TXSNPFLIT        (hnf_txsnpflit),
        .TXSNPFLITPEND    (hnf_txsnpflitpend),
        .TXDATFLITV       (hnf_txdatflitv),
        .TXDATFLIT        (hnf_txdatflit),
        .TXDATFLITPEND    (hnf_txdatflitpend),

        .RXREQLCRDV       (mesh_hnf_rxreqlcrdv),
        .RXRSPLCRDV       (mesh_hnf_rxrsplcrdv),
        .RXDATLCRDV       (mesh_hnf_rxdatlcrdv),
        .TXREQLCRDV       (hnf_txreqlcrdv),
        .TXRSPLCRDV       (hnf_txrsplcrdv),
        .TXSNPLCRDV       (hnf_txsnplcrdv),
        .TXDATLCRDV       (hnf_txdatlcrdv),

        .notify_reg       (hnf_notify_unused)
    );

    // ════════════════════════════════════════════════════════════════════════
    // ── 6. SN-F (direct snf instance; AXI master exposed for MIG hookup) ────
    // ════════════════════════════════════════════════════════════════════════
    // mem_ss is the simulation memory-backing wrapper (snf + axi2mem + inline
    // BRAM SRAM) — not used on FPGA because the SN-F's AXI master goes to the
    // DDR4 controller directly.  We instantiate `snf` raw and bring its AXI
    // pins out to the board top.  MIG hookup is a follow-on.
    snf #(
        .AXI4_AXDATA_WIDTH_PARAM       (AXI_DATA_WIDTH),              // 128 (see localparam note)
        .AXI4_PA_WIDTH_PARAM           (AXI_ADDR_WIDTH),              // 64
        .CHIE_REQ_ADDR_WIDTH_PARAM     (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM          (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM         (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM           (CHIE_BE_WIDTH_PARAM),
        .SNF_NID_PARAM                 (SNF_NID_PARAM),
        .XP_LCRD_NUM_PARAM             (XP_LCRD_NUM_PARAM)
    ) u_snf (
        .CLK              (clk_sys),
        .RST              (rst),

        .TXLINKACTIVEREQ  (snf_txlinkactivereq),
        .TXLINKACTIVEACK  (snf_txlinkactiveack),
        .RXLINKACTIVEREQ  (snf_rxlinkactivereq),
        .RXLINKACTIVEACK  (snf_rxlinkactiveack),
        .TXSACTIVE        (snf_txactive),
        .RXSACTIVE        (snf_rxactive),

        .RXREQFLITV       (snf_rxreqflitv),
        .RXREQFLIT        (snf_rxreqflit),
        .RXREQFLITPEND    (1'b0),
        .RXREQLCRDV       (snf_rxreqlcrdv),
        .RXDATFLITV       (snf_rxdatflitv),
        .RXDATFLIT        (snf_rxdatflit),
        .RXDATFLITPEND    (1'b0),
        .RXDATLCRDV       (snf_rxdatlcrdv),

        .TXRSPFLITV       (snf_txrspflitv),
        .TXRSPFLIT        (snf_txrspflit),
        .TXRSPFLITPEND    (/* unused */),
        .TXRSPLCRDV       (snf_txrsplcrdv),
        .TXDATFLITV       (snf_txdatflitv),
        .TXDATFLIT        (snf_txdatflit),
        .TXDATFLITPEND    (/* unused */),
        .TXDATLCRDV       (snf_txdatlcrdv),

        // AXI master → board top (eventually to MIG)
        .ARID     (snf_axi_ar_id),
        .ARADDR   (snf_axi_ar_addr),
        .ARLEN    (snf_axi_ar_len),
        .ARSIZE   (snf_axi_ar_size),
        .ARBURST  (snf_axi_ar_burst),
        .ARLOCK   (snf_axi_ar_lock),
        .ARCACHE  (snf_axi_ar_cache),
        .ARPROT   (snf_axi_ar_prot),
        .ARQOS    (snf_axi_ar_qos),
        .ARREGION (snf_axi_ar_region),
        .ARVALID  (snf_axi_ar_valid),
        .ARREADY  (snf_axi_ar_ready),
        .RID      (snf_axi_r_id),
        .RDATA    (snf_axi_r_data),
        .RRESP    (snf_axi_r_resp),
        .RLAST    (snf_axi_r_last),
        .RVALID   (snf_axi_r_valid),
        .RREADY   (snf_axi_r_ready),
        .AWID     (snf_axi_aw_id),
        .AWADDR   (snf_axi_aw_addr),
        .AWLEN    (snf_axi_aw_len),
        .AWSIZE   (snf_axi_aw_size),
        .AWBURST  (snf_axi_aw_burst),
        .AWLOCK   (snf_axi_aw_lock),
        .AWCACHE  (snf_axi_aw_cache),
        .AWPROT   (snf_axi_aw_prot),
        .AWQOS    (snf_axi_aw_qos),
        .AWREGION (snf_axi_aw_region),
        .AWVALID  (snf_axi_aw_valid),
        .AWREADY  (snf_axi_aw_ready),
        .WDATA    (snf_axi_w_data),
        .WSTRB    (snf_axi_w_strb),
        .WLAST    (snf_axi_w_last),
        .WVALID   (snf_axi_w_valid),
        .WREADY   (snf_axi_w_ready),
        .BID      (snf_axi_b_id),
        .BRESP    (snf_axi_b_resp),
        .BVALID   (snf_axi_b_valid),
        .BREADY   (snf_axi_b_ready)
    );

    // ════════════════════════════════════════════════════════════════════════
    // ── 7. Status LEDs ──────────────────────────────────────────────────────
    // ════════════════════════════════════════════════════════════════════════
    assign leds = {
        |rnfw_txactive,     // [7] any RN-F TX link up
        snf_txactive,       // [6] SN-F TX link up
        ndmreset,           // [5] DM non-debug-module reset
        dmactive,           // [4] DM is active (TAP responding)
        |debug_req,         // [3] any hart halt-requested
        1'b0,               // [2] reserved
        rst_n,              // [1] system reset deasserted
        pll_locked          // [0] clk_wiz locked
    };

endmodule
