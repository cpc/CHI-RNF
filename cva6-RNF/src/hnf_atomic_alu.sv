/*
 * hnf_atomic_alu.sv -- combinational ALU for CHI atomics at the HN-F.
 *
 * Inputs:
 *   cur_value   - current 256-bit cache-line value (from L3 read or peer-forward)
 *   operand     - 256-bit operand from the requester's TX DAT (low 8 bytes valid)
 *   compare_val - 256-bit compare value (AtomicCompare only; reserved, unused today)
 *   addr_lo     - byte offset (0..31) within the line for the atomic target.
 *                 Must be 8-byte aligned for the current implementation.
 *   atomic_op   - selector (see ATOMIC_OP_* localparams below)
 *
 * Outputs:
 *   new_value   - cache-line value after ALU; written back to L3
 *   returned    - 256 bits containing the 8-byte old value at the same lane,
 *                 zeros elsewhere.  AtomicStore consumers ignore this.
 *
 * P4 minimum scope:
 *   - Fixed 8-byte operand size (CHI size == 3).  Sub-doubleword sizes
 *     (1/2/4 B) will land in this same lane wrapper later via a byte-mask
 *     refinement; the protocol path is unchanged.
 *   - Only ATOMIC_OP_ADD is implemented; the rest fall through to a
 *     passthrough (new = current).  Add the remaining ALU ops once the
 *     end-to-end protocol path is verified.
 *   - Compare-and-swap path is reserved (compare_val input) but inactive.
 *
 * Combinational only -- no clock; consumer registers the output.
 */

`ifndef HNF_ATOMIC_ALU_V
`define HNF_ATOMIC_ALU_V

module hnf_atomic_alu #(
    parameter int DATA_WIDTH = 256,
    parameter int LANE_WIDTH = 64       // 8-byte atomic granule for P4
) (
    input  logic [DATA_WIDTH-1:0] cur_value,
    input  logic [DATA_WIDTH-1:0] operand,
    input  logic [DATA_WIDTH-1:0] compare_val,    // reserved (AtomicCompare)
    input  logic            [4:0] addr_lo,        // byte offset, 8B-aligned
    input  logic            [3:0] atomic_op,

    output logic [DATA_WIDTH-1:0] new_value,
    output logic [DATA_WIDTH-1:0] returned
);

    // ── Op selector encoding ────────────────────────────────────────────────
    localparam logic [3:0] ATOMIC_OP_ADD     = 4'h0;
    localparam logic [3:0] ATOMIC_OP_CLR     = 4'h1;
    localparam logic [3:0] ATOMIC_OP_EOR     = 4'h2;
    localparam logic [3:0] ATOMIC_OP_SET     = 4'h3;
    localparam logic [3:0] ATOMIC_OP_SMAX    = 4'h4;
    localparam logic [3:0] ATOMIC_OP_SMIN    = 4'h5;
    localparam logic [3:0] ATOMIC_OP_UMAX    = 4'h6;
    localparam logic [3:0] ATOMIC_OP_UMIN    = 4'h7;
    localparam logic [3:0] ATOMIC_OP_SWAP    = 4'h8;
    localparam logic [3:0] ATOMIC_OP_COMPARE = 4'h9;

    // ── 8-byte aligned bit offset within the 256-bit line ──────────────────
    // Picks one of 4 doublewords (256 / 64 = 4).
    wire [4:0] dw_off       = addr_lo & 5'b11000;          // 0, 8, 16, or 24
    wire [7:0] bit_off      = {dw_off, 3'b000};            // 0, 64, 128, 192

    // ── Extract the current and operand lanes ──────────────────────────────
    wire [LANE_WIDTH-1:0] cur_lane = cur_value[bit_off +: LANE_WIDTH];
    wire [LANE_WIDTH-1:0] op_lane  = operand  [bit_off +: LANE_WIDTH];

    // ── ALU: ADD and SWAP wired; others passthrough ─────────────────────────
    // AtomicSwap semantics (CHI-E): NEW = operand (unconditional replace),
    // returned = OLD.  That's lane := op_lane in the ALU, plus the existing
    // `returned` output already carries cur_lane.
    logic [LANE_WIDTH-1:0] alu_lane;
    always_comb begin
        unique case (atomic_op)
            ATOMIC_OP_ADD:  alu_lane = cur_lane + op_lane;
            ATOMIC_OP_SWAP: alu_lane = op_lane;
            // P4-extend: implement CLR/EOR/SET/SMAX/SMIN/UMAX/UMIN/COMPARE
            default:        alu_lane = cur_lane;           // passthrough
        endcase
    end

    // ── new_value: replace the target doubleword; preserve the rest ────────
    always_comb begin
        new_value = cur_value;
        new_value[bit_off +: LANE_WIDTH] = alu_lane;
    end

    // ── returned: old value placed in the same lane, zeros elsewhere ───────
    always_comb begin
        returned = '0;
        returned[bit_off +: LANE_WIDTH] = cur_lane;
    end

endmodule

`endif /* HNF_ATOMIC_ALU_V */
