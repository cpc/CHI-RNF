-- Copyright (c) 2016-2023 Tampere University.
--
-- This file is part of TTA-Based Codesign Environment (TCE).
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.
-------------------------------------------------------------------------------
-- Title      : testbench template for AlmaIF processors
-- Project    : OpenASIP
-------------------------------------------------------------------------------
-- File       : almaif-tb.vhdl.tmpl
-- Author     : Kati Tervo
-- Company    : TUNI
-- Created    : 2016-07-26
-- Last update: 2025-08-27
-- Platform   : 
-------------------------------------------------------------------------------
-- Description: Resets the processor, initializes instruction and data memories
--              via AXI and triggers execution
--              27.8.2025, Teemu Rinne: Run the tta with Openpiton caches and 
--                    AMBA CHI interface. 
--                    - TXREQ, RXDAT
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2016-07-26  1.0      tervo   Created
-- 2023-01-12  1.1      leppane Modified to a template so that it can be
--                              generated as AlmaIF testbench with optional
--                              AXI Master
-------------------------------------------------------------------------------

library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.tta_imem_mau.all;
use work.tta_globals.all;
use work.register_pkg.all;
use work.tce_util.all;
use std.textio.all;
use IEEE.std_logic_textio.all;
use work.tta_toplevel_params.all;
use work.cache_subsystem_pkg.all;
use work.wt_cache_pkg.all;
use work.riscv.all;

entity tta_almaif_tb is
  generic (
    imem_image                  : string := "prog.img";
    imem_image_2                : string := "prog2.img";
    dmem_image                  : string := "prog_data.img";
    log_path                    : string := "../verification/run.log";
    dmem_dump_path              : string := "../verification/dmem.log";
    resfile_path                : string := "../verification/result_file.log";
    clk_period                  : time := PERIOD;
    completion_signal_address_g : integer := 4);
end tta_almaif_tb;

architecture testbench of tta_almaif_tb is
  function mmax (a,b : integer) return integer is
  begin
    if (a > b) then return a; else return b; end if;
  end mmax;

  constant stall_threshold : real := 0.1;
  constant core_dbg_addrw : integer := 32;
  constant core_dbg_dataw : integer := 32;
  constant imem_word_width_c  : integer := (IMEMDATAWIDTH+31)/32;
  constant imem_word_sel_c    : integer := bit_width(imem_word_width_c-1);
  constant id_width_c         : integer := AXI_ID_WIDTH;
  constant axi_addrw_c        : integer := AXI_ADDR_WIDTH;

  constant rnf_count : integer := 2;

  signal clk       : std_logic := '0';
  signal clk_ena   : std_logic := '1';
  signal nreset    : std_logic;

  type data_arr is array (natural range <>) of std_logic_vector(31 downto 0);
  signal in_data   : data_arr(0 to 65535);


  type imem_arr is array (natural range <>) of std_logic_vector(15 downto 0);

  signal   val_out : std_logic_vector(31 downto 0);
  signal   vals_in  : data_arr(0 to 63);
  signal   vals_out : data_arr(0 to 63);

  -- AXI-lite interface
  signal s_axi_awaddr   : STD_LOGIC_VECTOR (rnf_count*32-1 downto 0);
  signal s_axi_awvalid  : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_awready  : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_wdata    : STD_LOGIC_VECTOR (rnf_count*32-1 downto 0);
  signal s_axi_wstrb    : STD_LOGIC_VECTOR (rnf_count*4-1 downto 0);
  signal s_axi_wvalid   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_wready   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_bresp    : STD_LOGIC_VECTOR (rnf_count*2-1 downto 0);
  signal s_axi_bvalid   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_bready   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_araddr   : STD_LOGIC_VECTOR (rnf_count*32-1 downto 0);
  signal s_axi_arvalid  : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_arready  : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_rdata    : STD_LOGIC_VECTOR (rnf_count*32-1 downto 0);
  signal s_axi_rresp    : STD_LOGIC_VECTOR (rnf_count*2-1 downto 0);
  signal s_axi_rvalid   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_rready   : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_awid     : STD_LOGIC_VECTOR (rnf_count*id_width_c-1 downto 0);
  signal s_axi_awlen    : STD_LOGIC_VECTOR (rnf_count*8-1 downto 0);
  signal s_axi_awsize   : STD_LOGIC_VECTOR (rnf_count*3-1 downto 0);
  signal s_axi_awburst  : STD_LOGIC_VECTOR (rnf_count*2-1 downto 0);
  signal s_axi_bid      : STD_LOGIC_VECTOR (rnf_count*id_width_c-1 downto 0);
  signal s_axi_arid     : STD_LOGIC_VECTOR (rnf_count*id_width_c-1 downto 0);
  signal s_axi_arlen    : STD_LOGIC_VECTOR (rnf_count*8-1 downto 0);
  signal s_axi_arsize   : STD_LOGIC_VECTOR (rnf_count*3-1 downto 0);
  signal s_axi_arburst  : STD_LOGIC_VECTOR (rnf_count*2-1 downto 0);
  signal s_axi_rid      : STD_LOGIC_VECTOR (rnf_count*id_width_c-1 downto 0);
  signal s_axi_rlast    : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  signal s_axi_wlast    : STD_LOGIC_VECTOR (rnf_count-1 downto 0);
  
  type lcrdv_arr  is array (natural range <>) of std_logic;
  type flitv      is array (natural range <>) of std_logic;
  type flitpend   is array (natural range <>) of std_logic;
  type rsp_flit   is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_WIDTH-1 downto 0);
  type dat_flit   is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_WIDTH-1 downto 0);
  type req_flit   is array (natural range <>) of std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
  type snp_flit   is array (natural range <>) of std_logic_vector(CHIE_SNP_FLIT_WIDTH-1 downto 0);

  ------CHI signals------
  signal rxrspflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxrspflit      : std_logic_vector(rnf_count*CHIE_RSP_FLIT_WIDTH-1 downto 0);
  signal rxrspflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- from data channel
  signal rxdatflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxdatflit      : std_logic_vector(rnf_count*CHIE_DAT_FLIT_WIDTH-1 downto 0);
  signal rxdatflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- to snoop channel         
  signal rxsnpflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxsnpflit      : std_logic_vector(rnf_count*CHIE_SNP_FLIT_WIDTH-1 downto 0);
  signal rxsnpflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- Credits back from responder?
  signal txreqlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal txrsplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal txdatlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  -- OUTPUTS
  -- Credits to requestor
  signal rxrsplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxdatlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxsnplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  -- to request channel
  signal txreqflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txreqflit      : std_logic_vector(rnf_count*CHIE_REQ_FLIT_WIDTH-1 downto 0);
  signal txreqflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- response channel
  signal txrspflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txrspflit      : std_logic_vector(rnf_count*CHIE_RSP_FLIT_WIDTH-1 downto 0);
  signal txrspflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- to data channel
  signal txdatflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txdatflit      : std_logic_vector(rnf_count*CHIE_DAT_FLIT_WIDTH-1 downto 0);
  signal txdatflitpend  : std_logic_vector(rnf_count-1 downto 0);

  -- Procedure signals
  signal txreq_procedure     : std_logic;
  signal rxdat_procedure     : std_logic;
  signal txrsp_procedure     : std_logic;
  signal rxsnp_procedure     : std_logic;
  signal count_procedure     : std_logic;
  signal rxrsp_procedure     : std_logic;
  -- Counters
  type counter_array is array (natural range <>) of std_logic_vector(31 downto 0);
  signal rxdat_crdt_count    : counter_array(rnf_count-1 downto 0);
  signal rxsnp_crdt_count    : counter_array(rnf_count-1 downto 0);
  signal rxrsp_crdt_count    : counter_array(rnf_count-1 downto 0);
  signal waiting_ack_count   : counter_array(rnf_count-1 downto 0);
  signal txrsp_crdt_counter  : counter_array(rnf_count-1 downto 0);
  signal txreq_crdt_counter  : counter_array(rnf_count-1 downto 0);
  signal txdat_crdt_counter  : counter_array(rnf_count-1 downto 0);

  -- Last Level Cache signals
  type cache_arr is array (natural range <>) of std_logic_vector(511 downto 0);
  signal LLCache : cache_arr(0 to 2047);    -- 64KB cache, 128KB because address shift from tta-32-bit-word-addr to OP-64-bit-dword-addr (half of the l1/l15 is unused, also the same in LLC)

  -- array for cacheline states
  -- 3=M, 2=E, 1=S, 0=I     (1=Valid if not in any RNF)
  type state_arr is array (natural range <>) of std_logic_vector(1 downto 0);
  signal cacheline_state : state_arr(0 to 2047);

  -- cacheline owners, "Directory"
  -- 1=has the cacheline, 0=doesn't have the cacheline
  type dir_arr is array (natural range <>) of std_logic_vector(rnf_count-1 downto 0);
  signal directory : dir_arr(0 to 2047);

-- Just for testing, how the OP L15 will answer when the LLC snoops the given unique cacheline
  signal snoop_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 
  signal snoop_txnid      : std_logic_vector(CHIE_REQ_FLIT_TXNID_WIDTH-1 downto 0); 

  signal update_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 
  signal update_txnid      : std_logic_vector(CHIE_REQ_FLIT_TXNID_WIDTH-1 downto 0); 


