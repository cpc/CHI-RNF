# phys_bug_wave.do — focused layout for the SNF=memss + ICN=mesh deadlock.
#
# Symptom: RNF0 issues ReadClean → HNF MSHR allocates at slot 0 (~121us)
#          → HNF never emits TX REQ/RSP/DAT/SNP → MSHR stays STUCK
#          → chi_monitor flags DEADLOCK in REQ_RCVD_HNF state.
#
# Both SNF=memss + ICN=behavioral and SNF=tbsnf + ICN=mesh pass independently;
# only this combo fails — interaction bug.
#
# Open via:
#   LM_LICENSE_FILE=1718@localhost \
#     vsim -view questa_build/phys_bug.wlf -do "do ../phys_bug_wave.do"
#
# Zoom is pre-set to 100us-200us (active replay window).

# In `vsim -view` mode the wave window isn't opened by default; open it
# before issuing `delete wave *`, otherwise Questa errors out.
view wave
delete wave *

# ── 1. RNF0 → HNF: the original ReadClean REQ (should arrive ~121us) ────────
add wave -group "1. RNF0 TX REQ → mesh" \
    /tlm_rnf_hnf_tb/rnf_txreqflitv \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_0_0_P0_TXREQFLITV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_0_0_P0_TXREQFLIT \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_0_0_P0_TXREQLCRDV

# ── 2. Mesh → HNF: REQ delivery at XP_1_0 P0 (should pulse just after) ──────
add wave -group "2. Mesh → HNF RXREQ" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_RXREQFLITV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_RXREQFLIT \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_RXREQLCRDV \
    /tlm_rnf_hnf_tb/u_hnf/RXREQFLITV \
    /tlm_rnf_hnf_tb/u_hnf/RXREQLCRDV

# ── 3. HNF MSHR state (allocates but never retires) ────────────────────────
add wave -group "3. HNF MSHR" \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_alloc_en_s0 \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_alloc_en_s1_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_retire_sx \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_retire_busy_sx1_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_txreq_valid_sx1_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/mshr_txreq_txnid_sx1_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/txreq_mshr_won_sx1 \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/txdat_mshr_busy_sx \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_mshr/u_hnf_mshr_ctl/txsnp_mshr_busy_sx1

# ── 4. HNF cache pipeline (does L3 lookup ever complete?) ──────────────────
add wave -group "4. HNF cache_pipeline" \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_cache_pipeline/pipe_req_valid_sx_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_cache_pipeline/pipe_tag_match_sx4_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_cache_pipeline/pipe_fill_sx_q \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_cache_pipeline/pipe_insert_slc_fill_sx4 \
    /tlm_rnf_hnf_tb/u_hnf/u_hnf_cache_pipeline/pipe_mem_rd_sx3

# ── 5. HNF TX side (all four outbound channels — all stuck at 0) ───────────
add wave -group "5. HNF TX (all stuck)" \
    /tlm_rnf_hnf_tb/hnf_txreqflitv \
    /tlm_rnf_hnf_tb/hnf_txreqflit \
    /tlm_rnf_hnf_tb/hnf_txdatflitv \
    /tlm_rnf_hnf_tb/hnf_txrspflitv \
    /tlm_rnf_hnf_tb/hnf_txsnpflitv \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_TXREQLCRDV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_TXDATLCRDV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_TXRSPLCRDV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0_P0_TXSNPLCRDV

# ── 6. SNF endpoint state (real RTL link-active FSM) ───────────────────────
add wave -group "6. SNF link-active" \
    /tlm_rnf_hnf_tb/snf_txlinkactivereq \
    /tlm_rnf_hnf_tb/snf_txlinkactiveack \
    /tlm_rnf_hnf_tb/snf_rxlinkactivereq \
    /tlm_rnf_hnf_tb/snf_rxlinkactiveack \
    /tlm_rnf_hnf_tb/snf_txactive \
    /tlm_rnf_hnf_tb/snf_rxactive \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/linkactive_p0 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/linkactive_p0

# ── 7. SNF endpoint credit pipeline (suspected blocker) ────────────────────
add wave -group "7. SNF credit chain (suspect)" \
    /tlm_rnf_hnf_tb/snf_rxreqlcrdv \
    /tlm_rnf_hnf_tb/u_chi_icn/snf_rxreqlcrdv_eff \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1_P0_RXREQLCRDV \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txlcrd_cnt_q

# ── 8. Inter-XP REQ wires HNF→SNF (XP_1_0 → XP_1_1, north) ─────────────────
# NB: m_reqflitv_10_11 is the TXFLITV_N output of XP_1_0; if it's missing from
# the wave window, Questa optimized the net away — use Group 8b below instead.
add wave -group "8. Inter-XP HNF→SNF" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/m_reqflitv_10_11 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/m_reqflit_10_11 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/m_reqlcrdv_10_11 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/m_datflitv_11_10 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/m_datlcrdv_11_10

