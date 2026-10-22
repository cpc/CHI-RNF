onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/clk
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rstn
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txreq_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txreq_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txreq_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txreq_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txrsp_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txrsp_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txrsp_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txrsp_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txdat_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txdat_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txdat_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/txdat_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxrsp_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxrsp_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxrsp_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxrsp_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxsnp_flitv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxsnp_flitpend
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxsnp_flit
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxsnp_lcrdv
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_flit_sc
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_dpi_data
add wave -noupdate -expand -group gem5 /tb_chi_system/u_gem5_ipc/rxdat_dpi_be
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/clk
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rst
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txreqflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txreqflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txreqlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txrspflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txrspflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txrsplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxsnpflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxsnppend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxsnpflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxsnplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxrspflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxrsppend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxrspflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxrsplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatpend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txlinkactivereq
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txlinkactiveack
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxlinkactivereq
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxlinkactiveack
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txactive
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxactive
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxreqflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxreqflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxreqpend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxreqlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxrspflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxrspflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxrsppend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxrsplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatpend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txsnpflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txsnpflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txsnppend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txsnplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqpend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txrspflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txrspflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txrsppend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txrsplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txdatpend
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxreqflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxreqflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxreqlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txrspflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txrspflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txrsplcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txdatflitv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txdatflit
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txdatlcrdv
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txlinkactivereq
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txlinkactiveack
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxlinkactivereq
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxlinkactiveack
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txactive
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxactive
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/icnrxreqcrdts
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/icn_hnf_crdt_buf
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_txreqflit_dbg[1]} -expand {/tb_chi_system/u_chi_icn/rnf_txreqflit_dbg[0]} {-height 16 -childformat {{addr -radix hexadecimal}} -expand} {/tb_chi_system/u_chi_icn/rnf_txreqflit_dbg[0].addr} {-radix hexadecimal}} /tb_chi_system/u_chi_icn/rnf_txreqflit_dbg
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_txrspflit_dbg[0]} -expand} /tb_chi_system/u_chi_icn/rnf_txrspflit_dbg
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_txdatflit_dbg[0]} -expand} /tb_chi_system/u_chi_icn/rnf_txdatflit_dbg
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_rxrspflit_dbg[0]} -expand} /tb_chi_system/u_chi_icn/rnf_rxrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatflit_dbg
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_rxsnpflit_dbg[0]} -expand} /tb_chi_system/u_chi_icn/rnf_rxsnpflit_dbg
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/hnf_rxreqflit_dbg
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/hnf_rxrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txrspflit_dbg
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/hnf_txsnpflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxreqflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txdatflit_dbg
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/clk}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rst_n}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg_ack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg_val}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_valid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_txnid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_opcode_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_resp_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_fwdstate_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_mshr_rxdat_dataid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_decoder_rxdat_homenid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_decoder_rxdat_ccid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_decoder_rxdat_dbid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_valid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_txnid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_opcode_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_dataid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_be_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_dbf_rxdat_data_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_buf_ready}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_valid_sx1_q}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_qos_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_tgtid_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_txnid_sx1_q}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_opcode_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_resperr_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_resp_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_dbid_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc2buffer_txrsp_tracetag_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_cache_crd_avail}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_rxdat_buf_won_sx1}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_valid_sx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_fwdnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_fwdtxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_donotgotosd}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_rettosrc}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_decoder_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_buf_ready}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_returnnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_returntxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_size}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_allowretry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_order}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_pcrdtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_memattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_dodwt}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_likelyshared}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_exclusive}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_endian}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_lpid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_txreq_bypass_expcompack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_rxbuf_bypass_won}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_valid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_srcid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_txnid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_opcode_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_resp_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_fwdstate_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_dbid_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/li_rxbuf_rxrsp_pcrdtype_s0}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_buf_ready}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_resp}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_resperr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_fwdstate}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_dataid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_homenid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_ccid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_dbid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_be}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxbuf_ack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/atomic_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_size}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_snpattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_likelyshared}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_returnnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_returntxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_allowretry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_order}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_pcrdtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_memattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_exclusive}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_endian}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_lpid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_expcompack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reqenc_txreq_reg_icache}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_enc_won}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_size}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_snpattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_likelyshared}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_returnnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_returntxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_allowretry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_order}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_pcrdtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_memattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_exclusive}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_endian}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_lpid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_expcompack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_be}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_rxctrl_txreq_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rspenc_txreq_won}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_buf_read_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_buf_store_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/tmp_rxdat_buf_read_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_consumed}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_resp_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_fwdstate_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_dataid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_homenid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_ccid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_dbid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_be_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxdat_data_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_qos_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_tgtid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_resperr_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_resp_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_dbid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txrsp_tracetag_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_buf_read_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_buf_store_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_consumed}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_qos_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_srcid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_fwdnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_fwdtxnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_addr_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_ns_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_donotgotosd_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_rettosrc_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxsnp_tracetag_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_buf_read_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_buf_store_idx}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_consumed}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_srcid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_resp_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_fwdstate_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_dbid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxrsp_pcrdtype_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/wrcl_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_qos_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_returnnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_returntxnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_size_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_addr_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_ns_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_allowretry_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_order_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_pcrdtype_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_memattr_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_dodwt_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_tracetag_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_tgtid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_srcid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_likelyshared_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_exclusive_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_endian_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_lpid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_bypass_expcompack_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_valid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_qos_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_srcid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_txnid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_opcode_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_resp_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_resperr_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_fwdstate_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_dataid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_homenid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_ccid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_tgtid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_dbid_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_be_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/rxbuf_rspenc_txdat_data_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/noc_in_rdy}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg_buffer}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg_ack_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/data_rdy_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/wait_rsp_ack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/wait_snp_ack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/ack_received}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/state}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/state_next}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/is_dirty}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/wait_dirty_flit}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/dirty_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/dirty_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/dirtydat_rdy}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/wait_compdbid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/dbid_received}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/sending_copybackwrdata}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/sending_noncopybackwrdata}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/amo_data_response}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/amo_data_response_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/msg_buffer_rxsnp}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/atomic_data_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/atomic_be_r}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/atomic_data_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/atomic_data_vld}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/do_retry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/get_address}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/get_req_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/get_memtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/get_amo_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/evict_entry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/search_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/address_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/opcode_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/amo_data_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/retry_txreq_valid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/address}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/is_icache}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/amo_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/amo_be}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_size}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_snpattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_returnnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_returntxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_allowretry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_order}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_pcrdtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_memattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_exclusive}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_likelyshared}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_endian}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_lpid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_expcompack}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_amo_data}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_amo_be}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/txreq_icache}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_txnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_opcode}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_size}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_addr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_snpattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_qos}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_returnnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_returntxnid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_ns}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_allowretry}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_order}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_pcrdtype}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_memattr}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_tracetag}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_tgtid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_srcid}
add wave -noupdate {/tb_chi_system/u_rnf_wrap/RNF_GEN[0]/u_rnf/l15/l15/rx_control/reg_likelyshared}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {17155000 ps} 0} {{Cursor 2} {19275000 ps} 0} {{Cursor 3} {31075000 ps} 0} {{Cursor 4} {31095000 ps} 0} {{Cursor 5} {17055000 ps} 0} {{Cursor 6} {19495000 ps} 0}
quietly wave cursor active 6
configure wave -namecolwidth 271
configure wave -valuecolwidth 159
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {17797270 ps} {23165340 ps}