--  MSHR
  --signal mshr_read_idx : integer;
  --signal mshr_store_idx : integer;

  type mshr_valid         is array (natural range <>) of std_logic;
  type mshr_entry           is array (natural range <>) of std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
  -- MSHR entry
  -- signal mshr_valid         : mshr_valid(0 to TB_MSHR_WIDTH-1);
  -- signal mshr               : mshr_entry(0 to TB_MSHR_WIDTH-1);

  -- For WriteCleanFull requests
  --signal bypass_mshr_read_idx : integer;
  --signal bypass_mshr_store_idx : integer;
  -- bypass MSHR entry
  --signal bypass_mshr_valid         : mshr_valid(0 to TB_BYPASS_MSHR_WIDTH-1);
  --signal bypass_mshr               : mshr_entry(0 to TB_BYPASS_MSHR_WIDTH-1);

  type id_array is array (natural range <>) of integer;

  -- Transaction control signals 
  signal snp_done : std_logic;
  signal send_data : std_logic;
  signal send_response : std_logic;
  signal waiting_ack : std_logic;
  signal compack_received : std_logic;
  signal response_sent : std_logic;
  signal copybackdata_received : std_logic;
  signal send_snoop : std_logic;
  signal snoop_sent : std_logic;
  signal snoop_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0);
  signal data_flit_num : std_logic_vector(31 downto 0);
  signal snoopees : std_logic_vector(rnf_count-1 downto 0);
  signal sent_snoop_count : std_logic_vector(31 downto 0);
  signal reorder_done : std_logic;

                     
  signal txreq_valid        : std_logic;
  signal txreq_qos          : std_logic_vector(CHIE_REQ_FLIT_QOS_WIDTH-1 downto 0);
  signal txreq_tgtid        : std_logic_vector(CHIE_REQ_FLIT_TGTID_WIDTH-1 downto 0); 
  signal txreq_srcid        : std_logic_vector(CHIE_REQ_FLIT_SRCID_WIDTH-1 downto 0); 
  signal txreq_txnid        : std_logic_vector(CHIE_REQ_FLIT_TXNID_WIDTH-1 downto 0); 
  signal txreq_returnnid    : std_logic_vector(CHIE_REQ_FLIT_RETURNNID_WIDTH-1 downto 0);
  signal txreq_endian       : std_logic_vector(CHIE_REQ_FLIT_ENDIAN_WIDTH-1 downto 0);
  signal txreq_returntxnid  : std_logic_vector(CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1 downto 0);
  signal txreq_opcode       : std_logic_vector(CHIE_REQ_FLIT_OPCODE_WIDTH-1 downto 0);   
  signal txreq_size         : std_logic_vector(CHIE_REQ_FLIT_SIZE_WIDTH-1 downto 0);    
  signal txreq_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 
  signal txreq_ns           : std_logic_vector(CHIE_REQ_FLIT_NS_WIDTH-1 downto 0);      
  signal txreq_likelyshared : std_logic_vector(CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1 downto 0);
  signal txreq_allowretry   : std_logic_vector(CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1 downto 0);    
  signal txreq_order        : std_logic_vector(CHIE_REQ_FLIT_ORDER_WIDTH-1 downto 0);
  signal txreq_pcrdtype     : std_logic_vector(CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1 downto 0);
  signal txreq_memattr      : std_logic_vector(CHIE_REQ_FLIT_MEMATTR_WIDTH-1 downto 0);
  signal txreq_snpattr      : std_logic_vector(CHIE_REQ_FLIT_DODWT_WIDTH-1 downto 0); 
  signal txreq_lpid         : std_logic_vector(CHIE_REQ_FLIT_LPID_WIDTH-1 downto 0);
  signal txreq_excl_snoopme : std_logic_vector(CHIE_REQ_FLIT_EXCL_WIDTH-1 downto 0);
  signal txreq_expcompack   : std_logic_vector(CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1 downto 0);
  signal txreq_tagop        : std_logic_vector(CHIE_REQ_FLIT_TAGOP_WIDTH-1 downto 0);
  signal txreq_tracetag     : std_logic_vector(CHIE_REQ_FLIT_TRACETAG_WIDTH-1 downto 0);

  type rsp_qos_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_QOS_WIDTH-1 downto 0);
  type rsp_tgtid_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_TGTID_WIDTH-1 downto 0);  
  type rsp_srcid_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_SRCID_WIDTH-1 downto 0);    
  type rsp_txnid_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_TXNID_WIDTH-1 downto 0);    
  type rsp_opcode_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_OPCODE_WIDTH-1 downto 0);
  type rsp_resperr_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_RESPERR_WIDTH-1 downto 0); 
  type rsp_resp_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_RESP_WIDTH-1 downto 0);  
  type rsp_fwdstate_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_FWDSTATE_WIDTH-1 downto 0);   
  type rsp_cbusy_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_CBUSY_WIDTH-1 downto 0);       
  type rsp_dbid_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_DBID_WIDTH-1 downto 0);
  type rsp_pcrdtype_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1 downto 0);   
  type rsp_tagop_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_TAGOP_WIDTH-1 downto 0);       
  type rsp_tracetag_arr is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_TRACETAG_WIDTH-1 downto 0);

  signal txrsp_qos        : rsp_qos_arr(rnf_count-1 downto 0);
  signal txrsp_tgtid      : rsp_tgtid_arr(rnf_count-1 downto 0);  
  signal txrsp_srcid      : rsp_srcid_arr(rnf_count-1 downto 0);    
  signal txrsp_txnid      : rsp_txnid_arr(rnf_count-1 downto 0);    
  signal txrsp_opcode     : rsp_opcode_arr(rnf_count-1 downto 0);
  signal txrsp_resperr    : rsp_resperr_arr(rnf_count-1 downto 0); 
  signal txrsp_resp       : rsp_resp_arr(rnf_count-1 downto 0);  
  signal txrsp_fwdstate   : rsp_fwdstate_arr(rnf_count-1 downto 0);   
  signal txrsp_cbusy      : rsp_cbusy_arr(rnf_count-1 downto 0);       
  signal txrsp_dbid       : rsp_dbid_arr(rnf_count-1 downto 0);
  signal txrsp_pcrdtype   : rsp_pcrdtype_arr(rnf_count-1 downto 0);   
  signal txrsp_tagop      : rsp_tagop_arr(rnf_count-1 downto 0);       
  signal txrsp_tracetag   : rsp_tracetag_arr(rnf_count-1 downto 0);

  type dat_qos_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_QOS_WIDTH-1 downto 0);
  type dat_tgtid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TGTID_WIDTH-1 downto 0);
  type dat_srcid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_SRCID_WIDTH-1 downto 0);
  type dat_txnid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TXNID_WIDTH-1 downto 0);
  type dat_homenid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_HOMENID_WIDTH-1 downto 0); 
  type dat_opcode_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_OPCODE_WIDTH-1 downto 0);
  type dat_resperr_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_RESPERR_WIDTH-1 downto 0);
  type dat_resp_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_RESP_WIDTH-1 downto 0);
  type dat_fwdstate_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_FWDSTATE_WIDTH-1 downto 0);
  type dat_cbusy_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_CBUSY_WIDTH-1 downto 0);
  type dat_dbid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_DBID_WIDTH-1 downto 0);
  type dat_ccid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_CCID_WIDTH-1 downto 0);  
  type dat_dataid_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_DATAID_WIDTH-1 downto 0);
  type dat_tagop_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TAGOP_WIDTH-1 downto 0); -- not in CHI-B
  type dat_tag_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TAG_WIDTH-1 downto 0); -- not in CHI-B
  type dat_tu_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TU_WIDTH-1 downto 0); -- not in CHI-B
  type dat_tracetag_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_TRACETAG_WIDTH-1 downto 0); 
  type dat_be_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_BE_WIDTH-1 downto 0);
  type dat_data_arr is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_DATA_WIDTH-1 downto 0);

  signal txdat_qos        : dat_qos_arr(rnf_count-1 downto 0);
  signal txdat_tgtid      : dat_tgtid_arr(rnf_count-1 downto 0);
  signal txdat_srcid      : dat_srcid_arr(rnf_count-1 downto 0);
  signal txdat_txnid      : dat_txnid_arr(rnf_count-1 downto 0);
  signal txdat_homenid    : dat_homenid_arr(rnf_count-1 downto 0); 
  signal txdat_opcode     : dat_opcode_arr(rnf_count-1 downto 0);
  signal txdat_resperr    : dat_resperr_arr(rnf_count-1 downto 0);
  signal txdat_resp       : dat_resp_arr(rnf_count-1 downto 0);
  signal txdat_fwdstate   : dat_fwdstate_arr(rnf_count-1 downto 0);
  signal txdat_cbusy      : dat_cbusy_arr(rnf_count-1 downto 0);
  signal txdat_dbid       : dat_dbid_arr(rnf_count-1 downto 0);
  signal txdat_ccid       : dat_ccid_arr(rnf_count-1 downto 0);  
  signal txdat_dataid     : dat_dataid_arr(rnf_count-1 downto 0);
  signal txdat_tagop      : dat_tagop_arr(rnf_count-1 downto 0); -- not in CHI-B
  signal txdat_tag        : dat_tag_arr(rnf_count-1 downto 0); -- not in CHI-B
  signal txdat_tu         : dat_tu_arr(rnf_count-1 downto 0); -- not in CHI-B
  signal txdat_tracetag   : dat_tracetag_arr(rnf_count-1 downto 0); 
  signal txdat_be         : dat_be_arr(rnf_count-1 downto 0);
  signal txdat_data       : dat_data_arr(rnf_count-1 downto 0);




  function endian_swap(a : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(a'high downto 0);
    variable j   : integer;
  begin
    for i in 0 to (a'high+1)/8-1 loop
        j := (a'high+1)/8-1-i;
        result((i+1)*8-1 downto i*8) := a((j+1)*8-1 downto j*8);
    end loop;
    return result;
  end;

begin

    clk_gen : process(clk, clk_ena)
  begin
    if clk_ena = '1' then
      clk <= not clk after PERIOD/2;
    end if;
  end process clk_gen;

  dut : entity work.rnf_wrapper
    generic map (
      axi_addr_width_g => AXI_ADDR_WIDTH,
      axi_id_width_g => AXI_ID_WIDTH,
      local_mem_addrw_g => 0,
      corecount_g => rnf_count
    )
    port map (
      clk           => clk,
      rstx          => nreset,

      
      s_axi_awaddr  => s_axi_awaddr,  --(axi_addrw_c-1 downto 0),   Why sliced like this?
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata   => s_axi_wdata,
      s_axi_wstrb   => s_axi_wstrb,
      s_axi_wvalid  => s_axi_wvalid,
      s_axi_wready  => s_axi_wready,
      s_axi_bresp   => s_axi_bresp,
      s_axi_bvalid  => s_axi_bvalid,
      s_axi_bready  => s_axi_bready,
      s_axi_araddr  => s_axi_araddr,  --(axi_addrw_c-1 downto 0),   Why sliced like this?
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata   => s_axi_rdata,
      s_axi_rresp   => s_axi_rresp,
      s_axi_rvalid  => s_axi_rvalid,
      s_axi_rready  => s_axi_rready,
      -- Full AXI4
      s_axi_awid     => s_axi_awid,
      s_axi_awlen    => s_axi_awlen,
      s_axi_awsize   => s_axi_awsize,
      s_axi_awburst  => s_axi_awburst,
      s_axi_bid      => s_axi_bid,
      s_axi_arid     => s_axi_arid,
      s_axi_arlen    => s_axi_arlen,
      s_axi_arsize   => s_axi_arsize,
      s_axi_arburst  => s_axi_arburst,
      s_axi_rid      => s_axi_rid,
      s_axi_rlast    => s_axi_rlast,

      rxrspflitv => rxrspflitv,
      rxrspflit => rxrspflit,
      rxrspflitpend => rxrspflitpend,
      rxdatflitv => rxdatflitv,
      rxdatflit => rxdatflit,
      rxdatflitpend => rxdatflitpend,
      rxsnpflit => rxsnpflit,
      rxsnpflitv => rxsnpflitv,
      rxsnpflitpend => rxsnpflitpend,
      txreqlcrdv => txreqlcrdv,
      txrsplcrdv => txrsplcrdv,
      txdatlcrdv => txdatlcrdv,
      rxrsplcrdv => rxrsplcrdv,
      rxdatlcrdv => rxdatlcrdv,
      rxsnplcrdv => rxsnplcrdv,
      txreqflitv => txreqflitv,
      txreqflit => txreqflit,
      txreqflitpend => txreqflitpend,
      txrspflitv => txrspflitv,
      txrspflit => txrspflit,
      txrspflitpend => txrspflitpend,
      txdatflitv => txdatflitv,
      txdatflit => txdatflit,
      txdatflitpend => txdatflitpend


      );

  
  run_test : process


  variable rxdat_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable rxsnp_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable rxrsp_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txrsp_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txreq_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txdat_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable tmp_LLCache : cache_arr(0 to 2047) := (others=>(others=>'0'));
  variable tmp_cacheline_state : state_arr(0 to 2047) := (others=>(others=>'0'));
  variable tmp_directory : dir_arr(0 to 2047) := (others=>(others=>'0'));
  variable mshr_read_idx : integer := 0;
  variable mshr_store_idx : integer := 0;
  variable mshr_vld         : mshr_valid(0 to TB_MSHR_WIDTH-1) := (others=>'0');
  variable mshr               : mshr_entry(0 to TB_MSHR_WIDTH-1) := (others=>(others=>'0'));
  variable bypass_mshr_read_idx : integer := 0;
  variable bypass_mshr_store_idx : integer := 0;
  variable bypass_mshr_valid         : mshr_valid(0 to TB_BYPASS_MSHR_WIDTH-1) := (others=>'0');
  variable bypass_mshr               : mshr_entry(0 to TB_BYPASS_MSHR_WIDTH-1) := (others=>(others=>'0'));
  variable update_llc : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable invalid_snp_rsp : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable sent_snoop_count_var : integer := 0;
  variable decrement_rxdatcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable decrement_rxsnpcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable decrement_rxrspcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');


    -- Update CHI RX credit counts, to keep up where it's possible to send flits.
    -- If flit was sent, decrement the count
                                                          -- TESTATESSA TARKISTA ETTÄ COUNTERIEN PÄIVITYKSET TOIMII OIKEIN KUN NE TEHDÄÄN SAMALLA SYKLILLÄ ERI COREILTA, ETTEI TOINEN PÄÄLLEKIRJOITA VÄÄRIN
                                                          -- TODENNÄKÖISESTI NÄIN KÄY...
    procedure update_rxdat_credit_count ( constant core_id : in integer ) is
      -- variables
      variable rxdat_crdt_count_int : integer := 0;
    begin

      rxdat_crdt_count_int := to_integer(signed(rxdat_crdt_count_tmp(core_id)));

      -- update rxdat L credit count if it is signaled
      if (rxdatlcrdv(core_id) = '1') then
        rxdat_crdt_count_int := rxdat_crdt_count_int + 1;
      end if;
      if decrement_rxdatcrdt(core_id) = '1' then 
        rxdat_crdt_count_int := rxdat_crdt_count_int - 1;
      end if;

      rxdat_crdt_count_tmp(core_id) := std_logic_vector(to_unsigned(rxdat_crdt_count_int, 32));

    end procedure update_rxdat_credit_count;


    procedure update_rxsnp_credit_count ( constant core_id : in integer ) is
      -- variables
      variable rxsnp_crdt_count_int : integer := 0;
    begin

      rxsnp_crdt_count_int := to_integer(signed(rxsnp_crdt_count_tmp(core_id)));

      -- update rxsnp L credit count if it is signaled
      if (rxsnplcrdv(core_id) = '1') then
        rxsnp_crdt_count_int := rxsnp_crdt_count_int + 1;
      end if;
      if decrement_rxsnpcrdt(core_id) = '1' then
        rxsnp_crdt_count_int := rxsnp_crdt_count_int - 1;
      end if;

      rxsnp_crdt_count_tmp(core_id) := std_logic_vector(to_unsigned(rxsnp_crdt_count_int, 32));

    end procedure update_rxsnp_credit_count;


    procedure update_rxrsp_credit_count ( constant core_id : in integer ) is
      -- variables
      variable rxrsp_crdt_count_int : integer := 0;
    begin

      rxrsp_crdt_count_int := to_integer(signed(rxrsp_crdt_count_tmp(core_id)));

      -- update rxrsp L credit count if it is signaled
      if (rxrsplcrdv(core_id) = '1') then
        rxrsp_crdt_count_int := rxrsp_crdt_count_int + 1;
      end if;
      if decrement_rxrspcrdt(core_id) = '1' then
        rxrsp_crdt_count_int := rxrsp_crdt_count_int - 1;
      end if;

      rxrsp_crdt_count_tmp(core_id) := std_logic_vector(to_unsigned(rxrsp_crdt_count_int, 32));

    end procedure update_rxrsp_credit_count;




    -- Procedure to check if there is snoop responses or CompAcks
    procedure chi_txrsp_receive ( variable value : out std_logic_vector(31 downto 0) ) is
      -- variables
      variable waiting_ack_count_next : integer := 0;
      variable opcode : integer := 0;
      variable txnid : std_logic_vector(CHIE_RSP_FLIT_TXNID_WIDTH-1 downto 0) := (others => '0');
      variable srcid : std_logic_vector(CHIE_RSP_FLIT_SRCID_WIDTH-1 downto 0) := (others => '0');

      variable txrsp_qos_tmp        : rsp_qos_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txrsp_tgtid_tmp      : rsp_tgtid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));  
      variable txrsp_srcid_tmp      : rsp_srcid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));    
      variable txrsp_txnid_tmp      : rsp_txnid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));    
      variable txrsp_opcode_tmp     : rsp_opcode_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txrsp_resperr_tmp    : rsp_resperr_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txrsp_resp_tmp       : rsp_resp_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));  
      variable txrsp_fwdstate_tmp   : rsp_fwdstate_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));   
      variable txrsp_cbusy_tmp      : rsp_cbusy_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));       
      variable txrsp_dbid_tmp       : rsp_dbid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txrsp_pcrdtype_tmp   : rsp_pcrdtype_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));   
      variable txrsp_tagop_tmp      : rsp_tagop_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));       
      variable txrsp_tracetag_tmp   : rsp_tracetag_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txrsp_crdt_counter_tmp : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
    begin
      -- 
      txrsp_procedure <= '1';
      value := (others => '0');

      txrsp_crdt_counter_tmp := txrsp_crdt_counter;

      for core_id in 0 to rnf_count-1 loop
        opcode := to_integer(signed(txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)));
        txnid := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI+1);
        srcid := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI+1);

        -- TXRSP signals in
        if (txrspflitv(core_id) = '1') then
          txrsp_qos_tmp(core_id)         := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI downto (core_id*CHIE_RSP_FLIT_WIDTH));         
          txrsp_tgtid_tmp(core_id)       := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI+1);       
          txrsp_srcid_tmp(core_id)       := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI+1);       
          txrsp_txnid_tmp(core_id)       := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI+1);       
          txrsp_opcode_tmp(core_id)      := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1);  
          txrsp_resperr_tmp(core_id)     := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI+1); 
          txrsp_resp_tmp(core_id)        := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1);    
          txrsp_fwdstate_tmp(core_id)    := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI+1);    
          txrsp_cbusy_tmp(core_id)       := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI+1);       
          txrsp_dbid_tmp(core_id)        := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1);
          txrsp_pcrdtype_tmp(core_id)    := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI+1);    
          txrsp_tagop_tmp(core_id)       := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI+1);       
          txrsp_tracetag_tmp(core_id)    := txrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TRACETAG_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI+1);


          --if ( to_integer(signed(txrsp_opcode)) = 2 ) then     -- CHIE_COMPACK
          if ( opcode = 2 ) then -- CHIE_COMPACK
            if (srcid = txreq_srcid and txnid = txreq_txnid) then
              compack_received <= '1';
              waiting_ack_count_next := to_integer(signed(waiting_ack_count(core_id))) - 1;
              waiting_ack_count(core_id) <= std_logic_vector(to_unsigned(waiting_ack_count_next, 32));
            end if;

          elsif ( opcode = 1 ) then  -- CHIE_SNPRESP
            update_llc(core_id) := '1';
            invalid_snp_rsp(core_id) := '1';
            update_addr <= txreq_addr;
          end if;

          txrsp_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txrsp_crdt_counter_tmp(core_id))) - 1, 32));

        else 
          -- if valid is lowered (shouldnt be if already in this procedure)
        end if;
      end loop;

      txrsp_qos <= txrsp_qos_tmp;
      txrsp_tgtid <= txrsp_tgtid_tmp;
      txrsp_srcid <= txrsp_srcid_tmp;
      txrsp_txnid <= txrsp_txnid_tmp;
      txrsp_opcode <= txrsp_opcode_tmp;
      txrsp_resperr <= txrsp_resperr_tmp;
      txrsp_resp <= txrsp_resp_tmp;
      txrsp_fwdstate <= txrsp_fwdstate_tmp;
      txrsp_cbusy <= txrsp_cbusy_tmp;
      txrsp_dbid <= txrsp_dbid_tmp;
      txrsp_pcrdtype <= txrsp_pcrdtype_tmp;
      txrsp_tagop <= txrsp_tagop_tmp;
      txrsp_tracetag <= txrsp_tracetag_tmp;

      for id in 0 to rnf_count-1 loop
        if (to_integer(signed(txrsp_crdt_counter_tmp(id))) = 0) then
          txrsplcrdv(id) <= '1';
          txrsp_crdt_counter_tmp(id) := std_logic_vector(to_unsigned(to_integer(signed(txrsp_crdt_counter_tmp(id))) + 1, 32));
        end if;
      end loop;

      txrsp_crdt_counter <= txrsp_crdt_counter_tmp;

    end procedure chi_txrsp_receive;


    -- Update the LLC with the data coming from DAT-channel
    procedure update_LLC_txdat( variable value : out std_logic_vector(31 downto 0) ) is
      variable cacheline_addr : integer := 0;
    begin
      value := (others => '0');

      cacheline_addr := to_integer(unsigned(update_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6)));

      for core_id in 0 to rnf_count-1 loop
        if (update_llc(core_id) = '1') then

          -- Cacheline has been invalidated from local cache      ERI CACHETILATAPAUKSET
          if (invalid_snp_rsp(core_id) = '1') then
            if (txrsp_resp(core_id) = std_logic_vector(to_unsigned(0, CHIE_RSP_FLIT_RESP_WIDTH))) then -- I, line was invalidated from RNF
              tmp_directory(cacheline_addr)(core_id) := '0';
              tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
            elsif (txrsp_resp(core_id) = std_logic_vector(to_unsigned(1, CHIE_RSP_FLIT_RESP_WIDTH))) then -- SC, line was left to Shared state in RNF
              tmp_directory(cacheline_addr)(core_id) := '1';
              tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Shared              
            end if;
            sent_snoop_count_var := sent_snoop_count_var - 1;

          else 
            -- Update the received data to LLC
            if (txdat_dataid(core_id) = "00") then

              if (txdat_be(core_id)(0) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH/4-1 downto 0) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH/4-1 downto 0);
              end if;
              if (txdat_be(core_id)(8) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH/2-1 downto CHIE_DAT_FLIT_DATA_WIDTH/4)  := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH/2-1 downto CHIE_DAT_FLIT_DATA_WIDTH/4);
              end if;
              if (txdat_be(core_id)(16) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH-64-1 downto CHIE_DAT_FLIT_DATA_WIDTH/2) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-64-1 downto CHIE_DAT_FLIT_DATA_WIDTH/2);
              end if;
              if (txdat_be(core_id)(24) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH-1 downto CHIE_DAT_FLIT_DATA_WIDTH-64) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-1 downto CHIE_DAT_FLIT_DATA_WIDTH-64);
              end if;

            end if;

            if (txdat_dataid(core_id) = "10") then
              if (txdat_be(core_id)(0) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH+64-1 downto CHIE_DAT_FLIT_DATA_WIDTH) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH/4-1 downto 0);
              end if;
              if (txdat_be(core_id)(8) = '1' ) then
                tmp_LLCache(cacheline_addr)(CHIE_DAT_FLIT_DATA_WIDTH+128-1 downto CHIE_DAT_FLIT_DATA_WIDTH+64) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH/2-1 downto CHIE_DAT_FLIT_DATA_WIDTH/4);
              end if;
              if (txdat_be(core_id)(16) = '1' ) then
                tmp_LLCache(cacheline_addr)(2*CHIE_DAT_FLIT_DATA_WIDTH-64-1 downto CHIE_DAT_FLIT_DATA_WIDTH+128) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-64-1 downto CHIE_DAT_FLIT_DATA_WIDTH/2);
              end if;
              if (txdat_be(core_id)(24) = '1' ) then
                tmp_LLCache(cacheline_addr)(2*CHIE_DAT_FLIT_DATA_WIDTH-1 downto 2*CHIE_DAT_FLIT_DATA_WIDTH-64) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-1 downto CHIE_DAT_FLIT_DATA_WIDTH-64);
              end if;

              if (txdat_opcode(core_id) = std_logic_vector(to_unsigned(1, CHIE_DAT_FLIT_OPCODE_WIDTH)) or 
                  txdat_opcode(core_id) = std_logic_vector(to_unsigned(5, CHIE_DAT_FLIT_OPCODE_WIDTH))) then -- 1 or 5 CHIE_SNPRESPDATA
                if (txdat_resp(core_id) = std_logic_vector(to_unsigned(4, CHIE_DAT_FLIT_RESP_WIDTH))) then -- I_PD, line was invalidated from RNF
                  tmp_directory(cacheline_addr)(core_id) := '0';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
                elsif (txdat_resp(core_id) = std_logic_vector(to_unsigned(5, CHIE_DAT_FLIT_RESP_WIDTH))) then -- SC_PD, line was left to Shared state in RNF
                  tmp_directory(cacheline_addr)(core_id) := '1';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Shared       
                  -- TAKE INTO ACCOUNT THAT THIS SOULDN'T BE POSSIBLE WITH -PARTIAL- DATA RESPONSE ACCORDING TO CHI SPEC!! THE LINE SHOULD BE INVALIDATED FROM THE RNF IN THAT CASE        
                end if;
                sent_snoop_count_var := sent_snoop_count_var - 1;

              elsif (txdat_opcode(core_id) = std_logic_vector(to_unsigned(2, CHIE_DAT_FLIT_OPCODE_WIDTH))) then -- CHIE_COPYBACKWRDATA
                if (txreq_opcode = std_logic_vector(to_unsigned(23, CHIE_REQ_FLIT_OPCODE_WIDTH))) then -- CHIE_WRITECLEANFULL
                  tmp_directory(cacheline_addr)(core_id) := '1';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive
                elsif (txreq_opcode = std_logic_vector(to_unsigned(26, CHIE_REQ_FLIT_OPCODE_WIDTH))) then -- CHIE_WRITEBACKPTL
                  tmp_directory(cacheline_addr)(core_id) := '0';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
                end if;
                copybackdata_received <= '1';
              
              end if;
            end if;
          end if;

          update_llc(core_id) := '0';
          invalid_snp_rsp(core_id) := '0';
        end if;
      end loop;

    end procedure update_LLC_txdat;



    -- Procedure for receiving one DAT flit at the time (256bit data)
    procedure chi_txdat_receive ( variable value : out std_logic_vector(31 downto 0) ) is
      variable txdat_qos_tmp        : dat_qos_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_tgtid_tmp      : dat_tgtid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_srcid_tmp      : dat_srcid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_txnid_tmp      : dat_txnid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_homenid_tmp    : dat_homenid_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txdat_opcode_tmp     : dat_opcode_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_resperr_tmp    : dat_resperr_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_resp_tmp       : dat_resp_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_fwdstate_tmp   : dat_fwdstate_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_cbusy_tmp      : dat_cbusy_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_dbid_tmp       : dat_dbid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_ccid_tmp       : dat_ccid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));  
      variable txdat_dataid_tmp     : dat_dataid_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_tagop_tmp      : dat_tagop_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txdat_tag_tmp        : dat_tag_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txdat_tu_tmp         : dat_tu_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txdat_tracetag_tmp   : dat_tracetag_arr(rnf_count-1 downto 0) := (others=>(others=>'0')); 
      variable txdat_be_tmp         : dat_be_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable txdat_data_tmp       : dat_data_arr(rnf_count-1 downto 0) := (others=>(others=>'0'));
      variable update_llc_tmp       : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
      variable txdat_crdt_counter_tmp   : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
    begin
      value := (others => '0');
      update_llc_tmp := update_llc;
      txdat_crdt_counter_tmp := txdat_crdt_counter;

      for id in 0 to rnf_count-1 loop
        if txdatflitv(id) = '1' then
          txdat_qos_tmp(id)       := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI downto (id*CHIE_DAT_FLIT_WIDTH));
          txdat_tgtid_tmp(id)     := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI+1);
          txdat_srcid_tmp(id)     := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI+1);
          txdat_txnid_tmp(id)     := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI+1);
          txdat_homenid_tmp(id)   := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI+1); 
          txdat_opcode_tmp(id)    := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1);
          txdat_resperr_tmp(id)   := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI+1);
          txdat_resp_tmp(id)      := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1);
          txdat_fwdstate_tmp(id)  := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI+1);
          txdat_cbusy_tmp(id)     := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI+1);
          txdat_dbid_tmp(id)      := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI+1);
          txdat_ccid_tmp(id)      := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI+1);  
          txdat_dataid_tmp(id)    := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1);
          txdat_tagop_tmp(id)     := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI+1); -- not in CHI-B
          txdat_tag_tmp(id)       := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI+1); -- not in CHI-B
          txdat_tu_tmp(id)        := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI+1); -- not in CHI-B
          txdat_tracetag_tmp(id)  := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI+1); 
          txdat_be_tmp(id)        := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI+1);
          txdat_data_tmp(id)      := txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1);
          
          update_llc_tmp(id) := txdatflitv(id);

          txdat_crdt_counter_tmp(id) := std_logic_vector(to_unsigned(to_integer(signed(txdat_crdt_counter_tmp(id))) - 1, 32));

        end if;
      end loop;


      txdat_qos       <= txdat_qos_tmp;
      txdat_tgtid     <= txdat_tgtid_tmp;
      txdat_srcid     <= txdat_srcid_tmp;
      txdat_txnid     <= txdat_txnid_tmp;
      txdat_homenid   <= txdat_homenid_tmp;
      txdat_opcode    <= txdat_opcode_tmp;
      txdat_resperr   <= txdat_resperr_tmp;
      txdat_resp      <= txdat_resp_tmp;
      txdat_fwdstate  <= txdat_fwdstate_tmp;
      txdat_cbusy     <= txdat_cbusy_tmp;
      txdat_dbid      <= txdat_dbid_tmp;
      txdat_ccid      <= txdat_ccid_tmp;
      txdat_dataid    <= txdat_dataid_tmp;
      txdat_tagop     <= txdat_tagop_tmp;
      txdat_tag       <= txdat_tag_tmp;
      txdat_tu        <= txdat_tu_tmp;
      txdat_tracetag  <= txdat_tracetag_tmp;
      txdat_be        <= txdat_be_tmp;
      txdat_data      <= txdat_data_tmp;

      update_llc := update_llc_tmp;

      -- Set address to be used according to txnid when storing the data to LLC
      update_addr <= txreq_addr;  -- Receiving data is always requested by ongoing request

      -- Update L-credits
      for id in 0 to rnf_count-1 loop
          if (to_integer(signed(txdat_crdt_counter_tmp(id))) /= 2) then
            txdatlcrdv(id) <= '1';
            txdat_crdt_counter_tmp(id) := std_logic_vector(to_unsigned(to_integer(signed(txdat_crdt_counter_tmp(id))) + 1, 32));
          end if;
      end loop;

      txdat_crdt_counter <= txdat_crdt_counter_tmp;

    end procedure chi_txdat_receive;




    -- Procedure to wait one cycle and check given credits and incoming CompAcks every cycle 
    procedure wait_cycle_update_counters( variable update_rxdat_credit : in std_logic;
                                          variable update_rxsnp_credit : in std_logic;
                                          variable update_rxrsp_credit : in std_logic  ) is
      -- 
      variable value : std_logic_vector(31 downto 0) := (others => '0');
    begin
      count_procedure <= '1';

      sent_snoop_count <= std_logic_vector(to_unsigned(sent_snoop_count_var, 32));

      wait until rising_edge(clk);

      rxdat_crdt_count_tmp := rxdat_crdt_count;
      rxsnp_crdt_count_tmp := rxsnp_crdt_count;
      rxrsp_crdt_count_tmp := rxrsp_crdt_count;

      for id in 0 to rnf_count-1 loop
        update_rxdat_credit_count(id);
        update_rxsnp_credit_count(id);
        update_rxrsp_credit_count(id);
      end loop;

      rxdat_crdt_count <= rxdat_crdt_count_tmp;
      rxsnp_crdt_count <= rxsnp_crdt_count_tmp;
      rxrsp_crdt_count <= rxrsp_crdt_count_tmp;
      decrement_rxdatcrdt := (others => '0');
      decrement_rxsnpcrdt := (others => '0');
      decrement_rxrspcrdt := (others => '0');

      count_procedure <= '0';
    end procedure wait_cycle_update_counters;



    -- Procedure for sending snoops
      -- What is unknown in CHI spec is that how it should be declared which snoopees the snoops are sent, as the snp flit doesnt have the tgtid-field? 
          -- In the testbench it's obviously easy to just propagate it to certain RNF
    procedure chi_rxsnp_snoop ( variable value : out std_logic_vector(31 downto 0) ) is
      --
      variable tx_done : std_logic := '0';
      variable value0 : std_logic := '0';
      variable value1 : std_logic := '1';
    begin
      --
      value := (others => '0');

      rxsnp_procedure <= '1';

    -- RXSNP pakettien asetus usealle corelle pitäisi onnistua koska signaalia muokataan eri kohdista samassa prosessissa, TARKISTA VIELÄ SIMUSSA
      for id in 0 to rnf_count-1 loop
        if snoopees(id) = '1' then
          
          tx_done := '0';

          rxsnpflitpend(id) <= '1';

          if (to_integer(signed(rxsnp_crdt_count(id))) > 0) then

            rxsnpflitv(id) <= '1';
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_QOS_HI downto (id*CHIE_SNP_FLIT_WIDTH))                                    <= std_logic_vector(to_unsigned(1, CHIE_SNP_FLIT_QOS_WIDTH));
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_SRCID_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_QOS_HI+1)             <= std_logic_vector(to_unsigned(0, CHIE_SNP_FLIT_SRCID_WIDTH)); -- 0 is the home node
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TXNID_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_SRCID_HI+1)           <= snoop_txnid;
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_FWDNID_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TXNID_HI+1)          <= txreq_srcid;
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_FWDTXNID_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_FWDNID_HI+1)       <= snoop_txnid;

            --rxsnpflit(id)(CHIE_SNP_FLIT_OPCODE_HI downto CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= std_logic_vector(to_unsigned(1, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 1=SnpShared
            --rxsnpflit(id)(CHIE_SNP_FLIT_OPCODE_HI downto CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= std_logic_vector(to_unsigned(2, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 2=SnpClean
            --rxsnpflit(id)(CHIE_SNP_FLIT_OPCODE_HI downto CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= std_logic_vector(to_unsigned(7, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 7=SnpUnique
            --rxsnpflit(id)(CHIE_SNP_FLIT_OPCODE_HI downto CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= std_logic_vector(to_unsigned(8, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 8=SnpCleanShared
            --rxsnpflit(id)(CHIE_SNP_FLIT_OPCODE_HI downto CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= std_logic_vector(to_unsigned(9, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 9=SnpCleanInvalid
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_OPCODE_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= snoop_opcode;

            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_ADDR_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_OPCODE_HI+1)           <= snoop_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 3); -- indx 43 to 3
            -- rxsnpflit(id)(CHIE_SNP_FLIT_ADDR_HI downto CHIE_SNP_FLIT_OPCODE_HI+1)           <= (CHIE_SNP_FLIT_ADDR_HI downto CHIE_SNP_FLIT_OPCODE_HI+8 => '0', CHIE_SNP_FLIT_OPCODE_HI+7 downto CHIE_SNP_FLIT_OPCODE_HI+1 => '1'); -- Just random address

            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_NS_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_ADDR_HI+1)               <= "0";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_DONOTGOTOSD_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_NS_HI+1)        <= "0";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_RETTOSRC_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_DONOTGOTOSD_HI+1)  <= "1";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TRACETAG_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_RETTOSRC_HI+1)     <= "0";


            -- THIS IS USED WHEN RANDOM ADDRESS IS GIVEN FOR SNOOP INSTEAD OF THE update_addr!! So the received response won't mess up the LLC
            -- update_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0) <= (CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 10 => '0', 
            --                                                                                 9 downto 3 => '1', others => '0'); -- Just random address
            -- update_txnid <= snoop_txnid;


            tx_done := '1';

            decrement_rxsnpcrdt(id) := '1';

            sent_snoop_count_var := sent_snoop_count_var + 1;
            
          end if;
        end if;
      end loop;

      snoopees <= (others => '0');
      snoop_opcode <= (others => '0');
      send_snoop <= '0';
      snoop_sent <= '1';

    end procedure chi_rxsnp_snoop;



    -- Procedure for RXDAT response
    -- RXRSPtä EI PITÄISI OLLA LÄHETTÄMÄSSÄ KERRALLA KUIN 1 KPL (ei tarvetta loopille?)
    procedure chi_rxrsp_response ( variable value : out std_logic_vector(31 downto 0) ) is
      -- variables
      variable tx_done : std_logic := '0';

      variable value0 : std_logic := '0';
      variable value1 : std_logic := '1';

      variable core_id : integer := 0;

    begin

      core_id := to_integer(signed(txreq_srcid));

      rxrsp_procedure <= '1';
      rxrspflitpend(core_id) <= '1';

      if (to_integer(signed(rxrsp_crdt_count(core_id))) > 0) then
        if (to_integer(signed(txreq_opcode)) = 23 or to_integer(signed(txreq_opcode)) = 26) then   -- WriteCleanFull
          rxrspflitv(core_id) <= '1';

          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI downto (core_id*CHIE_RSP_FLIT_WIDTH))                                <= txreq_qos;         
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI+1)       <= txreq_srcid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI+1)     <= txreq_tgtid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI+1)     <= txreq_txnid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    <= std_logic_vector(to_unsigned(5, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_COMPDBIDRESP
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI+1)   <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1)      <= txreq_txnid; -- std_logic_vector(to_unsigned(2, CHIE_RSP_FLIT_DBID_WIDTH));
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI+1)   <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TRACETAG_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI+1)  <= (others => '0');


          send_response <= '0';
          response_sent <= '1';
          decrement_rxrspcrdt(core_id) := '1';

          tx_done := '1';
        end if;
      end if;


    end procedure chi_rxrsp_response;





    -- Procedure for RXDAT response
    procedure chi_rxdat_response ( variable value : out std_logic_vector(31 downto 0) ) is
      constant zeros : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
      constant snpshared_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(1, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 1=SnpShared
      constant snpclean_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(2, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 2=SnpClean
      constant snpunique_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(7, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 7=SnpUnique
      constant snpcleanshared_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(8, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 8=SnpCleanShared
      constant snpcleaninvalid_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(9, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 9=SnpCleanInvalid
      
      variable tx_done : std_logic := '0';
      variable flit_num : integer := 0;
      variable value0 : std_logic := '0';
      variable value1 : std_logic := '1';
      variable waiting_ack_count_next : integer := 0;

      variable core_id : integer := 0;
      variable cacheline_addr : integer := 0;
      variable opcode : integer := 0;
      variable is_owner : std_logic := '0';
      variable sharers : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
      variable snoop_mask : std_logic_vector(rnf_count-1 downto 0) := (others => '1');
      variable zero_mask : std_logic_vector(rnf_count-1 downto 0) := (others => '0');

    begin

      -- 
      rxdat_procedure <= '1';
      core_id := to_integer(signed(txreq_srcid));
      rxdatflitpend(core_id) <= '1';

      cacheline_addr := to_integer(unsigned(txreq_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6)));
      opcode := to_integer(signed(txreq_opcode));

      snoop_mask(core_id) := '0';
      sharers := snoop_mask and tmp_directory(cacheline_addr);
      is_owner := tmp_directory(cacheline_addr)(core_id);

      flit_num := to_integer(unsigned(data_flit_num)); 
      
      -- ReadUnique and line is in other RNFs -> SnpUnique
      if ( opcode = 7 and sharers /= zeros ) then
        send_snoop <= '1';
        send_data <= '0';
        snoopees <= sharers;
        snoop_addr <= txreq_addr;
        snoop_txnid <= txreq_txnid;
        snoop_opcode <= snpunique_opcode;

      -- ReadShared and line is Exclusive or Modified in other RNF -> SnpShared
      elsif ( opcode = 1 and sharers /= zeros and (tmp_cacheline_state(cacheline_addr) = "10" or tmp_cacheline_state(cacheline_addr) = "11") ) then
        send_snoop <= '1';
        send_data <= '0';
        snoopees <= sharers;
        snoop_addr <= txreq_addr;
        snoop_txnid <= txreq_txnid;
        snoop_opcode <= snpshared_opcode;

      -- Line is Shared or not owned by other RNFs -> CompData
      else 
        if (to_integer(signed(rxdat_crdt_count(core_id))) > 0) then
          
            -- qos and ids
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI downto (core_id*CHIE_DAT_FLIT_WIDTH))                                <= txreq_qos;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI+1)       <= txreq_srcid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI+1)     <= txreq_tgtid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI+1)     <= txreq_txnid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI+1)   <= txreq_tgtid;

            -- OPCODE
            if ( opcode = 7 or opcode = 1 ) then    -- ReadUnique or ReadShared
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1) <= std_logic_vector(to_unsigned(4, CHIE_DAT_FLIT_OPCODE_WIDTH)); -- CompData 
            end if;

            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI+1)  <= (others => '0');


            -- DATA AND CACHELINE STATE
              -- Data is sent back to RNF according to the Request type and cacheline state.
              -- If cacheline is invalid, random value is sent. If it is Shared/Exclusive, the stored value is sent back.
              -- If the requester wasn't already the owner of the cacheline, there is done snoops to the exclusive owners.

            -- ReadUnique
            if ( opcode = 7 ) then    
                  -- data could also be given in UniqueDirty-PassDirty state, for which the OP-RNF is expected to make WriteCleanFull request to update memory
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "010";  -- data is given as: not dirty, UniqueClean UC     --"110" would be UD_PD
              
              -- Cacheline in SHARED(/VALID) state, return stored value 
              if ( tmp_cacheline_state(cacheline_addr) = "01" ) then
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(255 downto 0);
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(511 downto 256);

                  sharers(core_id) := '1'; -- used sharers-var to update directory
                  tmp_directory(cacheline_addr) := sharers;
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive
                end if;

              
              -- Exclusive/Modified and owner, return stored value
              elsif ( is_owner = '1' and (tmp_cacheline_state(cacheline_addr) = "10" or tmp_cacheline_state(cacheline_addr) = "11") ) then
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(255 downto 0);
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(511 downto 256);
                end if;

              -- Invalid state, return new value and make owner
              elsif ( tmp_cacheline_state(cacheline_addr) = "00" ) then
                rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         
                          <= (CHIE_DAT_FLIT_DATA_HI downto CHIE_DAT_FLIT_BE_HI+8+1 => '0', CHIE_DAT_FLIT_BE_HI+8 downto CHIE_DAT_FLIT_BE_HI+1 => '1');

                  -- DataID of data packets and LLC update
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  --NOTE: OP gives addresses always with byte bits too (3 LSBits)
                  tmp_LLCache(cacheline_addr)(255 downto 0) :=  (255 downto 8 => '0', others => '1');  -- lowest byte as ones
                  --rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "110";--UDPD TEST
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511
                  tmp_LLCache(cacheline_addr)(511 downto 256) :=  (511 downto 264 => '0', others => '1');  -- 
                  
                  zero_mask(core_id) := '1';
                  tmp_directory(cacheline_addr) := zero_mask;
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive   --std_logic_vector(to_unsigned(3, 2));--UDPD TEST, Modified
                  --rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "110";--UDPD TEST
                end if;
              end if;

            -- ReadShared
            elsif ( opcode = 1 ) then 
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "001";  -- data is given as: not dirty, SharedClean SC

              -- Cacheline in Shared/Valid state, return stored value 
              if ( tmp_cacheline_state(cacheline_addr) = "01" ) then
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(255 downto 0);
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511  
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(511 downto 256);
                  
                  sharers(core_id) := '1'; -- used sharers-var to update directory
                  tmp_directory(cacheline_addr) := sharers;
                end if;
              
              -- Exclusive/Modified and owner, return stored value
              elsif ( is_owner = '1' and (tmp_cacheline_state(cacheline_addr) = "10" or tmp_cacheline_state(cacheline_addr) = "11") ) then
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(255 downto 0);
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= tmp_LLCache(cacheline_addr)(511 downto 256);
                end if;


              -- Invalid state, return new value
              elsif ( tmp_cacheline_state(cacheline_addr) = "00" ) then
                rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         <= (others => '1');  -- send data only as '1's

                  -- DataID of data packets and LLC update
                if (flit_num = 0) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "00";-- 0-255
                  tmp_LLCache(cacheline_addr)(255 downto 0) :=  (255 downto 8 => '0', others => '1');
                elsif (flit_num = 1) then
                  rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   <= "10";-- 256-511
                  tmp_LLCache(cacheline_addr)(511 downto 256) :=  (511 downto 264 => '0', others => '1');
                  
                  zero_mask(core_id) := '1';
                  tmp_directory(cacheline_addr) := zero_mask;
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Shared
                end if;
              end if;
            end if;



            -- FwdState, CBusy, DBID, CCID
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI+1)   <= (others => '0'); -- indicates data state in Snoopee in snoop responses with Direct Cache Transfer
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI+1)  <= (others => '0'); -- completer busyness, implemention defined
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI+1)      <= txreq_txnid; -- HNF's txnid, REQ's txnid given, used in CompAck response
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI+1)       <= txreq_addr(5 downto 4); -- requested 128 bit chunk, compared to DataID value in RNF                
            -- TagOP, Tag, TU, TraceTag, BE
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI+1)    <= (others => '0');  -- not in CHI B
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI+1)       <= (others => '0');  -- not in CHI B
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI+1)          <= (others => '0');  -- not in CHI B
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI+1)     <= (others => '0');
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI+1)     <= (others => '0');  -- inapplicable with Read response data transfers (the whole line must be valid)

            
            -- fill the rest of the flit, for some reason the datflit width is defined wider in OpenNoC than CHI specifies for 256data
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_WIDTH-1 downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI+1)       <= (others => '0');  

            rxdatflitv(core_id) <= '1';

            decrement_rxdatcrdt(core_id) := '1';

            -- if data flits are sent, exit from the loop
            if (flit_num = 1) then
              tx_done := '1';

                waiting_ack_count_next := to_integer(signed(waiting_ack_count(core_id))) + 1;
                waiting_ack_count(core_id) <= std_logic_vector(to_unsigned(waiting_ack_count_next, 32));


              -- THIS FOR TESTING HOW L15 ANSWERS TO SNOOPS (whole 64byte or just 16byte)
              -- if ( opcode = 7 and snp_done = '0' ) then
              --   update_addr <= txreq_addr;
              --   update_txnid <= txreq_txnid;
              -- end if;

              -- reset the data packet counter
              data_flit_num <= (others => '0');
              send_data <= '0';
              waiting_ack <= '1';

            else 
              flit_num := flit_num + 1;
              data_flit_num <= std_logic_vector(to_unsigned(flit_num, 32));
            end if;
        else 
          rxdatflitv(core_id) <= '0';
        end if; -- end of credit condition
      end if; -- end of snoop condition


    end procedure chi_rxdat_response;


    -- Procedure for receiving TXREQ transactions
    procedure chi_txreq_receive ( variable value : out std_logic_vector(31 downto 0) ) is
      -- variables
      variable tx_done : std_logic := '0';
      variable value1 : std_logic := '1';
      variable value0 : std_logic := '0';
      variable opcode : integer := 0;

      variable sort_array : id_array(0 to rnf_count-1);
      variable qos : integer := 0;
      variable qos2 : integer := 0;
      variable temp_id : integer := 0;
      variable core_id : integer := 0;

    begin

      -- 
      txreq_procedure <= '1';
      value := (others => '0');


      -- Init the sort array
      for id in 0 to rnf_count-1 loop
        sort_array(id) := id;
      end loop;
      -- Sort incoming requests by QoS-value
        -- Could it be better if also core and address is compared to core and address of the last cycle?
          -- coherent ops wouldn't needed to be done everytime one core requests for a chunk of cacheline...
      if rnf_count > 1 then
        for i in 0 to rnf_count-1 loop
          for idx in 0 to rnf_count-1 loop
            qos := to_integer(unsigned(txreqflit((sort_array(idx)*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_QOS_HI downto (sort_array(idx)*CHIE_REQ_FLIT_WIDTH))));
            qos2 := to_integer(unsigned(txreqflit((sort_array(idx+1)*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_QOS_HI downto (sort_array(idx+1)*CHIE_REQ_FLIT_WIDTH))));
            if (qos < qos2) then
              temp_id := sort_array(idx);
              sort_array(idx) := sort_array(idx+1);
              sort_array(idx+1) := temp_id;
            end if;
            if idx = rnf_count-2 then
              exit;
            end if;
          end loop;
        end loop;
      end if;

      -- Allocate requests to mshr
      for order_id in 0 to rnf_count-1 loop

        core_id := sort_array(order_id);

        if (txreqflitv(core_id) = '1') then
          opcode := to_integer(signed(txreqflit((core_id*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_OPCODE_HI downto (core_id*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_RETURNTXNID_HI+1)));

          if (opcode = 23 or opcode = 26) then -- WriteCleanFull
            bypass_mshr_valid(bypass_mshr_store_idx)    := '1';
            bypass_mshr(bypass_mshr_store_idx)          := txreqflit(((core_id+1)*CHIE_REQ_FLIT_WIDTH)-1 downto (core_id*CHIE_REQ_FLIT_WIDTH));

            if (bypass_mshr_store_idx = TB_BYPASS_MSHR_WIDTH-1) then
              bypass_mshr_store_idx := 0;
            else
              bypass_mshr_store_idx := bypass_mshr_store_idx+1;
            end if;
            
          else
            mshr_vld(mshr_store_idx)               := '1';
            mshr(mshr_store_idx)                     := txreqflit(((core_id+1)*CHIE_REQ_FLIT_WIDTH)-1 downto (core_id*CHIE_REQ_FLIT_WIDTH));
            
            if (mshr_store_idx = TB_MSHR_WIDTH-1) then
              mshr_store_idx := 0;
            else
              mshr_store_idx := mshr_store_idx+1;
            end if;

          end if;
          txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) - 1, 32));
        end if;
      end loop;

    end procedure chi_txreq_receive;


    -- Take next pending transaction from MSHR
    -- WriteCleanFull transactions bypass others.
    procedure next_transaction( variable value : out std_logic_vector(31 downto 0) ) is
      variable opcode : integer := 0;
      variable core_id : integer := 0;

    begin
      value := (others => '0');


      -- Take next entry from MSHR
      if (bypass_mshr_valid(bypass_mshr_read_idx) = '1') then

        opcode := to_integer(signed(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1)));
        core_id := to_integer(signed(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1)));

        txreq_valid               <= bypass_mshr_valid(bypass_mshr_read_idx);
        txreq_qos                 <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_QOS_HI downto 0);
        txreq_tgtid               <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_TGTID_HI downto CHIE_REQ_FLIT_QOS_HI+1);
        txreq_srcid               <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1);
        txreq_txnid               <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_TXNID_HI downto CHIE_REQ_FLIT_SRCID_HI+1);
        txreq_returnnid           <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_RETURNNID_HI downto CHIE_REQ_FLIT_TXNID_HI+1);
        txreq_endian              <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ENDIAN_HI downto CHIE_REQ_FLIT_RETURNNID_HI+1);
        txreq_returntxnid         <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_RETURNTXNID_HI downto CHIE_REQ_FLIT_ENDIAN_HI+1);
        txreq_opcode              <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1);
        txreq_size                <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_SIZE_HI downto CHIE_REQ_FLIT_OPCODE_HI+1);
        txreq_addr                <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1);
        txreq_ns                  <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_NS_HI downto CHIE_REQ_FLIT_ADDR_HI+1);
        txreq_likelyshared        <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_LIKELYSHARED_HI downto CHIE_REQ_FLIT_NS_HI+1);
        txreq_allowretry          <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ALLOWRETRY_HI downto CHIE_REQ_FLIT_LIKELYSHARED_HI+1);
        txreq_order               <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ORDER_HI downto CHIE_REQ_FLIT_ALLOWRETRY_HI+1);
        txreq_pcrdtype            <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_PCRDTYPE_HI downto CHIE_REQ_FLIT_ORDER_HI+1);
        txreq_memattr             <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_MEMATTR_HI downto CHIE_REQ_FLIT_PCRDTYPE_HI+1);
        txreq_snpattr             <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_DODWT_HI downto CHIE_REQ_FLIT_MEMATTR_HI+1);
        txreq_lpid                <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_LPID_HI downto CHIE_REQ_FLIT_DODWT_HI+1);
        txreq_excl_snoopme        <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_EXCL_HI downto CHIE_REQ_FLIT_LPID_HI+1);
        txreq_expcompack          <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_EXPCOMPACK_HI downto CHIE_REQ_FLIT_EXCL_HI+1);
        txreq_tagop               <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_TAGOP_HI downto CHIE_REQ_FLIT_EXPCOMPACK_HI+1);
        txreq_tracetag            <= bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_TRACETAG_HI downto CHIE_REQ_FLIT_TAGOP_HI+1);

        -- WriteCleanFull/WritebackPtl
        if (opcode = 23 or opcode = 26) then
          send_response <= '1';
        else
          -- ??
        end if;

        -- Invalidate the entry when it's used
        bypass_mshr_valid(bypass_mshr_read_idx) := '0';
        bypass_mshr(bypass_mshr_read_idx) := (others => '0');

        -- Increase the read index
        if (bypass_mshr_read_idx = TB_BYPASS_MSHR_WIDTH-1) then
          bypass_mshr_read_idx := 0;
        else
          bypass_mshr_read_idx := bypass_mshr_read_idx+1;
        end if;

        -- Give L-credit to core which req was used
        if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= 2) then     -- 
          txreqlcrdv(core_id) <= '1';
          txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
        end if;

      elsif (mshr_vld(mshr_read_idx) = '1') then

        opcode := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1)));
        core_id := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1)));

        txreq_valid               <= mshr_vld(mshr_read_idx);
        txreq_qos                 <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_QOS_HI downto 0);
        txreq_tgtid               <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_TGTID_HI downto CHIE_REQ_FLIT_QOS_HI+1);
        txreq_srcid               <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1);
        txreq_txnid               <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_TXNID_HI downto CHIE_REQ_FLIT_SRCID_HI+1);
        txreq_returnnid           <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_RETURNNID_HI downto CHIE_REQ_FLIT_TXNID_HI+1);
        txreq_endian              <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_ENDIAN_HI downto CHIE_REQ_FLIT_RETURNNID_HI+1);
        txreq_returntxnid         <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_RETURNTXNID_HI downto CHIE_REQ_FLIT_ENDIAN_HI+1);
        txreq_opcode              <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1);
        txreq_size                <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_SIZE_HI downto CHIE_REQ_FLIT_OPCODE_HI+1);
        txreq_addr                <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1);
        txreq_ns                  <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_NS_HI downto CHIE_REQ_FLIT_ADDR_HI+1);
        txreq_likelyshared        <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_LIKELYSHARED_HI downto CHIE_REQ_FLIT_NS_HI+1);
        txreq_allowretry          <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_ALLOWRETRY_HI downto CHIE_REQ_FLIT_LIKELYSHARED_HI+1);
        txreq_order               <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_ORDER_HI downto CHIE_REQ_FLIT_ALLOWRETRY_HI+1);
        txreq_pcrdtype            <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_PCRDTYPE_HI downto CHIE_REQ_FLIT_ORDER_HI+1);
        txreq_memattr             <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_MEMATTR_HI downto CHIE_REQ_FLIT_PCRDTYPE_HI+1);
        txreq_snpattr             <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_DODWT_HI downto CHIE_REQ_FLIT_MEMATTR_HI+1);
        txreq_lpid                <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_LPID_HI downto CHIE_REQ_FLIT_DODWT_HI+1);
        txreq_excl_snoopme        <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_EXCL_HI downto CHIE_REQ_FLIT_LPID_HI+1);
        txreq_expcompack          <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_EXPCOMPACK_HI downto CHIE_REQ_FLIT_EXCL_HI+1);
        txreq_tagop               <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_TAGOP_HI downto CHIE_REQ_FLIT_EXPCOMPACK_HI+1);
        txreq_tracetag            <= mshr(mshr_read_idx)(CHIE_REQ_FLIT_TRACETAG_HI downto CHIE_REQ_FLIT_TAGOP_HI+1);

        -- ReadUnique/ReadShared
        if (opcode = 7 or opcode = 1) then
          send_data <= '1';
        else
          --
        end if;

        -- Invalidate the entry when it's used
        mshr_vld(mshr_read_idx) := '0';
        mshr(mshr_read_idx) := (others => '0');

        -- Increase the read index
        if (mshr_read_idx = TB_MSHR_WIDTH-1) then
          mshr_read_idx := 0;
        else
          mshr_read_idx := mshr_read_idx+1;
        end if;

        -- Give L-credit to core which req was used
        if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= 2) then     -- 
          txreqlcrdv(core_id) <= '1';
          txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
        end if;

      else
        txreq_qos                 <= (others => '0');
        txreq_tgtid               <= (others => '0');
        txreq_srcid               <= (others => '0');
        txreq_txnid               <= (others => '0');
        txreq_returnnid           <= (others => '0');
        txreq_endian              <= (others => '0');
        txreq_returntxnid         <= (others => '0');
        txreq_opcode              <= (others => '0');
        txreq_size                <= (others => '0');
        txreq_addr                <= (others => '0');
        txreq_ns                  <= (others => '0');
        txreq_likelyshared        <= (others => '0');
        txreq_allowretry          <= (others => '0');
        txreq_order               <= (others => '0');
        txreq_pcrdtype            <= (others => '0');
        txreq_memattr             <= (others => '0');
        txreq_snpattr             <= (others => '0');
        txreq_lpid                <= (others => '0');
        txreq_excl_snoopme        <= (others => '0');
        txreq_expcompack          <= (others => '0');
        txreq_tagop               <= (others => '0');
        txreq_tracetag            <= (others => '0');
      end if;

    end procedure next_transaction;


    procedure check_next_mshr_enrty( variable value : out std_logic_vector(31 downto 0) ) is
      variable read_idx : integer := 0;
      variable next_idx : integer := 0;
      variable read_source : std_logic_vector(CHIE_REQ_FLIT_SRCID_WIDTH-1 downto 0);
      variable next_source : std_logic_vector(CHIE_REQ_FLIT_SRCID_WIDTH-1 downto 0);
      variable read_addrtag : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6);
      variable next_addrtag : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6);
      variable temp_entry : std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
    begin
      -- 
      value := (others => '0');

      -- Shift requests in mshr if they are from the same core requesting the same cacheline as the last request handled
      for i in 0 to rnf_count-1 loop
        for j in 0 to rnf_count-1 loop

          if (j = 0) then
            read_idx := mshr_read_idx;
            if (mshr_read_idx+1 = TB_MSHR_WIDTH) then 
              next_idx := 0;
            else 
              next_idx := mshr_read_idx+1;
            end if;
          else 
            if (read_idx+1 = TB_MSHR_WIDTH) then
              read_idx := 0;
            else
              read_idx := read_idx+1;
            end if;

            if (next_idx+1 = TB_MSHR_WIDTH) then
              next_idx := 0;
            else
              next_idx := next_idx+1;
            end if;
          end if;

          if (mshr_vld(read_idx) = '1' and mshr_vld(next_idx) = '1') then
            read_source := mshr(read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1);
            next_source := mshr(next_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1);
            read_addrtag := mshr(read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1+6);
            next_addrtag := mshr(next_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1+6);
            -- Check the cores and tags
            if ( read_source /= txreq_srcid and read_addrtag /= txreq_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6) ) then
              if ( next_source = txreq_srcid and next_addrtag = txreq_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 6) ) then
                temp_entry := mshr(read_idx);
                mshr(read_idx) := mshr(next_idx);
                mshr(next_idx) := temp_entry;

                reorder_done <= '1';
              end if;
            end if;
          else 
            exit;
          end if;
          if j = rnf_count-2 then
            exit;
          end if;
        end loop;
      end loop;

    end procedure check_next_mshr_enrty;


    
    procedure transaction_control( variable value : out std_logic_vector(31 downto 0) ) is
      --
    begin
      value := (others => '0');
        
      if send_data = '1' then
        chi_rxdat_response(value);
      end if;

      if send_response = '1' then
        chi_rxrsp_response(value);
      end if;

      if send_snoop = '1' then
        chi_rxsnp_snoop(value);
      elsif snoop_sent = '1' and sent_snoop_count_var = 0 then
        send_data <= '1';
        snoop_sent <= '0';
      end if;

      if (response_sent = '1' and copybackdata_received = '1') or (waiting_ack = '1' and compack_received = '1') then
        response_sent <= '0';
        copybackdata_received <= '0';
        waiting_ack <= '0';
        compack_received <= '0';
        txreq_valid <= '0';
      end if;
    
    end procedure transaction_control;


