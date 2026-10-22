// cva6_debug_subsystem.sv — JTAG TAP + dmi_jtag + dm_top wrapper.
//
// Wraps the pulp-platform/riscv-dbg stack into a single block with a clean
// pin-side interface, so the top-level only has to feed it JTAG pads and
// a system-bus slave + master pair.
//
// Source files used (all from
//   singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/):
//
//   dmi_jtag.sv         JTAG TAP + DMI request/response framing
//   dmi_jtag_tap.sv     RAW JTAG 4-state TAP controller
//   dm_top.sv           Debug Module (CSRs + abstract cmd + SBA + program buf)
//   dm_csrs.sv          Debug CSRs
//   dm_mem.sv           Debug memory (program buffer + data + ROM)
//   dm_sba.sv           System Bus Access master
//   dm_pkg.sv           DM types (dmi_req_t, dmi_resp_t, command_t…)
//   dmi_cdc.sv          CDC for DMI between JTAG clock domain and clk_i

module cva6_debug_subsystem
    import dm::*;
#(
    parameter int unsigned NrHarts        = 1,
    parameter int unsigned BusWidth       = 32,
    parameter int unsigned DmBaseAddress  = 32'h0000_1000,
    parameter logic [31:0] JtagIdcode     = 32'h2495_1001  // CVA6 default
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    // JTAG pads (route to PMOD pins or BSCAN primitive at top level)
    input  logic              tck_i,
    input  logic              tms_i,
    input  logic              tdi_i,
    output logic              tdo_o,
    input  logic              trst_ni,

    // DM → hart
    output logic              ndmreset_o,
    output logic              dmactive_o,
    output logic [NrHarts-1:0] debug_req_o,

    // DM slave port (CVA6 LSU → DM register window at DmBaseAddress)
    input  logic                   slave_req_i,
    input  logic                   slave_we_i,
    input  logic [BusWidth-1:0]    slave_addr_i,
    input  logic [BusWidth/8-1:0]  slave_be_i,
    input  logic [BusWidth-1:0]    slave_wdata_i,
    output logic [BusWidth-1:0]    slave_rdata_o,

    // DM master port (System Bus Access → fabric)
    output logic                   master_req_o,
    output logic [BusWidth-1:0]    master_addr_o,
    output logic                   master_we_o,
    output logic [BusWidth-1:0]    master_wdata_o,
    output logic [BusWidth/8-1:0]  master_be_o,
    input  logic                   master_gnt_i,
    input  logic                   master_r_valid_i,
    input  logic [BusWidth-1:0]    master_r_rdata_i
);

    // ── DMI bus between dmi_jtag (TCK domain) and dm_top (clk_i domain) ─────
    // dmi_jtag handles the CDC internally via the input/output handshake.
    logic                  dmi_rst_n;
    logic                  dmi_req_valid;
    logic                  dmi_req_ready;
    dm::dmi_req_t          dmi_req;

    logic                  dmi_resp_valid;
    logic                  dmi_resp_ready;
    dm::dmi_resp_t         dmi_resp;

    logic                  tdo_oe_unused;

    // ── JTAG TAP + DMI framer ───────────────────────────────────────────────
    dmi_jtag #(
        .IdcodeValue (JtagIdcode)
    ) u_dmi_jtag (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .testmode_i       (1'b0),

        .dmi_rst_no       (dmi_rst_n),
        .dmi_req_o        (dmi_req),
        .dmi_req_valid_o  (dmi_req_valid),
        .dmi_req_ready_i  (dmi_req_ready),

        .dmi_resp_i       (dmi_resp),
        .dmi_resp_ready_o (dmi_resp_ready),
        .dmi_resp_valid_i (dmi_resp_valid),

        .tck_i            (tck_i),
        .tms_i            (tms_i),
        .trst_ni          (trst_ni),
        .td_i             (tdi_i),
        .td_o             (tdo_o),
        .tdo_oe_o         (tdo_oe_unused)
    );

    // ── Hart-info: required by dm_top ───────────────────────────────────────
    // Matches the standard CVA6 layout (ZeroBase = 0x800, DataAddr = 0x380).
    dm::hartinfo_t [NrHarts-1:0] hartinfo;
    for (genvar h = 0; h < NrHarts; h++) begin : g_hartinfo
        assign hartinfo[h] = '{
            zero1      :  '0,
            nscratch   :  4'd2,
            zero0      :  '0,
            dataaccess : 1'b1,
            datasize   : dm::DataCount,
            dataaddr   : dm::DataAddr
        };
    end

    // ── Debug Module ────────────────────────────────────────────────────────
    dm_top #(
        .NrHarts        (NrHarts),
        .BusWidth       (BusWidth),
        .DmBaseAddress  (DmBaseAddress)
    ) u_dm_top (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .testmode_i      (1'b0),
        .ndmreset_o      (ndmreset_o),
        .dmactive_o      (dmactive_o),
        .debug_req_o     (debug_req_o),
        .unavailable_i   ('0),
        .hartinfo_i      (hartinfo),

        // Slave (memory-mapped DM registers)
        .slave_req_i     (slave_req_i),
        .slave_we_i      (slave_we_i),
        .slave_addr_i    (slave_addr_i),
        .slave_be_i      (slave_be_i),
        .slave_wdata_i   (slave_wdata_i),
        .slave_rdata_o   (slave_rdata_o),

        // Master (System Bus Access for fabric reads/writes)
        .master_req_o    (master_req_o),
        .master_add_o    (master_addr_o),
        .master_we_o     (master_we_o),
        .master_wdata_o  (master_wdata_o),
        .master_be_o     (master_be_o),
        .master_gnt_i    (master_gnt_i),
        .master_r_valid_i(master_r_valid_i),
        .master_r_rdata_i(master_r_rdata_i),

        // DMI from JTAG
        .dmi_rst_ni        (dmi_rst_n),
        .dmi_req_valid_i   (dmi_req_valid),
        .dmi_req_ready_o   (dmi_req_ready),
        .dmi_req_i         (dmi_req),

        .dmi_resp_valid_o  (dmi_resp_valid),
        .dmi_resp_ready_i  (dmi_resp_ready),
        .dmi_resp_o        (dmi_resp)
    );

endmodule
