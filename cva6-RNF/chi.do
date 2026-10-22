onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/clk
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rst_n
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/clk_en
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/debug_req_i
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxrspflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxrspflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxrspflitpend
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxdatflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxdatflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxdatflitpend
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxsnpflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxsnpflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxsnpflitpend
add wave -noupdate -expand -group rnf -expand /tb_chi_system/u_rnf_wrap/txreqlcrdv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txrsplcrdv
add wave -noupdate -expand -group rnf -expand /tb_chi_system/u_rnf_wrap/txdatlcrdv
add wave -noupdate -expand -group rnf -expand /tb_chi_system/u_rnf_wrap/rxrsplcrdv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxdatlcrdv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxsnplcrdv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txreqflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txreqflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txreqflitpend
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txrspflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txrspflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txrspflitpend
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txdatflitv
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txdatflit
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txdatflitpend
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txlinkactivereq
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txlinkactiveack
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxlinkactivereq
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxlinkactiveack
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/txactive
add wave -noupdate -expand -group rnf /tb_chi_system/u_rnf_wrap/rxactive
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
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/rnf_rxrsplcrdv
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
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_txreqflit_dbg[1]} -expand} /tb_chi_system/u_chi_icn/rnf_txreqflit_dbg
add wave -noupdate -expand -group icn -expand -subitemconfig {{/tb_chi_system/u_chi_icn/rnf_txrspflit_dbg[1]} -expand {/tb_chi_system/u_chi_icn/rnf_txrspflit_dbg[0]} -expand} /tb_chi_system/u_chi_icn/rnf_txrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_txdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxreqflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_rxdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txreqflit_dbg
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/hnf_txrspflit_dbg
add wave -noupdate -expand -group icn -expand /tb_chi_system/u_chi_icn/hnf_txdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxreqflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_rxdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txrspflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/snf_txdatflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/rnf_rxsnpflit_dbg
add wave -noupdate -expand -group icn /tb_chi_system/u_chi_icn/hnf_txsnpflit_dbg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 287
configure wave -valuecolwidth 100
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
WaveRestoreZoom {10860270 ps} {25145690 ps}
