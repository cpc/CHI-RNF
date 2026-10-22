/*
* Copyright (c) 2024 Beijing Institute of Open Source Chip
* OpenNoC is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
* See the Mulan PSL v2 for more details.
*
* Author:
*    Jianxing Wang <wangjianxing@bosc.ac.cn>
*/

`ifndef MESH_WRAPPER_2X2_H
`define MESH_WRAPPER_2X2_H

module mesh_wrapper_2x2
#(
  parameter REQ_FLIT_WIDTH,
  parameter RSP_FLIT_WIDTH,
  parameter DAT_FLIT_WIDTH,
  parameter SNP_FLIT_WIDTH
)
(
  input clk
  ,input reset

  //============================================================
  //CHI XP_0_0_P0 RNF signal
  //============================================================
  ,input    XP_0_0_P0_TXSACTIVE
  ,output   XP_0_0_P0_RXSACTIVE

  ,input    XP_0_0_P0_TXLINKACTIVEREQ
  ,output   XP_0_0_P0_TXLINKACTIVEACK
  ,output   XP_0_0_P0_RXLINKACTIVEREQ
  ,input    XP_0_0_P0_RXLINKACTIVEACK

  //TXREQ Channel
  ,input    XP_0_0_P0_TXREQFLITPEND
  ,input    XP_0_0_P0_TXREQFLITV
  ,input    [REQ_FLIT_WIDTH-1:0] XP_0_0_P0_TXREQFLIT
  ,output   XP_0_0_P0_TXREQLCRDV


  //TXRSP Channel
  ,input    XP_0_0_P0_TXRSPFLITPEND
  ,input    XP_0_0_P0_TXRSPFLITV
  ,input    [RSP_FLIT_WIDTH-1:0] XP_0_0_P0_TXRSPFLIT
  ,output   XP_0_0_P0_TXRSPLCRDV

  //RXRSP Channel
  ,output   XP_0_0_P0_RXRSPFLITPEND
  ,output   XP_0_0_P0_RXRSPFLITV
  ,output   [RSP_FLIT_WIDTH-1:0] XP_0_0_P0_RXRSPFLIT
  ,input    XP_0_0_P0_RXRSPLCRDV

  //TXDAT Channel
  ,input    XP_0_0_P0_TXDATFLITPEND
  ,input    XP_0_0_P0_TXDATFLITV
  ,input    [DAT_FLIT_WIDTH-1:0] XP_0_0_P0_TXDATFLIT
  ,output   XP_0_0_P0_TXDATLCRDV

  //RXDAT Channel
  ,output   XP_0_0_P0_RXDATFLITPEND
  ,output   XP_0_0_P0_RXDATFLITV
  ,output   [DAT_FLIT_WIDTH-1:0] XP_0_0_P0_RXDATFLIT
  ,input    XP_0_0_P0_RXDATLCRDV


  //RXSNP Channel
  ,output   XP_0_0_P0_RXSNPFLITPEND
  ,output   XP_0_0_P0_RXSNPFLITV
  ,output   [SNP_FLIT_WIDTH-1:0] XP_0_0_P0_RXSNPFLIT
  ,input    XP_0_0_P0_RXSNPLCRDV

  //============================================================
  //CHI XP_0_0_P1 RNF signal
  //============================================================
  ,input    XP_0_0_P1_TXSACTIVE
  ,output   XP_0_0_P1_RXSACTIVE

  ,input    XP_0_0_P1_TXLINKACTIVEREQ
  ,output   XP_0_0_P1_TXLINKACTIVEACK
  ,output   XP_0_0_P1_RXLINKACTIVEREQ
  ,input    XP_0_0_P1_RXLINKACTIVEACK

  //TXREQ Channel
  ,input    XP_0_0_P1_TXREQFLITPEND
  ,input    XP_0_0_P1_TXREQFLITV
  ,input    [REQ_FLIT_WIDTH-1:0] XP_0_0_P1_TXREQFLIT
  ,output   XP_0_0_P1_TXREQLCRDV


  //TXRSP Channel
  ,input    XP_0_0_P1_TXRSPFLITPEND
  ,input    XP_0_0_P1_TXRSPFLITV
  ,input    [RSP_FLIT_WIDTH-1:0] XP_0_0_P1_TXRSPFLIT
  ,output   XP_0_0_P1_TXRSPLCRDV

  //RXRSP Channel
  ,output   XP_0_0_P1_RXRSPFLITPEND
  ,output   XP_0_0_P1_RXRSPFLITV
  ,output   [RSP_FLIT_WIDTH-1:0] XP_0_0_P1_RXRSPFLIT
  ,input    XP_0_0_P1_RXRSPLCRDV

  //TXDAT Channel
  ,input    XP_0_0_P1_TXDATFLITPEND
  ,input    XP_0_0_P1_TXDATFLITV
  ,input    [DAT_FLIT_WIDTH-1:0] XP_0_0_P1_TXDATFLIT
  ,output   XP_0_0_P1_TXDATLCRDV

  //RXDAT Channel
  ,output   XP_0_0_P1_RXDATFLITPEND
  ,output   XP_0_0_P1_RXDATFLITV
  ,output   [DAT_FLIT_WIDTH-1:0] XP_0_0_P1_RXDATFLIT
  ,input    XP_0_0_P1_RXDATLCRDV


  //RXSNP Channel
  ,output   XP_0_0_P1_RXSNPFLITPEND
  ,output   XP_0_0_P1_RXSNPFLITV
  ,output   [SNP_FLIT_WIDTH-1:0] XP_0_0_P1_RXSNPFLIT
  ,input    XP_0_0_P1_RXSNPLCRDV
  //============================================================
  //CHI XP_1_0_P0 HNF signal
  //============================================================
  ,input    XP_1_0_P0_TXSACTIVE
  ,output   XP_1_0_P0_RXSACTIVE

  ,input    XP_1_0_P0_TXLINKACTIVEREQ
  ,output   XP_1_0_P0_TXLINKACTIVEACK
  ,output   XP_1_0_P0_RXLINKACTIVEREQ
  ,input    XP_1_0_P0_RXLINKACTIVEACK

  //TXREQ Channel
  ,input    XP_1_0_P0_TXREQFLITPEND
  ,input    XP_1_0_P0_TXREQFLITV
  ,input    [REQ_FLIT_WIDTH-1:0] XP_1_0_P0_TXREQFLIT
  ,output   XP_1_0_P0_TXREQLCRDV

  //RXREQ Channel
  ,output   XP_1_0_P0_RXREQFLITPEND
  ,output   XP_1_0_P0_RXREQFLITV
  ,output   [REQ_FLIT_WIDTH-1:0] XP_1_0_P0_RXREQFLIT
  ,input    XP_1_0_P0_RXREQLCRDV

  //TXRSP Channel
  ,input    XP_1_0_P0_TXRSPFLITPEND
  ,input    XP_1_0_P0_TXRSPFLITV
  ,input    [RSP_FLIT_WIDTH-1:0] XP_1_0_P0_TXRSPFLIT
  ,output   XP_1_0_P0_TXRSPLCRDV

  //RXRSP Channel
  ,output   XP_1_0_P0_RXRSPFLITPEND
  ,output   XP_1_0_P0_RXRSPFLITV
  ,output   [RSP_FLIT_WIDTH-1:0] XP_1_0_P0_RXRSPFLIT
  ,input    XP_1_0_P0_RXRSPLCRDV

  //TXDAT Channel
  ,input    XP_1_0_P0_TXDATFLITPEND
  ,input    XP_1_0_P0_TXDATFLITV
  ,input    [DAT_FLIT_WIDTH-1:0] XP_1_0_P0_TXDATFLIT
  ,output   XP_1_0_P0_TXDATLCRDV

  //RXDAT Channel
  ,output   XP_1_0_P0_RXDATFLITPEND
  ,output   XP_1_0_P0_RXDATFLITV
  ,output   [DAT_FLIT_WIDTH-1:0] XP_1_0_P0_RXDATFLIT
  ,input    XP_1_0_P0_RXDATLCRDV

  //TXSNP Channel
  ,input    XP_1_0_P0_TXSNPFLITPEND
  ,input    XP_1_0_P0_TXSNPFLITV
  ,input    [SNP_FLIT_WIDTH+7-1:0] XP_1_0_P0_TXSNPFLIT
  ,output   XP_1_0_P0_TXSNPLCRDV


  //============================================================
  //CHI XP_1_1_P0 SNF signal
  //============================================================
  ,input    XP_1_1_P0_TXSACTIVE
  ,output   XP_1_1_P0_RXSACTIVE

  ,input    XP_1_1_P0_TXLINKACTIVEREQ
  ,output   XP_1_1_P0_TXLINKACTIVEACK
  ,output   XP_1_1_P0_RXLINKACTIVEREQ
  ,input    XP_1_1_P0_RXLINKACTIVEACK


  //RXREQ Channel
  ,output   XP_1_1_P0_RXREQFLITPEND
  ,output   XP_1_1_P0_RXREQFLITV
  ,output   [REQ_FLIT_WIDTH-1:0] XP_1_1_P0_RXREQFLIT
  ,input    XP_1_1_P0_RXREQLCRDV

  //TXRSP Channel
  ,input    XP_1_1_P0_TXRSPFLITPEND
  ,input    XP_1_1_P0_TXRSPFLITV
  ,input    [RSP_FLIT_WIDTH-1:0] XP_1_1_P0_TXRSPFLIT
  ,output   XP_1_1_P0_TXRSPLCRDV


  //TXDAT Channel
  ,input    XP_1_1_P0_TXDATFLITPEND
  ,input    XP_1_1_P0_TXDATFLITV
  ,input    [DAT_FLIT_WIDTH-1:0] XP_1_1_P0_TXDATFLIT
  ,output   XP_1_1_P0_TXDATLCRDV

  //RXDAT Channel
  ,output   XP_1_1_P0_RXDATFLITPEND
  ,output   XP_1_1_P0_RXDATFLITV
  ,output   [DAT_FLIT_WIDTH-1:0] XP_1_1_P0_RXDATFLIT
  ,input    XP_1_1_P0_RXDATLCRDV



);

  
  // Generate Horizontal signals

  wire m_reqflitv_00_10;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_00_10;
  wire m_reqlcrdv_00_10;

  wire m_reqflitv_10_00;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_10_00;
  wire m_reqlcrdv_10_00;

  wire m_datflitv_00_10;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_00_10;
  wire m_datlcrdv_00_10;

  wire m_datflitv_10_00;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_10_00;
  wire m_datlcrdv_10_00;

  wire m_rspflitv_00_10;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_00_10;
  wire m_rsplcrdv_00_10;

  wire m_rspflitv_10_00;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_10_00;
  wire m_rsplcrdv_10_00;

  wire m_snpflitv_00_10;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_00_10;
  wire m_snplcrdv_00_10;

  wire m_snpflitv_10_00;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_10_00;
  wire m_snplcrdv_10_00;

  wire m_reqflitv_01_11;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_01_11;
  wire m_reqlcrdv_01_11;

  wire m_reqflitv_11_01;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_11_01;
  wire m_reqlcrdv_11_01;

  wire m_datflitv_01_11;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_01_11;
  wire m_datlcrdv_01_11;

  wire m_datflitv_11_01;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_11_01;
  wire m_datlcrdv_11_01;

  wire m_rspflitv_01_11;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_01_11;
  wire m_rsplcrdv_01_11;

  wire m_rspflitv_11_01;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_11_01;
  wire m_rsplcrdv_11_01;

  wire m_snpflitv_01_11;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_01_11;
  wire m_snplcrdv_01_11;

  wire m_snpflitv_11_01;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_11_01;
  wire m_snplcrdv_11_01;

  // Generate Portrait signals

  wire m_reqflitv_00_01;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_00_01;
  wire m_reqlcrdv_00_01;

  wire m_reqflitv_01_00;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_01_00;
  wire m_reqlcrdv_01_00;

  wire m_datflitv_00_01;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_00_01;
  wire m_datlcrdv_00_01;

  wire m_datflitv_01_00;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_01_00;
  wire m_datlcrdv_01_00;

  wire m_rspflitv_00_01;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_00_01;
  wire m_rsplcrdv_00_01;

  wire m_rspflitv_01_00;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_01_00;
  wire m_rsplcrdv_01_00;

  wire m_snpflitv_00_01;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_00_01;
  wire m_snplcrdv_00_01;

  wire m_snpflitv_01_00;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_01_00;
  wire m_snplcrdv_01_00;

  wire m_reqflitv_10_11;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_10_11;
  wire m_reqlcrdv_10_11;

  wire m_reqflitv_11_10;
  wire [REQ_FLIT_WIDTH-1:0] m_reqflit_11_10;
  wire m_reqlcrdv_11_10;

  wire m_datflitv_10_11;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_10_11;
  wire m_datlcrdv_10_11;

  wire m_datflitv_11_10;
  wire [DAT_FLIT_WIDTH-1:0] m_datflit_11_10;
  wire m_datlcrdv_11_10;

  wire m_rspflitv_10_11;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_10_11;
  wire m_rsplcrdv_10_11;

  wire m_rspflitv_11_10;
  wire [RSP_FLIT_WIDTH-1:0] m_rspflit_11_10;
  wire m_rsplcrdv_11_10;

  wire m_snpflitv_10_11;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_10_11;
  wire m_snplcrdv_10_11;

  wire m_snpflitv_11_10;
  wire [SNP_FLIT_WIDTH+7-1:0] m_snpflit_11_10;
  wire m_snplcrdv_11_10;

    chi_xp_node #(
		.REQ_FLIT_WIDTH(REQ_FLIT_WIDTH),
		.RSP_FLIT_WIDTH(RSP_FLIT_WIDTH),
		.DAT_FLIT_WIDTH(DAT_FLIT_WIDTH),
		.SNP_FLIT_WIDTH(SNP_FLIT_WIDTH+7),
		.SNP_TGTID_OFFSET(SNP_FLIT_WIDTH)
    ) XP_0_0 (
        .clk (clk)
        ,.rst (reset)
        ,.my_xid(3'(0))
        ,.my_yid(3'(0))

        ,.TXLINKACTIVEREQ_P0(XP_0_0_P0_RXLINKACTIVEREQ)
        ,.TXLINKACTIVEACK_P0(XP_0_0_P0_RXLINKACTIVEACK)
        ,.RXLINKACTIVEREQ_P0(XP_0_0_P0_TXLINKACTIVEREQ)
        ,.RXLINKACTIVEACK_P0(XP_0_0_P0_TXLINKACTIVEACK)
        ,.TXSACTIVE_P0(XP_0_0_P0_RXSACTIVE)
        ,.RXSACTIVE_P0(XP_0_0_P0_TXSACTIVE)

        ,.TXLINKACTIVEREQ_P1(XP_0_0_P1_RXLINKACTIVEREQ)
        ,.TXLINKACTIVEACK_P1(XP_0_0_P1_RXLINKACTIVEACK)
        ,.RXLINKACTIVEREQ_P1(XP_0_0_P1_TXLINKACTIVEREQ)
        ,.RXLINKACTIVEACK_P1(XP_0_0_P1_TXLINKACTIVEACK)
        ,.TXSACTIVE_P1(XP_0_0_P1_RXSACTIVE)
        ,.RXSACTIVE_P1(XP_0_0_P1_TXSACTIVE) 


        //RXREQ Channel
        ,.RXREQFLITV_E (m_reqflitv_10_00)
        ,.RXREQFLIT_E  (m_reqflit_10_00)
        ,.RXREQLCRDV_E (m_reqlcrdv_10_00)
        ,.RXREQFLITV_W (1'b0)
        ,.RXREQFLIT_W  ()
        ,.RXREQLCRDV_W ()
        ,.RXREQFLITV_N (m_reqflitv_01_00)
        ,.RXREQFLIT_N  (m_reqflit_01_00)
        ,.RXREQLCRDV_N (m_reqlcrdv_01_00)
        ,.RXREQFLITV_S (1'b0)
        ,.RXREQFLIT_S  ()
        ,.RXREQLCRDV_S ()

        ,.RXREQFLITV_P0(XP_0_0_P0_TXREQFLITV)
        ,.RXREQFLIT_P0 (XP_0_0_P0_TXREQFLIT)
        ,.RXREQLCRDV_P0(XP_0_0_P0_TXREQLCRDV)

        ,.RXREQFLITV_P1(XP_0_0_P1_TXREQFLITV)
        ,.RXREQFLIT_P1 (XP_0_0_P1_TXREQFLIT)
        ,.RXREQLCRDV_P1(XP_0_0_P1_TXREQLCRDV)

        //TXREQ Channel
        ,.TXREQFLITV_E (m_reqflitv_00_10)
        ,.TXREQFLIT_E  (m_reqflit_00_10)
        ,.TXREQLCRDV_E (m_reqlcrdv_00_10)
        ,.TXREQFLITV_W ()
        ,.TXREQFLIT_W  ()
        ,.TXREQLCRDV_W (1'b0)
        ,.TXREQFLITV_N (m_reqflitv_00_01)
        ,.TXREQFLIT_N  (m_reqflit_00_01)
        ,.TXREQLCRDV_N (m_reqlcrdv_00_01)
        ,.TXREQFLITV_S ()
        ,.TXREQFLIT_S  ()
        ,.TXREQLCRDV_S (1'b0)
        ,.TXREQFLITV_P0 ()
        ,.TXREQFLIT_P0  ()
        ,.TXREQLCRDV_P0 (1'b0)

        ,.TXREQFLITV_P1 ()
        ,.TXREQFLIT_P1  ()
        ,.TXREQLCRDV_P1 (1'b0)

        //RXDAT Channel
        ,.RXDATFLITV_E (m_datflitv_10_00)
        ,.RXDATFLIT_E  (m_datflit_10_00)
        ,.RXDATLCRDV_E (m_datlcrdv_10_00)
        ,.RXDATFLITV_W (1'b0)
        ,.RXDATFLIT_W  ()
        ,.RXDATLCRDV_W ()
        ,.RXDATFLITV_N (m_datflitv_01_00)
        ,.RXDATFLIT_N  (m_datflit_01_00)
        ,.RXDATLCRDV_N (m_datlcrdv_01_00)
        ,.RXDATFLITV_S (1'b0)
        ,.RXDATFLIT_S  ()
        ,.RXDATLCRDV_S ()

        ,.RXDATFLITV_P0(XP_0_0_P0_TXDATFLITV)
        ,.RXDATFLIT_P0 (XP_0_0_P0_TXDATFLIT)
        ,.RXDATLCRDV_P0(XP_0_0_P0_TXDATLCRDV)

        
        ,.RXDATFLITV_P1(XP_0_0_P1_TXDATFLITV)
        ,.RXDATFLIT_P1 (XP_0_0_P1_TXDATFLIT)
        ,.RXDATLCRDV_P1(XP_0_0_P1_TXDATLCRDV)

        //TXDAT Channel
        ,.TXDATFLITV_E (m_datflitv_00_10)
        ,.TXDATFLIT_E  (m_datflit_00_10)
        ,.TXDATLCRDV_E (m_datlcrdv_00_10)
        ,.TXDATFLITV_W ()
        ,.TXDATFLIT_W  ()
        ,.TXDATLCRDV_W (1'b0)
        ,.TXDATFLITV_N (m_datflitv_00_01)
        ,.TXDATFLIT_N  (m_datflit_00_01)
        ,.TXDATLCRDV_N (m_datlcrdv_00_01)
        ,.TXDATFLITV_S ()
        ,.TXDATFLIT_S  ()
        ,.TXDATLCRDV_S (1'b0)
        ,.TXDATFLITV_P0(XP_0_0_P0_RXDATFLITV)
        ,.TXDATFLIT_P0 (XP_0_0_P0_RXDATFLIT)
        ,.TXDATLCRDV_P0(XP_0_0_P0_RXDATLCRDV)

        ,.TXDATFLITV_P1(XP_0_0_P1_RXDATFLITV)
        ,.TXDATFLIT_P1 (XP_0_0_P1_RXDATFLIT)
        ,.TXDATLCRDV_P1(XP_0_0_P1_RXDATLCRDV)

        //RXRSP Channel
        ,.RXRSPFLITV_E (m_rspflitv_10_00)
        ,.RXRSPFLIT_E  (m_rspflit_10_00)
        ,.RXRSPLCRDV_E (m_rsplcrdv_10_00)
        ,.RXRSPFLITV_W (1'b0)
        ,.RXRSPFLIT_W  ()
        ,.RXRSPLCRDV_W ()
        ,.RXRSPFLITV_N (m_rspflitv_01_00)
        ,.RXRSPFLIT_N  (m_rspflit_01_00)
        ,.RXRSPLCRDV_N (m_rsplcrdv_01_00)
        ,.RXRSPFLITV_S (1'b0)
        ,.RXRSPFLIT_S  ()
        ,.RXRSPLCRDV_S ()

        ,.RXRSPFLITV_P0(XP_0_0_P0_TXRSPFLITV)
        ,.RXRSPFLIT_P0 (XP_0_0_P0_TXRSPFLIT)
        ,.RXRSPLCRDV_P0(XP_0_0_P0_TXRSPLCRDV)

        
        ,.RXRSPFLITV_P1(XP_0_0_P1_TXRSPFLITV)
        ,.RXRSPFLIT_P1 (XP_0_0_P1_TXRSPFLIT)
        ,.RXRSPLCRDV_P1(XP_0_0_P1_TXRSPLCRDV)

        //TXRSP Channel
        ,.TXRSPFLITV_E (m_rspflitv_00_10)
        ,.TXRSPFLIT_E  (m_rspflit_00_10)
        ,.TXRSPLCRDV_E (m_rsplcrdv_00_10)
        ,.TXRSPFLITV_W ()
        ,.TXRSPFLIT_W  ()
        ,.TXRSPLCRDV_W (1'b0)
        ,.TXRSPFLITV_N (m_rspflitv_00_01)
        ,.TXRSPFLIT_N  (m_rspflit_00_01)
        ,.TXRSPLCRDV_N (m_rsplcrdv_00_01)
        ,.TXRSPFLITV_S ()
        ,.TXRSPFLIT_S  ()
        ,.TXRSPLCRDV_S (1'b0)
        ,.TXRSPFLITV_P0(XP_0_0_P0_RXRSPFLITV)
        ,.TXRSPFLIT_P0 (XP_0_0_P0_RXRSPFLIT)
        ,.TXRSPLCRDV_P0(XP_0_0_P0_RXRSPLCRDV)

        ,.TXRSPFLITV_P1(XP_0_0_P1_RXRSPFLITV)
        ,.TXRSPFLIT_P1 (XP_0_0_P1_RXRSPFLIT)
        ,.TXRSPLCRDV_P1(XP_0_0_P1_RXRSPLCRDV)

        //RXSNP Channel
        ,.RXSNPFLITV_E (m_snpflitv_10_00)
        ,.RXSNPFLIT_E  (m_snpflit_10_00)
        ,.RXSNPLCRDV_E (m_snplcrdv_10_00)
        ,.RXSNPFLITV_W (1'b0)
        ,.RXSNPFLIT_W  ()
        ,.RXSNPLCRDV_W ()
        ,.RXSNPFLITV_N (m_snpflitv_01_00)
        ,.RXSNPFLIT_N  (m_snpflit_01_00)
        ,.RXSNPLCRDV_N (m_snplcrdv_01_00)
        ,.RXSNPFLITV_S (1'b0)
        ,.RXSNPFLIT_S  ()
        ,.RXSNPLCRDV_S ()

        ,.RXSNPFLITV_P0 (1'b0)
        ,.RXSNPFLIT_P0  ()
        ,.RXSNPLCRDV_P0 ()

        ,.RXSNPFLITV_P1 (1'b0)
        ,.RXSNPFLIT_P1  ()
        ,.RXSNPLCRDV_P1 ()

        //TXSNP Channel
        ,.TXSNPFLITV_E (m_snpflitv_00_10)
        ,.TXSNPFLIT_E  (m_snpflit_00_10)
        ,.TXSNPLCRDV_E (m_snplcrdv_00_10)
        ,.TXSNPFLITV_W ()
        ,.TXSNPFLIT_W  ()
        ,.TXSNPLCRDV_W (1'b0)
        ,.TXSNPFLITV_N (m_snpflitv_00_01)
        ,.TXSNPFLIT_N  (m_snpflit_00_01)
        ,.TXSNPLCRDV_N (m_snplcrdv_00_01)
        ,.TXSNPFLITV_S ()
        ,.TXSNPFLIT_S  ()
        ,.TXSNPLCRDV_S (1'b0)
        ,.TXSNPFLITV_P0(XP_0_0_P0_RXSNPFLITV)
        ,.TXSNPFLIT_P0 (XP_0_0_P0_RXSNPFLIT)
        ,.TXSNPLCRDV_P0(XP_0_0_P0_RXSNPLCRDV)

        ,.TXSNPFLITV_P1(XP_0_0_P1_RXSNPFLITV)
        ,.TXSNPFLIT_P1 (XP_0_0_P1_RXSNPFLIT)
        ,.TXSNPLCRDV_P1(XP_0_0_P1_RXSNPLCRDV)
    );
    chi_xp_node #(
		.REQ_FLIT_WIDTH(REQ_FLIT_WIDTH),
		.RSP_FLIT_WIDTH(RSP_FLIT_WIDTH),
		.DAT_FLIT_WIDTH(DAT_FLIT_WIDTH),
		.SNP_FLIT_WIDTH(SNP_FLIT_WIDTH+7),
		.SNP_TGTID_OFFSET(SNP_FLIT_WIDTH)
    ) XP_1_0 (
        .clk (clk)
        ,.rst (reset)
        ,.my_xid(3'(1))
        ,.my_yid(3'(0))

        ,.TXLINKACTIVEREQ_P0(XP_1_0_P0_RXLINKACTIVEREQ)
        ,.TXLINKACTIVEACK_P0(XP_1_0_P0_RXLINKACTIVEACK)
        ,.RXLINKACTIVEREQ_P0(XP_1_0_P0_TXLINKACTIVEREQ)
        ,.RXLINKACTIVEACK_P0(XP_1_0_P0_TXLINKACTIVEACK)
        ,.TXSACTIVE_P0(XP_1_0_P0_RXSACTIVE)
        ,.RXSACTIVE_P0(XP_1_0_P0_TXSACTIVE)



        //RXREQ Channel
        ,.RXREQFLITV_E (1'b0)
        ,.RXREQFLIT_E  ()
        ,.RXREQLCRDV_E ()
        ,.RXREQFLITV_W (m_reqflitv_00_10)
        ,.RXREQFLIT_W  (m_reqflit_00_10)
        ,.RXREQLCRDV_W (m_reqlcrdv_00_10)
        ,.RXREQFLITV_N (m_reqflitv_11_10)
        ,.RXREQFLIT_N  (m_reqflit_11_10)
        ,.RXREQLCRDV_N (m_reqlcrdv_11_10)
        ,.RXREQFLITV_S (1'b0)
        ,.RXREQFLIT_S  ()
        ,.RXREQLCRDV_S ()

        ,.RXREQFLITV_P0(XP_1_0_P0_TXREQFLITV)
        ,.RXREQFLIT_P0 (XP_1_0_P0_TXREQFLIT)
        ,.RXREQLCRDV_P0(XP_1_0_P0_TXREQLCRDV)

        ,.RXREQFLITV_P1 (1'b0)
        ,.RXREQFLIT_P1  ()
        ,.RXREQLCRDV_P1 ()

        //TXREQ Channel
        ,.TXREQFLITV_E ()
        ,.TXREQFLIT_E  ()
        ,.TXREQLCRDV_E (1'b0)
        ,.TXREQFLITV_W (m_reqflitv_10_00)
        ,.TXREQFLIT_W  (m_reqflit_10_00)
        ,.TXREQLCRDV_W (m_reqlcrdv_10_00)
        ,.TXREQFLITV_N (m_reqflitv_10_11)
        ,.TXREQFLIT_N  (m_reqflit_10_11)
        ,.TXREQLCRDV_N (m_reqlcrdv_10_11)
        ,.TXREQFLITV_S ()
        ,.TXREQFLIT_S  ()
        ,.TXREQLCRDV_S (1'b0)
        ,.TXREQFLITV_P0(XP_1_0_P0_RXREQFLITV)
        ,.TXREQFLIT_P0 (XP_1_0_P0_RXREQFLIT)
        ,.TXREQLCRDV_P0(XP_1_0_P0_RXREQLCRDV)

        ,.TXREQFLITV_P1 ()
        ,.TXREQFLIT_P1  ()
        ,.TXREQLCRDV_P1 (1'b0)

        //RXDAT Channel
        ,.RXDATFLITV_E (1'b0)
        ,.RXDATFLIT_E  ()
        ,.RXDATLCRDV_E ()
        ,.RXDATFLITV_W (m_datflitv_00_10)
        ,.RXDATFLIT_W  (m_datflit_00_10)
        ,.RXDATLCRDV_W (m_datlcrdv_00_10)
        ,.RXDATFLITV_N (m_datflitv_11_10)
        ,.RXDATFLIT_N  (m_datflit_11_10)
        ,.RXDATLCRDV_N (m_datlcrdv_11_10)
        ,.RXDATFLITV_S (1'b0)
        ,.RXDATFLIT_S  ()
        ,.RXDATLCRDV_S ()

        ,.RXDATFLITV_P0(XP_1_0_P0_TXDATFLITV)
        ,.RXDATFLIT_P0 (XP_1_0_P0_TXDATFLIT)
        ,.RXDATLCRDV_P0(XP_1_0_P0_TXDATLCRDV)

        
        ,.RXDATFLITV_P1 (1'b0)
        ,.RXDATFLIT_P1  ()
        ,.RXDATLCRDV_P1 ()

        //TXDAT Channel
        ,.TXDATFLITV_E ()
        ,.TXDATFLIT_E  ()
        ,.TXDATLCRDV_E (1'b0)
        ,.TXDATFLITV_W (m_datflitv_10_00)
        ,.TXDATFLIT_W  (m_datflit_10_00)
        ,.TXDATLCRDV_W (m_datlcrdv_10_00)
        ,.TXDATFLITV_N (m_datflitv_10_11)
        ,.TXDATFLIT_N  (m_datflit_10_11)
        ,.TXDATLCRDV_N (m_datlcrdv_10_11)
        ,.TXDATFLITV_S ()
        ,.TXDATFLIT_S  ()
        ,.TXDATLCRDV_S (1'b0)
        ,.TXDATFLITV_P0(XP_1_0_P0_RXDATFLITV)
        ,.TXDATFLIT_P0 (XP_1_0_P0_RXDATFLIT)
        ,.TXDATLCRDV_P0(XP_1_0_P0_RXDATLCRDV)

        ,.TXDATFLITV_P1 ()
        ,.TXDATFLIT_P1  ()
        ,.TXDATLCRDV_P1 (1'b0)

        //RXRSP Channel
        ,.RXRSPFLITV_E (1'b0)
        ,.RXRSPFLIT_E  ()
        ,.RXRSPLCRDV_E ()
        ,.RXRSPFLITV_W (m_rspflitv_00_10)
        ,.RXRSPFLIT_W  (m_rspflit_00_10)
        ,.RXRSPLCRDV_W (m_rsplcrdv_00_10)
        ,.RXRSPFLITV_N (m_rspflitv_11_10)
        ,.RXRSPFLIT_N  (m_rspflit_11_10)
        ,.RXRSPLCRDV_N (m_rsplcrdv_11_10)
        ,.RXRSPFLITV_S (1'b0)
        ,.RXRSPFLIT_S  ()
        ,.RXRSPLCRDV_S ()

        ,.RXRSPFLITV_P0(XP_1_0_P0_TXRSPFLITV)
        ,.RXRSPFLIT_P0 (XP_1_0_P0_TXRSPFLIT)
        ,.RXRSPLCRDV_P0(XP_1_0_P0_TXRSPLCRDV)

        
        ,.RXRSPFLITV_P1 (1'b0)
        ,.RXRSPFLIT_P1  ()
        ,.RXRSPLCRDV_P1 ()

        //TXRSP Channel
        ,.TXRSPFLITV_E ()
        ,.TXRSPFLIT_E  ()
        ,.TXRSPLCRDV_E (1'b0)
        ,.TXRSPFLITV_W (m_rspflitv_10_00)
        ,.TXRSPFLIT_W  (m_rspflit_10_00)
        ,.TXRSPLCRDV_W (m_rsplcrdv_10_00)
        ,.TXRSPFLITV_N (m_rspflitv_10_11)
        ,.TXRSPFLIT_N  (m_rspflit_10_11)
        ,.TXRSPLCRDV_N (m_rsplcrdv_10_11)
        ,.TXRSPFLITV_S ()
        ,.TXRSPFLIT_S  ()
        ,.TXRSPLCRDV_S (1'b0)
        ,.TXRSPFLITV_P0(XP_1_0_P0_RXRSPFLITV)
        ,.TXRSPFLIT_P0 (XP_1_0_P0_RXRSPFLIT)
        ,.TXRSPLCRDV_P0(XP_1_0_P0_RXRSPLCRDV)

        ,.TXRSPFLITV_P1 ()
        ,.TXRSPFLIT_P1  ()
        ,.TXRSPLCRDV_P1 (1'b0)

        //RXSNP Channel
        ,.RXSNPFLITV_E (1'b0)
        ,.RXSNPFLIT_E  ()
        ,.RXSNPLCRDV_E ()
        ,.RXSNPFLITV_W (m_snpflitv_00_10)
        ,.RXSNPFLIT_W  (m_snpflit_00_10)
        ,.RXSNPLCRDV_W (m_snplcrdv_00_10)
        ,.RXSNPFLITV_N (m_snpflitv_11_10)
        ,.RXSNPFLIT_N  (m_snpflit_11_10)
        ,.RXSNPLCRDV_N (m_snplcrdv_11_10)
        ,.RXSNPFLITV_S (1'b0)
        ,.RXSNPFLIT_S  ()
        ,.RXSNPLCRDV_S ()

        ,.RXSNPFLITV_P0(XP_1_0_P0_TXSNPFLITV)
        ,.RXSNPFLIT_P0 (XP_1_0_P0_TXSNPFLIT)
        ,.RXSNPLCRDV_P0(XP_1_0_P0_TXSNPLCRDV)

        ,.RXSNPFLITV_P1 (1'b0)
        ,.RXSNPFLIT_P1  ()
        ,.RXSNPLCRDV_P1 ()

        //TXSNP Channel
        ,.TXSNPFLITV_E ()
        ,.TXSNPFLIT_E  ()
        ,.TXSNPLCRDV_E (1'b0)
        ,.TXSNPFLITV_W (m_snpflitv_10_00)
        ,.TXSNPFLIT_W  (m_snpflit_10_00)
        ,.TXSNPLCRDV_W (m_snplcrdv_10_00)
        ,.TXSNPFLITV_N (m_snpflitv_10_11)
        ,.TXSNPFLIT_N  (m_snpflit_10_11)
        ,.TXSNPLCRDV_N (m_snplcrdv_10_11)
        ,.TXSNPFLITV_S ()
        ,.TXSNPFLIT_S  ()
        ,.TXSNPLCRDV_S (1'b0)
        ,.TXSNPFLITV_P0 ()
        ,.TXSNPFLIT_P0  ()
        ,.TXSNPLCRDV_P0 (1'b0)

        ,.TXSNPFLITV_P1 ()
        ,.TXSNPFLIT_P1  ()
        ,.TXSNPLCRDV_P1 (1'b0)
    );
    chi_xp_node #(
		.REQ_FLIT_WIDTH(REQ_FLIT_WIDTH),
		.RSP_FLIT_WIDTH(RSP_FLIT_WIDTH),
		.DAT_FLIT_WIDTH(DAT_FLIT_WIDTH),
		.SNP_FLIT_WIDTH(SNP_FLIT_WIDTH+7),
		.SNP_TGTID_OFFSET(SNP_FLIT_WIDTH)
    ) XP_0_1 (
        .clk (clk)
        ,.rst (reset)
        ,.my_xid(3'(0))
        ,.my_yid(3'(1))




        //RXREQ Channel
        ,.RXREQFLITV_E (m_reqflitv_11_01)
        ,.RXREQFLIT_E  (m_reqflit_11_01)
        ,.RXREQLCRDV_E (m_reqlcrdv_11_01)
        ,.RXREQFLITV_W (1'b0)
        ,.RXREQFLIT_W  ()
        ,.RXREQLCRDV_W ()
        ,.RXREQFLITV_N (1'b0)
        ,.RXREQFLIT_N  ()
        ,.RXREQLCRDV_N ()
        ,.RXREQFLITV_S (m_reqflitv_00_01)
        ,.RXREQFLIT_S  (m_reqflit_00_01)
        ,.RXREQLCRDV_S (m_reqlcrdv_00_01)

        ,.RXREQFLITV_P0 (1'b0)
        ,.RXREQFLIT_P0  ()
        ,.RXREQLCRDV_P0 ()

        ,.RXREQFLITV_P1 (1'b0)
        ,.RXREQFLIT_P1  ()
        ,.RXREQLCRDV_P1 ()

        //TXREQ Channel
        ,.TXREQFLITV_E (m_reqflitv_01_11)
        ,.TXREQFLIT_E  (m_reqflit_01_11)
        ,.TXREQLCRDV_E (m_reqlcrdv_01_11)
        ,.TXREQFLITV_W ()
        ,.TXREQFLIT_W  ()
        ,.TXREQLCRDV_W (1'b0)
        ,.TXREQFLITV_N ()
        ,.TXREQFLIT_N  ()
        ,.TXREQLCRDV_N (1'b0)
        ,.TXREQFLITV_S (m_reqflitv_01_00)
        ,.TXREQFLIT_S  (m_reqflit_01_00)
        ,.TXREQLCRDV_S (m_reqlcrdv_01_00)
        ,.TXREQFLITV_P0 ()
        ,.TXREQFLIT_P0  ()
        ,.TXREQLCRDV_P0 (1'b0)

        ,.TXREQFLITV_P1 ()
        ,.TXREQFLIT_P1  ()
        ,.TXREQLCRDV_P1 (1'b0)

        //RXDAT Channel
        ,.RXDATFLITV_E (m_datflitv_11_01)
        ,.RXDATFLIT_E  (m_datflit_11_01)
        ,.RXDATLCRDV_E (m_datlcrdv_11_01)
        ,.RXDATFLITV_W (1'b0)
        ,.RXDATFLIT_W  ()
        ,.RXDATLCRDV_W ()
        ,.RXDATFLITV_N (1'b0)
        ,.RXDATFLIT_N  ()
        ,.RXDATLCRDV_N ()
        ,.RXDATFLITV_S (m_datflitv_00_01)
        ,.RXDATFLIT_S  (m_datflit_00_01)
        ,.RXDATLCRDV_S (m_datlcrdv_00_01)

        ,.RXDATFLITV_P0 (1'b0)
        ,.RXDATFLIT_P0  ()
        ,.RXDATLCRDV_P0 ()

        
        ,.RXDATFLITV_P1 (1'b0)
        ,.RXDATFLIT_P1  ()
        ,.RXDATLCRDV_P1 ()

        //TXDAT Channel
        ,.TXDATFLITV_E (m_datflitv_01_11)
        ,.TXDATFLIT_E  (m_datflit_01_11)
        ,.TXDATLCRDV_E (m_datlcrdv_01_11)
        ,.TXDATFLITV_W ()
        ,.TXDATFLIT_W  ()
        ,.TXDATLCRDV_W (1'b0)
        ,.TXDATFLITV_N ()
        ,.TXDATFLIT_N  ()
        ,.TXDATLCRDV_N (1'b0)
        ,.TXDATFLITV_S (m_datflitv_01_00)
        ,.TXDATFLIT_S  (m_datflit_01_00)
        ,.TXDATLCRDV_S (m_datlcrdv_01_00)
        ,.TXDATFLITV_P0 ()
        ,.TXDATFLIT_P0  ()
        ,.TXDATLCRDV_P0 (1'b0)

        ,.TXDATFLITV_P1 ()
        ,.TXDATFLIT_P1  ()
        ,.TXDATLCRDV_P1 (1'b0)

        //RXRSP Channel
        ,.RXRSPFLITV_E (m_rspflitv_11_01)
        ,.RXRSPFLIT_E  (m_rspflit_11_01)
        ,.RXRSPLCRDV_E (m_rsplcrdv_11_01)
        ,.RXRSPFLITV_W (1'b0)
        ,.RXRSPFLIT_W  ()
        ,.RXRSPLCRDV_W ()
        ,.RXRSPFLITV_N (1'b0)
        ,.RXRSPFLIT_N  ()
        ,.RXRSPLCRDV_N ()
        ,.RXRSPFLITV_S (m_rspflitv_00_01)
        ,.RXRSPFLIT_S  (m_rspflit_00_01)
        ,.RXRSPLCRDV_S (m_rsplcrdv_00_01)

        ,.RXRSPFLITV_P0 (1'b0)
        ,.RXRSPFLIT_P0  ()
        ,.RXRSPLCRDV_P0 ()

        
        ,.RXRSPFLITV_P1 (1'b0)
        ,.RXRSPFLIT_P1  ()
        ,.RXRSPLCRDV_P1 ()

        //TXRSP Channel
        ,.TXRSPFLITV_E (m_rspflitv_01_11)
        ,.TXRSPFLIT_E  (m_rspflit_01_11)
        ,.TXRSPLCRDV_E (m_rsplcrdv_01_11)
        ,.TXRSPFLITV_W ()
        ,.TXRSPFLIT_W  ()
        ,.TXRSPLCRDV_W (1'b0)
        ,.TXRSPFLITV_N ()
        ,.TXRSPFLIT_N  ()
        ,.TXRSPLCRDV_N (1'b0)
        ,.TXRSPFLITV_S (m_rspflitv_01_00)
        ,.TXRSPFLIT_S  (m_rspflit_01_00)
        ,.TXRSPLCRDV_S (m_rsplcrdv_01_00)
        ,.TXRSPFLITV_P0 ()
        ,.TXRSPFLIT_P0  ()
        ,.TXRSPLCRDV_P0 (1'b0)

        ,.TXRSPFLITV_P1 ()
        ,.TXRSPFLIT_P1  ()
        ,.TXRSPLCRDV_P1 (1'b0)

        //RXSNP Channel
        ,.RXSNPFLITV_E (m_snpflitv_11_01)
        ,.RXSNPFLIT_E  (m_snpflit_11_01)
        ,.RXSNPLCRDV_E (m_snplcrdv_11_01)
        ,.RXSNPFLITV_W (1'b0)
        ,.RXSNPFLIT_W  ()
        ,.RXSNPLCRDV_W ()
        ,.RXSNPFLITV_N (1'b0)
        ,.RXSNPFLIT_N  ()
        ,.RXSNPLCRDV_N ()
        ,.RXSNPFLITV_S (m_snpflitv_00_01)
        ,.RXSNPFLIT_S  (m_snpflit_00_01)
        ,.RXSNPLCRDV_S (m_snplcrdv_00_01)

        ,.RXSNPFLITV_P0 (1'b0)
        ,.RXSNPFLIT_P0  ()
        ,.RXSNPLCRDV_P0 ()

        ,.RXSNPFLITV_P1 (1'b0)
        ,.RXSNPFLIT_P1  ()
        ,.RXSNPLCRDV_P1 ()

        //TXSNP Channel
        ,.TXSNPFLITV_E (m_snpflitv_01_11)
        ,.TXSNPFLIT_E  (m_snpflit_01_11)
        ,.TXSNPLCRDV_E (m_snplcrdv_01_11)
        ,.TXSNPFLITV_W ()
        ,.TXSNPFLIT_W  ()
        ,.TXSNPLCRDV_W (1'b0)
        ,.TXSNPFLITV_N ()
        ,.TXSNPFLIT_N  ()
        ,.TXSNPLCRDV_N (1'b0)
        ,.TXSNPFLITV_S (m_snpflitv_01_00)
        ,.TXSNPFLIT_S  (m_snpflit_01_00)
        ,.TXSNPLCRDV_S (m_snplcrdv_01_00)
        ,.TXSNPFLITV_P0 ()
        ,.TXSNPFLIT_P0  ()
        ,.TXSNPLCRDV_P0 (1'b0)

        ,.TXSNPFLITV_P1 ()
        ,.TXSNPFLIT_P1  ()
        ,.TXSNPLCRDV_P1 (1'b0)
    );
    chi_xp_node #(
		.REQ_FLIT_WIDTH(REQ_FLIT_WIDTH),
		.RSP_FLIT_WIDTH(RSP_FLIT_WIDTH),
		.DAT_FLIT_WIDTH(DAT_FLIT_WIDTH),
		.SNP_FLIT_WIDTH(SNP_FLIT_WIDTH+7),
		.SNP_TGTID_OFFSET(SNP_FLIT_WIDTH)
    ) XP_1_1 (
        .clk (clk)
        ,.rst (reset)
        ,.my_xid(3'(1))
        ,.my_yid(3'(1))

        ,.TXLINKACTIVEREQ_P0(XP_1_1_P0_RXLINKACTIVEREQ)
        ,.TXLINKACTIVEACK_P0(XP_1_1_P0_RXLINKACTIVEACK)
        ,.RXLINKACTIVEREQ_P0(XP_1_1_P0_TXLINKACTIVEREQ)
        ,.RXLINKACTIVEACK_P0(XP_1_1_P0_TXLINKACTIVEACK)
        ,.TXSACTIVE_P0(XP_1_1_P0_RXSACTIVE)
        ,.RXSACTIVE_P0(XP_1_1_P0_TXSACTIVE)



        //RXREQ Channel
        ,.RXREQFLITV_E (1'b0)
        ,.RXREQFLIT_E  ()
        ,.RXREQLCRDV_E ()
        ,.RXREQFLITV_W (m_reqflitv_01_11)
        ,.RXREQFLIT_W  (m_reqflit_01_11)
        ,.RXREQLCRDV_W (m_reqlcrdv_01_11)
        ,.RXREQFLITV_N (1'b0)
        ,.RXREQFLIT_N  ()
        ,.RXREQLCRDV_N ()
        ,.RXREQFLITV_S (m_reqflitv_10_11)
        ,.RXREQFLIT_S  (m_reqflit_10_11)
        ,.RXREQLCRDV_S (m_reqlcrdv_10_11)

        ,.RXREQFLITV_P0 (1'b0)
        ,.RXREQFLIT_P0  ()
        ,.RXREQLCRDV_P0 ()

        ,.RXREQFLITV_P1 (1'b0)
        ,.RXREQFLIT_P1  ()
        ,.RXREQLCRDV_P1 ()

        //TXREQ Channel
        ,.TXREQFLITV_E ()
        ,.TXREQFLIT_E  ()
        ,.TXREQLCRDV_E (1'b0)
        ,.TXREQFLITV_W (m_reqflitv_11_01)
        ,.TXREQFLIT_W  (m_reqflit_11_01)
        ,.TXREQLCRDV_W (m_reqlcrdv_11_01)
        ,.TXREQFLITV_N ()
        ,.TXREQFLIT_N  ()
        ,.TXREQLCRDV_N (1'b0)
        ,.TXREQFLITV_S (m_reqflitv_11_10)
        ,.TXREQFLIT_S  (m_reqflit_11_10)
        ,.TXREQLCRDV_S (m_reqlcrdv_11_10)
        ,.TXREQFLITV_P0(XP_1_1_P0_RXREQFLITV)
        ,.TXREQFLIT_P0 (XP_1_1_P0_RXREQFLIT)
        ,.TXREQLCRDV_P0(XP_1_1_P0_RXREQLCRDV)

        ,.TXREQFLITV_P1 ()
        ,.TXREQFLIT_P1  ()
        ,.TXREQLCRDV_P1 (1'b0)

        //RXDAT Channel
        ,.RXDATFLITV_E (1'b0)
        ,.RXDATFLIT_E  ()
        ,.RXDATLCRDV_E ()
        ,.RXDATFLITV_W (m_datflitv_01_11)
        ,.RXDATFLIT_W  (m_datflit_01_11)
        ,.RXDATLCRDV_W (m_datlcrdv_01_11)
        ,.RXDATFLITV_N (1'b0)
        ,.RXDATFLIT_N  ()
        ,.RXDATLCRDV_N ()
        ,.RXDATFLITV_S (m_datflitv_10_11)
        ,.RXDATFLIT_S  (m_datflit_10_11)
        ,.RXDATLCRDV_S (m_datlcrdv_10_11)

        ,.RXDATFLITV_P0(XP_1_1_P0_TXDATFLITV)
        ,.RXDATFLIT_P0 (XP_1_1_P0_TXDATFLIT)
        ,.RXDATLCRDV_P0(XP_1_1_P0_TXDATLCRDV)

        
        ,.RXDATFLITV_P1 (1'b0)
        ,.RXDATFLIT_P1  ()
        ,.RXDATLCRDV_P1 ()

        //TXDAT Channel
        ,.TXDATFLITV_E ()
        ,.TXDATFLIT_E  ()
        ,.TXDATLCRDV_E (1'b0)
        ,.TXDATFLITV_W (m_datflitv_11_01)
        ,.TXDATFLIT_W  (m_datflit_11_01)
        ,.TXDATLCRDV_W (m_datlcrdv_11_01)
        ,.TXDATFLITV_N ()
        ,.TXDATFLIT_N  ()
        ,.TXDATLCRDV_N (1'b0)
        ,.TXDATFLITV_S (m_datflitv_11_10)
        ,.TXDATFLIT_S  (m_datflit_11_10)
        ,.TXDATLCRDV_S (m_datlcrdv_11_10)
        ,.TXDATFLITV_P0(XP_1_1_P0_RXDATFLITV)
        ,.TXDATFLIT_P0 (XP_1_1_P0_RXDATFLIT)
        ,.TXDATLCRDV_P0(XP_1_1_P0_RXDATLCRDV)

        ,.TXDATFLITV_P1 ()
        ,.TXDATFLIT_P1  ()
        ,.TXDATLCRDV_P1 (1'b0)

        //RXRSP Channel
        ,.RXRSPFLITV_E (1'b0)
        ,.RXRSPFLIT_E  ()
        ,.RXRSPLCRDV_E ()
        ,.RXRSPFLITV_W (m_rspflitv_01_11)
        ,.RXRSPFLIT_W  (m_rspflit_01_11)
        ,.RXRSPLCRDV_W (m_rsplcrdv_01_11)
        ,.RXRSPFLITV_N (1'b0)
        ,.RXRSPFLIT_N  ()
        ,.RXRSPLCRDV_N ()
        ,.RXRSPFLITV_S (m_rspflitv_10_11)
        ,.RXRSPFLIT_S  (m_rspflit_10_11)
        ,.RXRSPLCRDV_S (m_rsplcrdv_10_11)

        ,.RXRSPFLITV_P0(XP_1_1_P0_TXRSPFLITV)
        ,.RXRSPFLIT_P0 (XP_1_1_P0_TXRSPFLIT)
        ,.RXRSPLCRDV_P0(XP_1_1_P0_TXRSPLCRDV)

        
        ,.RXRSPFLITV_P1 (1'b0)
        ,.RXRSPFLIT_P1  ()
        ,.RXRSPLCRDV_P1 ()

        //TXRSP Channel
        ,.TXRSPFLITV_E ()
        ,.TXRSPFLIT_E  ()
        ,.TXRSPLCRDV_E (1'b0)
        ,.TXRSPFLITV_W (m_rspflitv_11_01)
        ,.TXRSPFLIT_W  (m_rspflit_11_01)
        ,.TXRSPLCRDV_W (m_rsplcrdv_11_01)
        ,.TXRSPFLITV_N ()
        ,.TXRSPFLIT_N  ()
        ,.TXRSPLCRDV_N (1'b0)
        ,.TXRSPFLITV_S (m_rspflitv_11_10)
        ,.TXRSPFLIT_S  (m_rspflit_11_10)
        ,.TXRSPLCRDV_S (m_rsplcrdv_11_10)
        ,.TXRSPFLITV_P0 ()
        ,.TXRSPFLIT_P0  ()
        ,.TXRSPLCRDV_P0 (1'b0)

        ,.TXRSPFLITV_P1 ()
        ,.TXRSPFLIT_P1  ()
        ,.TXRSPLCRDV_P1 (1'b0)

        //RXSNP Channel
        ,.RXSNPFLITV_E (1'b0)
        ,.RXSNPFLIT_E  ()
        ,.RXSNPLCRDV_E ()
        ,.RXSNPFLITV_W (m_snpflitv_01_11)
        ,.RXSNPFLIT_W  (m_snpflit_01_11)
        ,.RXSNPLCRDV_W (m_snplcrdv_01_11)
        ,.RXSNPFLITV_N (1'b0)
        ,.RXSNPFLIT_N  ()
        ,.RXSNPLCRDV_N ()
        ,.RXSNPFLITV_S (m_snpflitv_10_11)
        ,.RXSNPFLIT_S  (m_snpflit_10_11)
        ,.RXSNPLCRDV_S (m_snplcrdv_10_11)

        ,.RXSNPFLITV_P0 (1'b0)
        ,.RXSNPFLIT_P0  ()
        ,.RXSNPLCRDV_P0 ()

        ,.RXSNPFLITV_P1 (1'b0)
        ,.RXSNPFLIT_P1  ()
        ,.RXSNPLCRDV_P1 ()

        //TXSNP Channel
        ,.TXSNPFLITV_E ()
        ,.TXSNPFLIT_E  ()
        ,.TXSNPLCRDV_E (1'b0)
        ,.TXSNPFLITV_W (m_snpflitv_11_01)
        ,.TXSNPFLIT_W  (m_snpflit_11_01)
        ,.TXSNPLCRDV_W (m_snplcrdv_11_01)
        ,.TXSNPFLITV_N ()
        ,.TXSNPFLIT_N  ()
        ,.TXSNPLCRDV_N (1'b0)
        ,.TXSNPFLITV_S (m_snpflitv_11_10)
        ,.TXSNPFLIT_S  (m_snpflit_11_10)
        ,.TXSNPLCRDV_S (m_snplcrdv_11_10)
        ,.TXSNPFLITV_P0 ()
        ,.TXSNPFLIT_P0  ()
        ,.TXSNPLCRDV_P0 (1'b0)

        ,.TXSNPFLITV_P1 ()
        ,.TXSNPFLIT_P1  ()
        ,.TXSNPLCRDV_P1 (1'b0)
    );
endmodule
`endif /* MESH_WRAPPER_2X2_H */