------------------------------------------------------------
------------------------------------------------------------
-- AXI PROCEDURES ------------------------------------------
    procedure axi_write (address : in integer;
                         value : in std_logic_vector(core_dbg_dataw - 1 downto 0);
                         core_id : in integer ) is

      variable addr_vec : std_logic_vector(core_dbg_addrw - 1 downto 0)
        := std_logic_vector(to_unsigned(address, core_dbg_addrw));

    begin
      s_axi_awlen((core_id+1)*8-1 downto core_id*8) <= (others => '0');

      s_axi_awvalid(core_id) <= '1';
      s_axi_awaddr((core_id+1)*32-1 downto core_id*32) <= std_logic_vector(resize(unsigned(addr_vec), 32));

      while s_axi_awready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      s_axi_awvalid(core_id) <= '0';
      s_axi_wvalid(core_id) <= '1';
      s_axi_wdata((core_id+1)*32-1 downto core_id*32) <= value;
      s_axi_wlast(core_id) <= '1';
      wait until rising_edge(clk);
      while s_axi_wready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      s_axi_wvalid(core_id) <= '0';
      wait until rising_edge(clk);

      s_axi_wlast(core_id) <= '0';
      s_axi_wvalid(core_id) <= '0';
      s_axi_awvalid(core_id) <= '0';

    end procedure axi_write;

    procedure axi_bwrite (address : in integer;
                          length  : in integer;
                          value : in data_arr;
                          core_id : in integer;
                          variable seed1 : inout integer;
                          variable seed2 : inout integer) is

      variable addr_vec : std_logic_vector(core_dbg_addrw - 1 downto 0)
        := std_logic_vector(to_unsigned(address, core_dbg_addrw));
      variable I : integer := 0;
      variable rand : real;

    begin
      s_axi_awlen((core_id+1)*8-1 downto core_id*8) <= std_logic_vector(to_unsigned(length-1, 8));

      s_axi_awvalid(core_id) <= '1';
      s_axi_awaddr((core_id+1)*32-1 downto core_id*32) <= std_logic_vector(resize(unsigned(addr_vec), 32));
      while s_axi_awready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      s_axi_awvalid(core_id) <= '0';

      while I < length loop
        uniform(seed1, seed2, rand);
        if rand < stall_threshold then
          s_axi_wvalid(core_id) <= '1';
          s_axi_wdata((core_id+1)*32-1 downto core_id*32) <= value(I);

          if I = length-1 then
            s_axi_wlast(core_id) <= '1';
          end if;

          wait until rising_edge(clk);
          while s_axi_wready(core_id) = '0' loop
            wait until rising_edge(clk);
          end loop;
          I := I + 1;
        else
          s_axi_wvalid(core_id) <= '0';
          wait until rising_edge(clk);
        end if;
      end loop;
      s_axi_wlast(core_id) <= '0';
      s_axi_wvalid(core_id) <= '0';
      wait until rising_edge(clk);
    end procedure axi_bwrite;

    procedure axi_bwrite_16 (address : in integer;
                             length  : in integer;
                             value : in imem_arr;
                             core_id : in integer) is

      variable addr_vec : std_logic_vector(core_dbg_addrw - 1 downto 0)
        := std_logic_vector(to_unsigned(address, core_dbg_addrw));

    begin
      s_axi_wstrb((core_id+1)*4-1 downto core_id*4) <= "1100";
      s_axi_awsize((core_id+1)*3-1 downto core_id*3) <= "001";
      s_axi_awlen((core_id+1)*8-1 downto core_id*8) <= std_logic_vector(to_unsigned(length-1, 8));

      s_axi_awvalid(core_id) <= '1';
      s_axi_awaddr((core_id+1)*32-1 downto core_id*32) <= std_logic_vector(resize(unsigned(addr_vec), 32));
      while s_axi_awready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      s_axi_awvalid(core_id) <= '0';

      for I in 0 to length-1 loop
        if I = length-1 then
          s_axi_wlast(core_id) <= '1';
        end if;

        s_axi_wvalid(core_id) <= '1';
        if s_axi_wstrb((core_id+1)*4-1 downto core_id*4) = "1100" then
          --s_axi_wdata(15 downto 0) <= value(I);         ((core_id+1)*32-1 downto core_id*32)
          --s_axi_wdata(31 downto 16) <= (others => '0');
          s_axi_wdata((core_id+1)*32-16-1 downto core_id*32) <= value(I);
          s_axi_wdata((core_id+1)*32-1 downto (core_id+1)*32-16) <= (others => '0');
        else
          s_axi_wdata((core_id+1)*32-16-1 downto core_id*32) <= (others => '0');
          s_axi_wdata((core_id+1)*32-1 downto (core_id+1)*32-16) <= value(I);
        end if;

        s_axi_wstrb((core_id+1)*4-1 downto core_id*4) <= not s_axi_wstrb((core_id+1)*4-1 downto core_id*4);
        wait until rising_edge(clk);
        while s_axi_wready(core_id) = '0' loop
          wait until rising_edge(clk);
        end loop;
      end loop;

      s_axi_wlast(core_id)  <= '0';
      s_axi_wvalid(core_id) <= '0';
      s_axi_wstrb((core_id+1)*4-1 downto core_id*4)  <= (others => '1');
      s_axi_awsize((core_id+1)*3-1 downto core_id*3) <= "010";
      wait until rising_edge(clk);
    end procedure axi_bwrite_16;

    procedure dbg_command (command : in integer;
                           core_id : in integer) is
      variable cmdreg : std_logic_vector(core_dbg_dataw - 1 downto 0) := (others => '0');
    begin
      cmdreg(command) := '1';
      axi_write(TTA_DEBUG_CMD*4, cmdreg, core_id);
    end procedure dbg_command;

    procedure axi_read (constant address : in integer;
                        variable value : out std_logic_vector(core_dbg_dataw - 1 downto 0);
                        core_id : in integer) is

      variable addr_vec : std_logic_vector(core_dbg_addrw - 1 downto 0)
        := std_logic_vector(to_unsigned(address, core_dbg_addrw));

    begin
      s_axi_arlen((core_id+1)*8-1 downto core_id*8) <= (others => '0');
      s_axi_arvalid(core_id) <= '1';

      s_axi_araddr((core_id+1)*32-1 downto core_id*32) <=std_logic_vector(resize(unsigned(addr_vec), 32));
      while s_axi_arready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      s_axi_arvalid(core_id) <= '0';
      --s_axi_awvalid(core_id) <= '0';
      s_axi_rready(core_id) <= '1';

      while s_axi_rvalid(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;
      value := s_axi_rdata((core_id+1)*32-1 downto core_id*32);
      wait until rising_edge(clk);
      s_axi_rready(core_id) <= '0';

    end procedure axi_read;

    procedure axi_bread (constant address : in integer;
                        constant length : in integer;
                        signal value : inout data_arr;
                        variable seed1 : inout integer;
                        variable seed2 : inout integer;
                        core_id : in integer) is

      variable addr_vec : std_logic_vector(core_dbg_addrw - 1 downto 0)
        := std_logic_vector(to_unsigned(address, core_dbg_addrw));
      variable I : integer := 0;
      variable rand : real;
    begin
      wait until rising_edge(clk);
      s_axi_arlen((core_id+1)*8-1 downto core_id*8) <= std_logic_vector(to_unsigned(length-1, 8));

      s_axi_arvalid(core_id) <= '1';
      s_axi_araddr((core_id+1)*32-1 downto core_id*32) <= std_logic_vector(resize(unsigned(addr_vec), 32));
      wait until rising_edge(clk);
      while s_axi_arready(core_id) = '0' loop
        wait until rising_edge(clk);
      end loop;

      s_axi_arvalid(core_id) <= '0';

      while I < length loop
        uniform(seed1, seed2, rand);
        if rand > stall_threshold then
          s_axi_rready(core_id) <= '1';

          wait until rising_edge(clk);
          while s_axi_rvalid(core_id) = '0' loop
            wait until rising_edge(clk);
          end loop;

          value(I) <= s_axi_rdata((core_id+1)*32-1 downto core_id*32);
          I := I+1;
        else
          s_axi_rready(core_id) <= '0';
          wait until rising_edge(clk);
        end if;
      end loop;
      wait until rising_edge(clk);

    end procedure axi_bread;


    type imem_slv_array is array (natural range <>) of
      std_logic_vector (IMEMDATAWIDTH-1 downto 0);
    variable imem_r : imem_slv_array (0 to 2**IMEMADDRWIDTH-1);
    variable imem_word : std_logic_vector(IMEMDATAWIDTH-1 downto 0);

    constant imem_word_nextPO2 : integer := 2**bit_width(IMEMDATAWIDTH-1);
    constant imem_word_padding : std_logic_vector(imem_word_nextPO2-IMEMDATAWIDTH-1 downto 0)
                               := (others => '0');
    variable imem_word_padded : std_logic_vector(imem_word_nextPO2-1 downto 0);
    constant imem_data_count : integer := imem_word_nextPO2/16;
    variable imem_data : imem_arr(0 to imem_data_count - 1);
    
    variable dmem_word : std_logic_vector(32-1 downto 0);
    variable dmem_size : integer;
    variable cqmem_size : integer;
    variable dmem_start : integer;
    variable cqmem_start : integer;
    variable imem_start : integer;
    variable imem_size : integer;
    variable i : integer;
    variable k : integer;
    variable good : boolean;
    file mem_init              : text;
    file dmem_init : text;
    variable line_in           : line;
    variable value : std_logic_vector(31 downto 0);

    variable line_out : line;
    file logfile      : text;
    file dmem_dump_file      : text;
    file resultfile : text;

    variable seed1    : integer := 733035985;
    variable seed2    : integer := 787335972;
    variable rand     : real;
    variable val_in   : std_logic_vector(31 downto 0);

    variable completion_req_counter : integer := 0;
    variable completion_address : std_logic_vector(MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 0) 
                                    := ((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 7 => '0') & "1001000");
                                    --((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 14 => '0') & (13 downto 2 => '1') & "00");
                                    --((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 1 => '0') & '1');

    variable decrement : std_logic := '1';
    variable zero : std_logic := '0';


    -- rxsnp test
    variable cycle_count : integer := 0;

------------------------------------------------------------
------------------------------------------------------------
-- SIMULATION ----------------------------------------------
  begin
      file_open(logfile, log_path, write_mode);

      nreset <= '0';

      s_axi_awid <= (others => '0');

      s_axi_arid <= (others => '0');
      s_axi_arlen <= (others => '0');

      s_axi_awaddr <= (others => '0');
      s_axi_araddr <= (others => '0');
      s_axi_wdata  <= (others => '0');
      s_axi_wlast <= (others => '0');

      s_axi_wvalid <= (others => '0');
      s_axi_arvalid <= (others => '0');
      s_axi_awvalid <= (others => '0');
      s_axi_wstrb <= (others=>'1');
      s_axi_rready <= (others => '0');

      for core_id in 0 to rnf_count-1 loop
        s_axi_awsize((core_id+1)*3-1 downto core_id*3) <= "010";
        s_axi_arsize((core_id+1)*3-1 downto core_id*3) <= "010";
        s_axi_awburst((core_id+1)*2-1 downto core_id*2) <= "01";
        s_axi_arburst((core_id+1)*2-1 downto core_id*2) <= "01";
        s_axi_bready <= (others => '1');
      end loop;

      for id in 0 to rnf_count-1 loop
        txreq_crdt_counter(id) <= (others => '0');
        txdat_crdt_counter(id) <= (others => '0');
        txrsp_crdt_counter(id) <= (others => '0');
        txreq_crdt_counter_tmp(id) := (others => '0');
        txdat_crdt_counter_tmp(id) := (others => '0');
        txrsp_crdt_counter_tmp(id) := (others => '0');
      end loop;

      update_llc := (others => '0');
      snp_done <= '0';
      send_snoop <= '0';
      invalid_snp_rsp := (others => '0');
      send_data <= '0';
      send_response <= '0';
      waiting_ack <= '0';
      response_sent <= '0';
      snoop_sent <= '0';
      compack_received <= '0';
      copybackdata_received <= '0';
      data_flit_num <= std_logic_vector(to_unsigned(0, 32));
      txreq_valid <= '0';


      wait until rising_edge(clk);
      wait until rising_edge(clk);

      nreset <= '1';

      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait until rising_edge(clk);

      for core_id in 0 to rnf_count-1 loop
        -- For some reason the TCEMC flips info register placements of CQMEM and DMEM
        -- Addresses had to be flipped to get the tb working. 
        --axi_read(TTA_DMEM_SIZE_LOW*4, dmem_word);
        axi_read(TTA_CQMEM_SIZE_LOW*4, dmem_word, core_id);
        dmem_size := to_integer(unsigned(dmem_word));
        write(line_out, "DMEM size: " & integer'image(dmem_size));
        writeline(logfile, line_out);

        --axi_read(TTA_CQMEM_SIZE_LOW*4, dmem_word);
        axi_read(TTA_DMEM_SIZE_LOW*4, dmem_word, core_id);
        cqmem_size := to_integer(unsigned(dmem_word));
        write(line_out, "CQMEM size: " & integer'image(cqmem_size));
        writeline(logfile, line_out);


        axi_read(TTA_IMEM_START_LOW*4, dmem_word, core_id);
        imem_start := to_integer(unsigned(dmem_word));
        write(line_out, "IMEM start: " & integer'image(imem_start));
        writeline(logfile, line_out);

        --axi_read(TTA_DMEM_START_LOW*4, dmem_word);
        axi_read(TTA_CQMEM_START_LOW*4, dmem_word, core_id);
        dmem_start := to_integer(unsigned(dmem_word));
        write(line_out, "DMEM start: " & integer'image(dmem_start));
        writeline(logfile, line_out);

        --axi_read(TTA_CQMEM_START_LOW*4, dmem_word);
        axi_read(TTA_DMEM_START_LOW*4, dmem_word, core_id);
        cqmem_start := to_integer(unsigned(dmem_word));
        write(line_out, "CQMEM start: " & integer'image(cqmem_start));
        writeline(logfile, line_out);
      end loop;
      
  -- IMEM INIT
      for core_id in 0 to rnf_count-1 loop
        i := 0;

        if (core_id = 0) then
          file_open(mem_init, imem_image, read_mode);
        elsif (core_id = 1) then
          file_open(mem_init, imem_image_2, read_mode);
        end if;

        while (not endfile(mem_init) and i < imem_r'length) loop
            readline(mem_init, line_in);
            read(line_in, imem_word, good);
            assert good
            report "Read error in instruction memory initialization file"
            severity failure;

          -- This supports instruction widths between 32 and 64, restrict with BEM
            imem_word_padded := imem_word_padding & imem_word;

            for k in integer range 0 to imem_data_count-1 loop
                imem_data(k) := imem_word_padded(16*(k+1) - 1 downto 16*k);
            end loop;

            axi_bwrite_16(i*imem_data_count*2   + imem_start, imem_data_count, imem_data, core_id);

            i        := i+1;
        end loop;
        file_close(mem_init);

        write(line_out, string'("IMEM Initialization complete"));
        writeline(logfile, line_out);
      end loop;

  -- Zero-initialize data memory                 -- Memory through AXI is not used atm. That's why also init also shortened with "/10"
      for core_id in 0 to rnf_count-1 loop
        for i in integer range 0 to (dmem_size/4-1)/10 loop
            axi_write(dmem_start+i*4, (others=>'0'), core_id);
        end loop;
      end loop;
      
      --- Initialize data memory with actual data
      --- For some reason, read(...) throws error...
      --- ATM, datamem init is not working
      -- i := 0;
      -- file_open(dmem_init, dmem_image, read_mode);
      -- while (not endfile(dmem_init) and i < dmem_size/4) loop
      --     readline(dmem_init, line_in);
      --     read(line_in, dmem_word, good);
      --     assert good
      --     report "Read error in data memory initialization file"
      --     severity failure;
      --     axi_write(i*4   + dmem_start, dmem_word);    -- core_id not given yet
      --     i        := i+1;
      -- end loop;
      -- file_close(dmem_init);

      -- write(line_out, string'("DMEM Initialization complete"));
      write(line_out, string'("NO DMEM Initialization "));
      writeline(logfile, line_out);


  -- Zero-initialize command queue memory
      for core_id in 0 to rnf_count-1 loop
        for i in integer range 0 to cqmem_size/4-1 loop
            axi_write(cqmem_start+i*4, (others=>'0'), core_id);
        end loop;
      end loop;

      write(line_out, string'("CQMEM Initialization complete"));
      writeline(logfile, line_out);

  -- Initialize the LLC
      for i in LLCache'range loop
        LLCache(i) <= (others => '0');
        cacheline_state(i) <= (others => '0');  -- invalid
        directory(i) <= (others => '0');  -- no sharers/owners
      end loop;

      tmp_LLCache := (others => (others => '0'));
      tmp_cacheline_state := (others => (others => '0'));
      tmp_directory := (others => (others => '0'));

      update_addr <= (others => '0');
      update_txnid <= (others => '0');

  -- Send TX-L-credits
      for i in 0 to 1 loop  -- loop 2 times so txreq/dat gets all the L-credits
        for core_id in 0 to rnf_count-1 loop
          if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= 2) then
            txreqlcrdv(core_id) <= '1';
            txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
          else
            txreqlcrdv(core_id) <= '0';
          end if;
          if (to_integer(signed(txdat_crdt_counter_tmp(core_id))) /= 2) then
            txdatlcrdv(core_id) <= '1';
            txdat_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txdat_crdt_counter_tmp(core_id))) + 1, 32));
          else
            txdatlcrdv(core_id) <= '0';
          end if;
          if (to_integer(signed(txrsp_crdt_counter_tmp(core_id))) = 0 and txrspflitv(core_id) = '0') then
            txrsplcrdv(core_id) <= '1';
            txrsp_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txrsp_crdt_counter_tmp(core_id))) + 1, 32));
          else
            txrsplcrdv(core_id) <= '0';
          end if;
        end loop;
        wait_cycle_update_counters(zero, zero, zero);
      end loop;

      txreq_crdt_counter <= txreq_crdt_counter_tmp;
      txdat_crdt_counter <= txdat_crdt_counter_tmp;
      txrsp_crdt_counter <= txrsp_crdt_counter_tmp;

      for core_id in 0 to rnf_count-1 loop
          txreqlcrdv(core_id) <= '0';
          txdatlcrdv(core_id) <= '0';
          txrsplcrdv(core_id) <= '0';
      end loop;

      wait_cycle_update_counters(zero, zero, zero);
  
  -- Start program completetion
      for core_id in 0 to rnf_count-1 loop
        -- Start the program
        axi_write(dmem_start+completion_signal_address_g, X"00000000", core_id);
        -- Lift softreset
        dbg_command(DEBUG_CMD_CONTINUE, core_id);
      end loop;

      value := (others=>'0');

      -- Give one credit to CHI TXREQ channel
      -- txreqlcrdv <= '1';
      -- wait until rising_edge(clk);
      -- txreqlcrdv <= '0';

  -- Reset RX signals
      rxrspflit <= (others=>'0');
      rxrspflitpend <= (others=>'0');
      rxrspflitv <= (others=>'0');
      rxdatflit <= (others=>'0');
      rxdatflitpend <= (others=>'0');
      rxdatflitv <= (others=>'0');
      rxsnpflit <= (others=>'0');
      rxsnpflitpend <= (others=>'0');
      rxsnpflitv <= (others=>'0');

------------------------------------------------------------
------------------------------------------------------------
-- MAIN LOOP -----------------------------------------------
      while value = X"00000000" loop

          -- Poll program completion        16.7. TEMPORARILY NO COMPLETION READ TO ENSURE CORRECT NOC RECEIVING
          --axi_read(dmem_start+completion_signal_address_g, value);

        -- TB/HNF logic

  -- TRANSACTION CONTROL
        if (txreq_valid = '1') then
          transaction_control(value);
        else 
          next_transaction(value);
        end if;

  -- CHECK INCOMING PACKETS
  reorder_done <= '0';
        if txreqflitv /= (txreqflitv'range => '0') then
          chi_txreq_receive(value);
          check_next_mshr_enrty(value); --CHECK IF WORKS
        end if;  

        txreq_crdt_counter <= txreq_crdt_counter_tmp;

        if txdatflitv /= (txdatflitv'range => '0') then
          chi_txdat_receive(value);
        end if;

        if txrspflitv /= (txrspflitv'range => '0') then
          chi_txrsp_receive(value);
        end if;

  -- UPDATE LLC SIGNALS
        cacheline_state <= tmp_cacheline_state;
        directory <= tmp_directory;
        LLCache <= tmp_LLCache;
        
  -- WAIT CYCLE
        wait_cycle_update_counters(zero, zero, zero); 

  -- LOWER THE TXDATLCRDV
        for id in 0 to rnf_count-1 loop
          txreqlcrdv(id)    <= '0';
          txdatlcrdv(id)    <= '0';
          txrsplcrdv(id)    <= '0';
          rxrspflitv(id)    <= '0';
          rxrspflitpend(id) <= '0';
          rxdatflitv(id)    <= '0';
          rxdatflitpend(id) <= '0';
          rxsnpflitv(id)    <= '0';
          rxsnpflitpend(id) <= '0';
        end loop;

        txreq_procedure <= '0';
        rxdat_procedure <= '0';
        txrsp_procedure <= '0';
        rxsnp_procedure <= '0';
        count_procedure <= '0';
        rxrsp_procedure <= '0';

  -- Update LLC if txdat had been received last cycle
                      -- SHOULD THIS ONLY ALLOW ONE CORE TO UPDATE LLC PER CYCLE  (THERE MIGHT BE RECEIVED TWO DATA PACKETS IN A ROW, SO THERE MIGHT BE MISSED THE FIRST PACKET)
        if update_llc /= (update_llc'range => '0') then
          update_LLC_txdat(value);
        end if;

        -- Should implement some way to get program completion and break this loop
        -- Atm it can be just seen from the lsu writing 0
      end loop;

  -- PROGRAM COMPLETED

      write(line_out, string'("Core done"));
      writeline(logfile, line_out);


      -- file_open(dmem_dump_file, dmem_dump_path, write_mode);
      -- for i in 0 to dmem_size/4-1 loop
      --     axi_read(dmem_start+i*4, dmem_word);
      --     write(line_out, integer'image(to_integer(unsigned(dmem_word))));
      --     writeline(dmem_dump_file, line_out);
      -- end loop;
      -- file_close(dmem_dump_file);
      for core_id in 0 to rnf_count-1 loop
        file_open(resultfile, resfile_path, write_mode);
        for i in 3 to 32 loop -- 0xABAD1D3A and the first 64 values of the fibonacci series
            axi_read(dmem_start+i*4, dmem_word, core_id);
            --value := endian_swap(value);
            write(line_out, "Data at address " & integer'image(i) & ": " & integer'image(to_integer(signed(dmem_word))));
            writeline(resultfile, line_out);
        end loop;
      end loop;


      write(line_out, string'("Output written"));
      writeline(logfile, line_out);
      file_close(logfile);
      file_close(resultfile);


      clk_ena  <= '0';
      wait;
  end process;

end testbench;