# ── 8b. XP_1_0 REQ channel internals (why the arbiter never fires) ─────────
# Indices: XP_INTF_E=0, XP_INTF_W=1, XP_INTF_N=2, XP_INTF_S=3, XP_INTF_P0=4, XP_INTF_P1=5
# So buffer[P0]=buffer[4], tgt[...][N]=tgt[...][2], txflitv_d1[N]=txflitv_d1[2].
add wave -group "8b. XP_1_0 m_req internals" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflitv_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_entry_enq_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_valid_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_entry_rdy_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_entry_tgt_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_entry_tgt_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxflit_buffer_entry_deq_d1

# ── 8c. XP_1_0 REQ channel arbiter (per-dst found / txflitv / credits) ─────
add wave -group "8c. XP_1_0 m_req arbiter" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_qos_hh_invec_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_qos_h_invec_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_qos_m_invec_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_qos_l_invec_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_arb_hh_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_arb_h_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_arb_m_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_arb_l_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflit_next_avail \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflitv_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txflitv_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txlcrd_cnt_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/txlcrdv \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_0/m_req/rxactive_run_q

# ── 8d. XP_1_1 REQ channel S-port (peer of XP_1_0 N) ───────────────────────
# RX_S at XP_1_1 receives what TX_N at XP_1_0 sends; rxlcrd_cnt_q[S] are the
# credits XP_1_1 has granted XP_1_0 (visible as txlcrd_cnt_q[N] at XP_1_0).
add wave -group "8d. XP_1_1 m_req S-port (RX)" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflitv_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflit_buffer_entry_enq_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflit_buffer_valid_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflit_buffer_entry_rdy_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflit_buffer_entry_tgt_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxflit_buffer_entry_tgt_r1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxlcrd_cnt_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxlcrdv_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/rxactive_run_q

# ── 8e. XP_1_1 m_req arbiter + TX_P0 to SNF (credit gate suspect) ──────────
# txlcrd_cnt_q[P0=4] is the TX credit count granted by SNF.RXREQLCRDV (via
# snf_rxreqlcrdv_eff). If stuck at 0, SNF never sent initial credits.
add wave -group "8e. XP_1_1 m_req TX_P0 (SNF-bound)" \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflit_arb_hh_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflit_arb_h_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflit_arb_m_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflit_arb_l_found_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflit_next_avail \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflitv_d1 \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txflitv_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txlcrd_cnt_q \
    /tlm_rnf_hnf_tb/u_chi_icn/u_mesh/XP_1_1/m_req/txlcrdv \
    /tlm_rnf_hnf_tb/snf_rxreqflitv \
    /tlm_rnf_hnf_tb/snf_rxreqlcrdv \
    /tlm_rnf_hnf_tb/u_chi_icn/snf_rxreqlcrdv_eff

# ── 9. SNF SNF→AXI activity (proves mem_ss is alive) ──────────────────────
add wave -group "9. mem_ss snf AXI" \
    /tlm_rnf_hnf_tb/u_mem_ss/snf_axi_bus/ar_valid \
    /tlm_rnf_hnf_tb/u_mem_ss/snf_axi_bus/ar_ready \
    /tlm_rnf_hnf_tb/u_mem_ss/snf_axi_bus/ar_addr \
    /tlm_rnf_hnf_tb/u_mem_ss/snf_axi_bus/r_valid \
    /tlm_rnf_hnf_tb/u_mem_ss/snf_axi_bus/r_data \
    /tlm_rnf_hnf_tb/u_mem_ss/mem_req \
    /tlm_rnf_hnf_tb/u_mem_ss/mem_we \
    /tlm_rnf_hnf_tb/u_mem_ss/mem_idx

# ── 10. Parsed-flit views (struct-decoded REQ/RSP/DAT/SNP) ─────────────────
add wave -group "10. Parsed dbg flits" \
    /tlm_rnf_hnf_tb/u_chi_icn/rnf_txreqflit_dbg[0] \
    /tlm_rnf_hnf_tb/u_chi_icn/hnf_rxreqflit_dbg \
    /tlm_rnf_hnf_tb/u_chi_icn/hnf_txreqflit_dbg \
    /tlm_rnf_hnf_tb/u_chi_icn/snf_rxreqflit_dbg

configure wave -namecolwidth 380 -valuecolwidth 110 -justifyvalue left
configure wave -signalnamewidth 1 -snapdistance 10
wave zoom range 100us 200us
