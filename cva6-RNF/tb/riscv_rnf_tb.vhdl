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
-- Title      : AMBA CHI Fully Coherent Request Node Testbench
-- Project    : 
-------------------------------------------------------------------------------
-- File       : riscv_rnf_tb.vhdl
-- Author     : Teemu Rinne
-- Company    : TUNI
-- Created    : 2016-07-26
-- Last update: 2026-01-27
-- Platform   : 
-------------------------------------------------------------------------------
-- Description: Cache coherency controlling testbench
--              Runs precompiled programs for RISC-V CVA6.
--              Handles every received transaction requests one by one sequentially.
--              
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 
-------------------------------------------------------------------------------

library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use std.textio.all;
use IEEE.std_logic_textio.all;
use work.cache_subsystem_pkg.all;
use work.wt_cache_pkg.all;
use work.riscv.all;

entity riscv_rnf_tb is
  generic (
    imem_image                  : string := "prog.img";
    imem_image_2                : string := "prog2.img";
    dmem_image                  : string := "prog_data.img";
    log_path                    : string := "verification/run.log";
    dmem_dump_path              : string := "verification/dmem.log";
    resfile_path                : string := "verification/result_file.log";
    unitresult_path             : string := "verification/unittest_result.log";
    io_path                     : string := "verification/io_output.log";
    clk_period                  : time := 1 ns; --10 ns;
    completion_signal_address_g : integer := 4);
end riscv_rnf_tb;

architecture testbench of riscv_rnf_tb is
  function mmax (a,b : integer) return integer is
  begin
    if (a > b) then return a; else return b; end if;
  end mmax;

  constant rnf_count : integer := 1;
  constant llc_memsize : integer := 8192; -- 512KB(524288B) cache, 8192x512bit = 262144byte. Basically the Cached Region Length set to cva6

  -- OpenPiton L1 has 8 entry write buffer, and RNF's rx_control can trigger WriteCleanFull with extra MSHR-ID -> 10 mshr slots /RNF 
  constant TB_MSHR_WIDTH : integer := (8+2)*rnf_count; 
  constant TB_BYPASS_MSHR_WIDTH : integer := 4*rnf_count;

  constant RNF_MSHR_ENTRY_SLOTS : integer := TB_MSHR_WIDTH/rnf_count;

  -- Memory space base addresses according to generated OpenPiton-CVA6
  constant mem_base : std_logic_vector(63 downto 0) := X"00000000_80000000";
  constant bootrom_base : std_logic_vector(63 downto 0) := X"000000_FFF1010000";
  constant debug_base : std_logic_vector(63 downto 0) := X"000000_FFF1000000";
  -- Be sure to check that the RNFs atomically add 1 to the same "finished_addr" as in the TB, if the simulation is wanted to be stop from the TB
  constant finished_rnf_cnt_addr : std_logic_vector(63 downto 0) := X"000000000007D000"; -- 8000th cacheline, used to signal that main program exec has finished
  constant start_rnf_cnt_addr : std_logic_vector(63 downto 0) := X"000000000007D004"; -- 8001th cacheline, used to signal that program exec has begun
  constant result_cacheline_addr : std_logic_vector(63 downto 0) := X"000000000007E900"; -- 8100th cacheline
  constant result_cacheline_addr_2 : std_logic_vector(63 downto 0) := X"000000000007E940"; -- 8101th cacheline
  constant riscv_imemwidth : integer := 32;
  -- According to mem_base
  constant mem_address_space_w : integer := integer(ceil(log2(real(524288)))); -- Gives address width for byte addresses in 512KB memory space
  constant io_address_space_w : integer := integer(ceil(log2(real(1024)))); -- 

  -- Required CHI DAT-packets per message
  constant dat_flits_to_send : integer := 512/CHIE_DATA_WIDTH_PARAM;
  constant max_dat_flits : integer := 4; -- 512/128

  signal clk       : std_logic := '0';
  signal clk_ena   : std_logic := '1';
  signal nreset    : std_logic;

  type data_arr is array (natural range <>) of std_logic_vector(31 downto 0);
  signal in_data   : data_arr(0 to 65535);


  type imem_arr is array (natural range <>) of std_logic_vector(15 downto 0);

  signal   val_out : std_logic_vector(31 downto 0);
  signal   vals_in  : data_arr(0 to 63);
  signal   vals_out : data_arr(0 to 63);

  signal bootrom_req : std_logic;
  signal bootrom_addr : std_logic_vector(63 downto 0);
  signal bootrom_rdata : std_logic_vector(63 downto 0);
  signal bootrom_read_done :std_logic;
  
------------------------------CHI signals------------------------------
  type lcrdv_arr  is array (natural range <>) of std_logic;
  type flitv      is array (natural range <>) of std_logic;
  type flitpend   is array (natural range <>) of std_logic;
  type rsp_flit   is array (natural range <>) of std_logic_vector(CHIE_RSP_FLIT_WIDTH-1 downto 0);
  type dat_flit   is array (natural range <>) of std_logic_vector(CHIE_DAT_FLIT_WIDTH-1 downto 0);
  type req_flit   is array (natural range <>) of std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
  type snp_flit   is array (natural range <>) of std_logic_vector(CHIE_SNP_FLIT_WIDTH-1 downto 0);

  -- RN-F interface signals
  -- RX response channel
  signal rxrspflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxrspflit      : std_logic_vector(rnf_count*CHIE_RSP_FLIT_WIDTH-1 downto 0);
  signal rxrspflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- RX data channel
  signal rxdatflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxdatflit      : std_logic_vector(rnf_count*CHIE_DAT_FLIT_WIDTH-1 downto 0);
  signal rxdatflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- RX snoop channel         
  signal rxsnpflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxsnpflit      : std_logic_vector(rnf_count*CHIE_SNP_FLIT_WIDTH-1 downto 0);
  signal rxsnpflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- Credits from TX channels
  signal txreqlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal txrsplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal txdatlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  -- Credits to RX channels
  signal rxrsplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxdatlcrdv     : std_logic_vector(rnf_count-1 downto 0);
  signal rxsnplcrdv     : std_logic_vector(rnf_count-1 downto 0);
  -- TX request channel
  signal txreqflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txreqflit      : std_logic_vector(rnf_count*CHIE_REQ_FLIT_WIDTH-1 downto 0);
  signal txreqflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- TX response channel
  signal txrspflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txrspflit      : std_logic_vector(rnf_count*CHIE_RSP_FLIT_WIDTH-1 downto 0);
  signal txrspflitpend  : std_logic_vector(rnf_count-1 downto 0);
  -- TX data channel
  signal txdatflitv     : std_logic_vector(rnf_count-1 downto 0);
  signal txdatflit      : std_logic_vector(rnf_count*CHIE_DAT_FLIT_WIDTH-1 downto 0);
  signal txdatflitpend  : std_logic_vector(rnf_count-1 downto 0);

  signal txlinkactivereq : std_logic_vector(rnf_count-1 downto 0);
  signal txlinkactiveack : std_logic_vector(rnf_count-1 downto 0);
  signal rxlinkactivereq : std_logic_vector(rnf_count-1 downto 0);
  signal rxlinkactiveack : std_logic_vector(rnf_count-1 downto 0);
  signal txactive : std_logic_vector(rnf_count-1 downto 0);
  signal rxactive : std_logic_vector(rnf_count-1 downto 0);

  -- Procedure signals
      -- In simulation, shows which procedure is done
  signal txreq_procedure     : std_logic;
  signal rxdat_procedure     : std_logic;
  signal txrsp_procedure     : std_logic;
  signal rxsnp_procedure     : std_logic;
  signal count_procedure     : std_logic;
  signal rxrsp_procedure     : std_logic;
  -- Link-credit and Data-response acknowledgement counters
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
  signal LLCache : cache_arr(0 to llc_memsize-1);

  -- Cache coherence state monitor
  -- 3=M, 2=E, 1=S, 0=I     (1=Valid if not in any RNF)
  type state_arr is array (natural range <>) of std_logic_vector(1 downto 0);
  signal cacheline_state : state_arr(0 to llc_memsize-1);

  -- Cacheline owners, "Directory"
  -- '1'=has the cacheline, '0'=doesn't have the cacheline
  type dir_arr is array (natural range <>) of std_logic_vector(rnf_count-1 downto 0);
  signal directory : dir_arr(0 to llc_memsize-1);

  -- IO storage
  type io_arr is array (natural range <>) of std_logic_vector(511 downto 0);
  signal io_space : io_arr(0 to 127);

  -- Snoop request addresses and transaction-id
  signal snoop_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 
  signal snoop_txnid      : std_logic_vector(CHIE_REQ_FLIT_TXNID_WIDTH-1 downto 0); 
  
  -- Address used when RN-F sends data or snoop response
  signal update_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 


  type mshr_valid         is array (natural range <>) of std_logic;
  type mshr_entry           is array (natural range <>) of std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
  type id_array is array (natural range <>) of integer;

  -- Transaction control signals
      -- State signals of the testbench, helps in simulations to see what the TB is doing
  signal snp_done : std_logic;
  signal send_data : std_logic;
  signal send_uncached_data : std_logic;
  signal send_response : std_logic;
  signal waiting_ack : std_logic;
  signal compack_received : std_logic;
  signal response_sent : std_logic;
  signal copybackdata_received : std_logic;
  signal send_snoop : std_logic;
  signal snoop_sent : std_logic;
  signal amo_data_ready : std_logic;
  signal do_amo : std_logic;
  signal amo_done : std_logic;
  signal snoop_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0);
  signal snoopees : std_logic_vector(rnf_count-1 downto 0);
  signal sent_snoop_count : std_logic_vector(31 downto 0);
  signal reorder_done : std_logic;
  signal handle_writereq : std_logic;
  signal switch_to_next_req : std_logic;
  signal switch_back : std_logic;
  signal intermediate_resp : std_logic;
  signal io_data_ready : std_logic;
  signal write_io_data : std_logic;
  signal io_done : std_logic;

  -- Request being handled by the TB
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
  -- Stalled and temporarily stored request
  signal stalled_req_valid        : std_logic;
  signal stalled_req_qos          : std_logic_vector(CHIE_REQ_FLIT_QOS_WIDTH-1 downto 0);
  signal stalled_req_tgtid        : std_logic_vector(CHIE_REQ_FLIT_TGTID_WIDTH-1 downto 0); 
  signal stalled_req_srcid        : std_logic_vector(CHIE_REQ_FLIT_SRCID_WIDTH-1 downto 0); 
  signal stalled_req_txnid        : std_logic_vector(CHIE_REQ_FLIT_TXNID_WIDTH-1 downto 0); 
  signal stalled_req_returnnid    : std_logic_vector(CHIE_REQ_FLIT_RETURNNID_WIDTH-1 downto 0);
  signal stalled_req_endian       : std_logic_vector(CHIE_REQ_FLIT_ENDIAN_WIDTH-1 downto 0);
  signal stalled_req_returntxnid  : std_logic_vector(CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1 downto 0);
  signal stalled_req_opcode       : std_logic_vector(CHIE_REQ_FLIT_OPCODE_WIDTH-1 downto 0);   
  signal stalled_req_size         : std_logic_vector(CHIE_REQ_FLIT_SIZE_WIDTH-1 downto 0);    
  signal stalled_req_addr         : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0); 
  signal stalled_req_ns           : std_logic_vector(CHIE_REQ_FLIT_NS_WIDTH-1 downto 0);      
  signal stalled_req_likelyshared : std_logic_vector(CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1 downto 0);
  signal stalled_req_allowretry   : std_logic_vector(CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1 downto 0);    
  signal stalled_req_order        : std_logic_vector(CHIE_REQ_FLIT_ORDER_WIDTH-1 downto 0);
  signal stalled_req_pcrdtype     : std_logic_vector(CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1 downto 0);
  signal stalled_req_memattr      : std_logic_vector(CHIE_REQ_FLIT_MEMATTR_WIDTH-1 downto 0);
  signal stalled_req_snpattr      : std_logic_vector(CHIE_REQ_FLIT_DODWT_WIDTH-1 downto 0); 
  signal stalled_req_lpid         : std_logic_vector(CHIE_REQ_FLIT_LPID_WIDTH-1 downto 0);
  signal stalled_req_excl_snoopme : std_logic_vector(CHIE_REQ_FLIT_EXCL_WIDTH-1 downto 0);
  signal stalled_req_expcompack   : std_logic_vector(CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1 downto 0);
  signal stalled_req_tagop        : std_logic_vector(CHIE_REQ_FLIT_TAGOP_WIDTH-1 downto 0);
  signal stalled_req_tracetag     : std_logic_vector(CHIE_REQ_FLIT_TRACETAG_WIDTH-1 downto 0);
  signal stalled_rxdat_flitnum    : std_logic_vector(31 downto 0);

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

  -- Received response packet fields from RN-Fs
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

  -- Received data packet fields from RN-Fs
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
      clk <= not clk after clk_period/2;
    end if;
  end process clk_gen;


  -- DUT (TB to RN-Fs)
  dut_rnf : entity work.rnf_wrapper
    generic map (
      CHIE_REQ_ADDR_WIDTH_PARAM     => CHIE_REQ_ADDR_WIDTH_PARAM,
      CHIE_SNP_ADDR_WIDTH_PARAM     => CHIE_SNP_ADDR_WIDTH_PARAM,
      CHIE_NID_WIDTH_PARAM          => CHIE_NID_WIDTH_PARAM,                   
      CHIE_DATA_WIDTH_PARAM         => CHIE_DATA_WIDTH_PARAM,
      CHIE_BE_WIDTH_PARAM           => CHIE_BE_WIDTH_PARAM,
      CHIE_DATACHECK_WIDTH_PARAM    => CHIE_DATACHECK_WIDTH_PARAM,
      CHIE_POISON_WIDTH_PARAM       => CHIE_POISON_WIDTH_PARAM,
      CHIE_REQ_RSVDC_WIDTH_PARAM    => CHIE_REQ_RSVDC_WIDTH_PARAM,
      CHIE_DAT_RSVDC_WIDTH_PARAM    => CHIE_DAT_RSVDC_WIDTH_PARAM,
      HNF_NID_PARAM                 => HNF_NID_PARAM,
      XP_LCRD_NUM_PARAM             => XP_LCRD_NUM_PARAM,
      CACHED_REGION_BASE            => mem_base,
      CACHED_REGION_SIZE            => CACHED_REGION_SIZE,
      BOOT_REGION_BASE              => bootrom_base,
      BOOT_REGION_SIZE              => BOOT_REGION_SIZE,
      IO_REGION_BASE                => IO_REGION_BASE,
      IO_REGION_SIZE                => IO_REGION_SIZE,
      corecount_g                   => rnf_count
    )
    port map (
      clk           => clk,
      rst_n         => nreset,
      clk_en        => clk_ena,

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
      txdatflitpend => txdatflitpend,
      txlinkactivereq => txlinkactivereq,
      txlinkactiveack => txlinkactiveack,
      rxlinkactivereq => rxlinkactivereq,
      rxlinkactiveack => rxlinkactiveack,
      txactive => txactive,
      rxactive => rxactive

      );

  -- Bootrom for CVA6 RN-F
  bootrom : entity work.bootrom
    port map (
      clk_i           => clk,
      req_i           => bootrom_req,
      addr_i          => bootrom_addr,
      rdata_o         => bootrom_rdata
    );

  
  run_test : process

  variable line_out : line;
  file logfile      : text;
  variable line_in           : line;

  variable unit_line_out : line;
  file unit_file      : text;
  variable unit_line_in           : line;

  variable io_line_out : line;
  file io_file : text;
  variable io_line_in : line;

  variable running : std_logic := '0';
  variable prog_end : std_logic := '0';

  -- Testing signals, modified by compile_prog.sh script whenever unit test is compiled
  -- Manual change might cause undefined behaviour
  ------------------------------------------------------------
  variable unit_test : std_logic := '0';
  variable corner_test : std_logic := '0';
  variable do_readunique_test : std_logic := '0';
  variable do_readshared_test : std_logic := '0';
  variable do_writebackptl_test : std_logic := '0';
  variable do_unique_snoop : std_logic := '0';
  variable do_shared_snoop : std_logic := '0';
  variable do_clean_snoop : std_logic := '0';
  variable do_makeinvalid_snoop : std_logic := '0';
  variable do_rettosrc_snoop : std_logic := '0';
  variable do_cleaninvalid_snoop : std_logic := '0';
  variable do_amoadd_swap_test : std_logic := '0';
  variable do_atomicload_test : std_logic := '0';
  variable do_mixeddata_test : std_logic := '0';
  variable do_reverseresponse_test : std_logic := '0';
  variable do_coherencystress_test : std_logic := '0';
  variable do_writenosnp_test : std_logic := '0';
  variable do_separate_resp : std_logic := '0';
  variable expect_empty_snpresp : std_logic := '0';
  variable send_unique_dirty_cline : std_logic := '0';
  variable do_snoop_test : std_logic := '0';
  variable readunique_triggered : std_logic := '0';
  variable readunique_done : std_logic := '0';
  variable readshared_triggered : std_logic := '0';
  variable readshared_done : std_logic := '0';
  variable writebackptl_triggered : std_logic := '0';
  variable writebackptl_done : std_logic := '0';
  variable writenosnp_triggered : std_logic := '0';
  variable writenosnp_done : std_logic := '0';
  variable correct_response :std_logic := '0';
  variable dirty_resp_triggered : std_logic := '0';
  variable wrcleanfull_done : std_logic := '0';
  variable dirtycleandata_test_done : std_logic := '0';
  variable mixed_data_resp_done : std_logic := '0';
  variable mixed_resp_triggered : std_logic := '0';
  variable reverse_resp_triggered : std_logic := '0';
  ------------------------------------------------------------

  -- Runtime control variables
  variable rxdat_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable rxsnp_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable rxrsp_crdt_count_tmp    : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txrsp_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txreq_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable txdat_crdt_counter_tmp  : counter_array(rnf_count-1 downto 0) := (others=>(others=>'0'));
  variable tmp_LLCache : cache_arr(0 to llc_memsize-1) := (others=>(others=>'0'));
  variable tmp_cacheline_state : state_arr(0 to llc_memsize-1) := (others=>(others=>'0'));
  variable tmp_directory : dir_arr(0 to llc_memsize-1) := (others=>(others=>'0'));
  variable amo_data : std_logic_vector(511 downto 0) := (others=>'0');
  variable amo_data_be : std_logic_vector(63 downto 0) := (others=>'0');
  variable io_data : std_logic_vector(511 downto 0) := (others=>'0');
  variable io_data_be : std_logic_vector(63 downto 0) := (others=>'0');
  variable mshr_read_idx : integer := 0;
  variable mshr_store_idx : integer := 0;
  variable mshr_vld         : mshr_valid(0 to TB_MSHR_WIDTH-1) := (others=>'0');
  variable mshr               : mshr_entry(0 to TB_MSHR_WIDTH-1) := (others=>(others=>'0'));
  variable bypass_mshr_read_idx : integer := 0;
  variable bypass_mshr_store_idx : integer := 0;
  variable bypass_mshr_valid         : mshr_valid(0 to TB_BYPASS_MSHR_WIDTH-1) := (others=>'0');
  variable bypass_mshr               : mshr_entry(0 to TB_BYPASS_MSHR_WIDTH-1) := (others=>(others=>'0'));
  variable update_llc : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable update_io : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable invalid_snp_rsp : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable amo_data_received : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable sent_snoop_count_var : integer := 0;
  variable decrement_rxdatcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable decrement_rxsnpcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable decrement_rxrspcrdt : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
  variable writenosnp_cnt : integer := 0;
  variable data_flit_num : std_logic_vector(31 downto 0) := (others => '0');


    -- Update CHI count of RX credits received from RN-Fs, 
    -- If flit was sent, decrement the count
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
    -- TXRSP channel
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

            if (do_snoop_test = '1' and expect_empty_snpresp = '1') then
              correct_response := '1';
            end if;
            
          end if;

          txrsp_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txrsp_crdt_counter_tmp(core_id))) - 1, 32));

          if (running = '1') then
            write(line_out, string'("Received response"));
            writeline(logfile, line_out);
            write(line_out, string'("Opcode: "));
            write(line_out, to_integer(unsigned(txrsp_opcode_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("Source ID: "));
            write(line_out, to_integer(unsigned(txrsp_srcid_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("Transaction ID: "));
            write(line_out, to_integer(unsigned(txrsp_txnid_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("Resp code: "));
            write(line_out, to_integer(unsigned(txrsp_resp_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("Forward state: "));
            write(line_out, to_integer(unsigned(txrsp_fwdstate_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("DBID: "));
            write(line_out, to_integer(unsigned(txrsp_dbid_tmp(core_id))));
            writeline(logfile, line_out);
            write(line_out, string'("####################"));
            writeline(logfile, line_out);
          end if;

        else 
          -- 
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

      -- Return L-credit
      for id in 0 to rnf_count-1 loop
        if (to_integer(signed(txrsp_crdt_counter_tmp(id))) = 0) then
          txrsplcrdv(id) <= '1';
          txrsp_crdt_counter_tmp(id) := std_logic_vector(to_unsigned(to_integer(signed(txrsp_crdt_counter_tmp(id))) + 1, 32));
        end if;
      end loop;

      txrsp_crdt_counter <= txrsp_crdt_counter_tmp;

    end procedure chi_txrsp_receive;


    -- Update the LLC with the responses coming from DAT- and RSP-channels
    procedure update_LLC_txdat( variable value : out std_logic_vector(31 downto 0) ) is
      variable cacheline_addr : integer := 0;
      variable req_opcode : integer := 0;
      variable dataid : integer := 0;
    begin
      value := (others => '0');
      req_opcode := to_integer(signed(txreq_opcode));

      cacheline_addr := to_integer(unsigned(update_addr(mem_address_space_w-1 downto 6)));

      for core_id in 0 to rnf_count-1 loop
        if (update_llc(core_id) = '1') then

          -- Cacheline has been invalidated from local cache
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

            dataid := to_integer(unsigned(txdat_dataid(core_id)));

            if (amo_data_received(core_id) = '1') then  -- AMO DATA
              amo_data(128*dataid+CHIE_DAT_FLIT_DATA_WIDTH-1 downto 128*dataid) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-1 downto 0);
              amo_data_be(16*dataid+CHIE_DAT_FLIT_BE_WIDTH-1 downto 16*dataid) := txdat_be(core_id);

            elsif (update_io(core_id) = '1') then  -- IO DATA
              io_data(128*dataid+CHIE_DAT_FLIT_DATA_WIDTH-1 downto 128*dataid) := txdat_data(core_id)(CHIE_DAT_FLIT_DATA_WIDTH-1 downto 0);
              io_data_be(16*dataid+CHIE_DAT_FLIT_BE_WIDTH-1 downto 16*dataid) := txdat_be(core_id);

            else  -- Cacheable data
              for be in 0 to CHIE_DAT_FLIT_BE_WIDTH-1 loop
                if (txdat_be(core_id)(be) = '1') then
                  tmp_LLCache(cacheline_addr)(be*8+8+128*dataid-1 downto be*8+128*dataid) := txdat_data(core_id)(be*8+8-1 downto be*8);
                end if;
              end loop;

            end if;

            -- Directory and cacheline state updates +next transaction steps
            if (dataid = dat_flits_to_send-1 or (CHIE_DATA_WIDTH_PARAM = 256 and dataid = dat_flits_to_send)) then
              if (txdat_opcode(core_id) = std_logic_vector(to_unsigned(1, CHIE_DAT_FLIT_OPCODE_WIDTH)) or 
                  txdat_opcode(core_id) = std_logic_vector(to_unsigned(5, CHIE_DAT_FLIT_OPCODE_WIDTH))) then -- 1 or 5 CHIE_SNPRESPDATA
                if (txdat_resp(core_id) = std_logic_vector(to_unsigned(4, CHIE_DAT_FLIT_RESP_WIDTH)) 
                    or txdat_resp(core_id) = std_logic_vector(to_unsigned(0, CHIE_DAT_FLIT_RESP_WIDTH))) then -- _I_PD/_I, line was invalidated from RNF
                  tmp_directory(cacheline_addr)(core_id) := '0';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
                elsif (txdat_resp(core_id) = std_logic_vector(to_unsigned(5, CHIE_DAT_FLIT_RESP_WIDTH)) 
                      or txdat_resp(core_id) = std_logic_vector(to_unsigned(1, CHIE_DAT_FLIT_RESP_WIDTH))) then -- SC_PD/SC, line was left to Shared state in RNF
                  -- TAKE INTO ACCOUNT THAT THIS SOULDN'T BE POSSIBLE WITH RETURNED -PARTIAL- DATA RESPONSE ACCORDING TO CHI SPEC!! THE LINE SHOULD BE INVALIDATED FROM THE RNF IN THAT CASE     
                  tmp_directory(cacheline_addr)(core_id) := '1';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Shared
                end if;
                sent_snoop_count_var := sent_snoop_count_var - 1;

              elsif (txdat_opcode(core_id) = std_logic_vector(to_unsigned(2, CHIE_DAT_FLIT_OPCODE_WIDTH))) then -- CHIE_COPYBACKWRDATA
                if (req_opcode = 23) then -- CHIE_WRITECLEANFULL
                  tmp_directory(cacheline_addr)(core_id) := '1';
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive
                elsif (req_opcode = 26 or req_opcode = 27) then -- CHIE_WRITEBACKPTL / CHIE_WRITEBACKFULL
                      tmp_directory(cacheline_addr)(core_id) := '0';
                      tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
                end if;
                copybackdata_received <= '1';
              
              elsif (txdat_opcode(core_id) = std_logic_vector(to_unsigned(3, CHIE_DAT_FLIT_OPCODE_WIDTH))) then -- CHIE_NONCOPYBACKWRDATA
                -- CHIE_ATOMICLOAD (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
                if (req_opcode = 48 or req_opcode = 49 or req_opcode = 50 or req_opcode = 51 
                    or req_opcode = 52 or req_opcode = 53 or req_opcode = 54 or req_opcode = 55 or req_opcode = 56) then
                  response_sent <= '0';
                  send_data <= '1';
                  amo_data_ready <= '1';
                elsif (req_opcode = 28) then  -- WriteNoSnp(28)
                  response_sent <= '0';
                  send_response <= '1';
                  io_data_ready <= '1';
                end if;
              end if;
            end if;
            
          end if;

          update_llc(core_id) := '0';
          update_io(core_id) := '0';
          invalid_snp_rsp(core_id) := '0';
          amo_data_received(core_id) := '0';
        end if;
      end loop;

    end procedure update_LLC_txdat;



    -- Procedure for receiving Data packets
    -- TXDAT channel
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

      variable opcode : integer := 0;
      variable req_opcode : integer := 0;
      variable resp : integer := 0;
    begin
      value := (others => '0');
      update_llc_tmp := update_llc;
      txdat_crdt_counter_tmp := txdat_crdt_counter;
      req_opcode := to_integer(signed(txreq_opcode));

      for id in 0 to rnf_count-1 loop
        opcode := to_integer(signed(txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1)));
        resp := to_integer(signed(txdatflit((id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)));
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

          -- When the DAT is NonCopyBackWriteData and AMO request is being handled
          -- (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
          if ( opcode = 3 ) then 
            if (req_opcode = 48 or req_opcode = 49 or req_opcode = 50 
              or req_opcode = 51 or req_opcode = 52 or req_opcode = 53 
              or req_opcode = 54 or req_opcode = 55 or req_opcode = 56) then  
              amo_data_received(id) := '1';
            elsif (req_opcode = 28) then -- WriteNoSnp
              update_io(id) := '1';
            end if; 
          end if;


            -- Check DATA response for ReadUnique(SnpUnique) or CleanUnique(SnpCleanInvalid) when test snoop is done
          if ( do_snoop_test = '1' and (req_opcode = 7 or req_opcode = 11) ) then
            -- CHIE_SNP_RESP_I_PD=4     _I=0
            if ( (to_integer(unsigned(txdat_resp_tmp(id))) = 4 or to_integer(unsigned(txdat_resp_tmp(id))) = 0) and (opcode = 1 or opcode = 5) and expect_empty_snpresp = '0') then
              correct_response := '1';
            end if;

          -- DATA response for ReadShared(SnpShared) or ReadClean(SnpClean)
          elsif ( do_snoop_test = '1' and (req_opcode = 1 or req_opcode = 2) ) then
            -- CHIE_SNP_RESP_SC_PD=5    _SC=1
            if ( (to_integer(unsigned(txdat_resp_tmp(id))) = 5 or to_integer(unsigned(txdat_resp_tmp(id))) = 1) and (opcode = 1 or opcode = 5) and expect_empty_snpresp = '0') then
              correct_response := '1';
            end if;

          end if;


            if (running = '1') then
              write(line_out, string'("Received data packet"));
              writeline(logfile, line_out);
              write(line_out, string'("Opcode: "));
              write(line_out, to_integer(unsigned(txdat_opcode_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Source ID: "));
              write(line_out, to_integer(unsigned(txdat_srcid_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Transaction ID: "));
              write(line_out, to_integer(unsigned(txdat_txnid_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Critical Chunk ID: "));
              write(line_out, to_integer(unsigned(txdat_ccid_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Data Chunk ID: "));
              write(line_out, to_integer(unsigned(txdat_dataid_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Resp code: "));
              write(line_out, to_integer(unsigned(txdat_resp_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Forward state: "));
              write(line_out, to_integer(unsigned(txdat_fwdstate_tmp(id))));
              writeline(logfile, line_out);
              write(line_out, string'("Byte Enable: "));
              write(line_out, txdat_be_tmp(id));
              writeline(logfile, line_out);
              write(line_out, string'("Data: "));
              write(line_out, txdat_data_tmp(id));
              writeline(logfile, line_out);
              write(line_out, string'("####################"));
              writeline(logfile, line_out);
            end if;

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

      -- Point for LLC updated procedure the responded RN-F channels
      update_llc := update_llc_tmp;


      -- Address when updating LLC with received response
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




    -- Procedure to wait one cycle and check sent credits
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
          -- In the testbench it's straightforward to just propagate it to certain RNF
    -- RXSNP channel
    procedure chi_rxsnp_snoop ( variable value : out std_logic_vector(31 downto 0) ) is
      --
      variable tx_done : std_logic := '0';
      variable value0 : std_logic := '0';
      variable value1 : std_logic := '1';
    begin
      --
      value := (others => '0');

      rxsnp_procedure <= '1';

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

            -- 1=SnpShared
            -- 2=SnpClean
            -- 7=SnpUnique
            -- 8=SnpCleanShared
            -- 9=SnpCleanInvalid
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_OPCODE_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_FWDTXNID_HI+1)       <= snoop_opcode;

            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_ADDR_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_OPCODE_HI+1)           <= snoop_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 3); -- indx 43 to 3

            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_NS_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_ADDR_HI+1)               <= "0";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_DONOTGOTOSD_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_NS_HI+1)        <= "0";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TRACETAG_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_RETTOSRC_HI+1)     <= "0";
            rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TGTID_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_TRACETAG_HI+1)        <= (others => '0');

            if (do_snoop_test = '1' and do_rettosrc_snoop = '1') then
              rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_RETTOSRC_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_DONOTGOTOSD_HI+1)  <= "1";
            else
              rxsnpflit((id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_RETTOSRC_HI downto (id*CHIE_SNP_FLIT_WIDTH)+CHIE_SNP_FLIT_DONOTGOTOSD_HI+1)  <= "0";
            end if;


            tx_done := '1';

            decrement_rxsnpcrdt(id) := '1';

            sent_snoop_count_var := sent_snoop_count_var + 1;
            

            if (running = '1') then
              write(line_out, string'("Sending snoop"));
              writeline(logfile, line_out);
              write(line_out, string'("Opcode: "));
              write(line_out, to_integer(unsigned(snoop_opcode)));
              writeline(logfile, line_out);
              write(line_out, string'("Target ID: "));
              write(line_out, id);
              writeline(logfile, line_out);
              write(line_out, string'("Transaction ID: "));
              write(line_out, to_integer(unsigned(snoop_txnid)));
              writeline(logfile, line_out);
              write(line_out, string'("Address: "));
              write(line_out, snoop_addr);
              writeline(logfile, line_out);
              write(line_out, string'("####################"));
              writeline(logfile, line_out);
            end if;

          end if;
        end if;
      end loop;

      snoopees <= (others => '0');
      snoop_opcode <= (others => '0');
      send_snoop <= '0';
      snoop_sent <= '1';

    end procedure chi_rxsnp_snoop;



    -- Procedure for RXRSP response
    -- RSP channel
    procedure chi_rxrsp_response ( variable value : out std_logic_vector(31 downto 0) ) is
      -- variables
      variable tx_done : std_logic := '0';
      variable value0 : std_logic := '0';
      variable value1 : std_logic := '1';
      variable core_id : integer := 0;
      variable req_opcode : integer := 0;
      variable waiting_ack_count_next : integer := 0;
      variable zero_mask : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
      variable cacheline_addr : integer := 0;
    begin

      core_id := to_integer(signed(txreq_srcid));
      cacheline_addr := to_integer(unsigned(txreq_addr(mem_address_space_w-1 downto 6)));

      rxrsp_procedure <= '1';
      rxrspflitpend(core_id) <= '1';
      req_opcode := to_integer(signed(txreq_opcode));

      if (to_integer(signed(rxrsp_crdt_count(core_id))) > 0) then
        -- ReadNoSnp(4; ordered)WriteCleanFull/WriteBackPtl,-Full/WriteNoSnp(28)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
        if (req_opcode = 4 or req_opcode = 2 or req_opcode = 7 or req_opcode = 11 or req_opcode = 23 or req_opcode = 26 
          or req_opcode = 27 or req_opcode = 28 or req_opcode = 48 or req_opcode = 49 or req_opcode = 50 
          or req_opcode = 51 or req_opcode = 52 or req_opcode = 53 or req_opcode = 54 or req_opcode = 55 or req_opcode = 56) then   
          rxrspflitv(core_id) <= '1';

          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI downto (core_id*CHIE_RSP_FLIT_WIDTH))                                <= txreq_qos;         
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_QOS_HI+1)       <= txreq_srcid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TGTID_HI+1)     <= txreq_tgtid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_SRCID_HI+1)     <= txreq_txnid;
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI+1)   <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_FWDSTATE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI+1)   <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_PCRDTYPE_HI+1)  <= (others => '0');
          rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TRACETAG_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TAGOP_HI+1)  <= (others => '0');

          if ( req_opcode = 23 or req_opcode = 26 or req_opcode = 27 ) then -- Writes
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) 
                    <= txreq_txnid; 
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                    <= std_logic_vector(to_unsigned(5, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_COMPDBIDRESP
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    
                    <= (others => '0');
            response_sent <= '1';

          elsif ( req_opcode = 28 or req_opcode = 48 or req_opcode = 49 or req_opcode = 50 or req_opcode = 51 or req_opcode = 52 
                or req_opcode = 53 or req_opcode = 54 or req_opcode = 55 or req_opcode = 56 ) then --AMOs

            if (req_opcode = 28 and io_data_ready = '1') then 
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                <= std_logic_vector(to_unsigned(4, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_COMP (noncacheable data had been received)
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) 
                <= (others => '0'); 
                write_io_data <= '1';
            else
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                <= std_logic_vector(to_unsigned(6, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_DBIDRESP
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) <= txreq_txnid; 
            end if;
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1) 
                <= (others => '0');
            response_sent <= '1';

          elsif (req_opcode = 11) then  -- CleanUnique
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                    <= std_logic_vector(to_unsigned(4, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_COMP
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    
                    <= std_logic_vector(to_unsigned(2, CHIE_RSP_FLIT_RESP_WIDTH));  -- CHIE_COMP_RESP_UC
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) 
                <= (others => '0'); 

            -- Update LLC
            zero_mask(core_id) := '1'; 
            tmp_directory(cacheline_addr) := zero_mask;
            tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive

            waiting_ack <= '1';
            waiting_ack_count_next := to_integer(signed(waiting_ack_count(core_id))) + 1;
            waiting_ack_count(core_id) <= std_logic_vector(to_unsigned(waiting_ack_count_next, 32));
          
          elsif (req_opcode = 4) then  -- ReadNoSnp, requires ordering and ReadReceipt
            
            if (do_separate_resp = '1') then
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                      <= std_logic_vector(to_unsigned(11, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_RESPSEPDATA
            else
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                      <= std_logic_vector(to_unsigned(8, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_READRECEIPT
            end if;

            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    
                    <= std_logic_vector(to_unsigned(0, CHIE_RSP_FLIT_RESP_WIDTH));  -- 
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) 
                    <= (others => '0'); 

            send_uncached_data <= '1';

          elsif (do_separate_resp = '1' and (req_opcode = 2 or req_opcode = 7)) then -- ReadClean/ReadUnique respsepdata

            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_OPCODE_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_TXNID_HI+1)    
                    <= std_logic_vector(to_unsigned(11, CHIE_RSP_FLIT_OPCODE_WIDTH));  -- CHIE_RESPSEPDATA
            rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_DBID_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_CBUSY_HI+1) 
                    <= (others => '0'); 

            if (req_opcode = 2) then
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    
                    <= std_logic_vector(to_unsigned(1, CHIE_RSP_FLIT_RESP_WIDTH));  -- CHIE_COMP_RESP_SC
            elsif (req_opcode = 7) then
              rxrspflit((core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESP_HI downto (core_id*CHIE_RSP_FLIT_WIDTH)+CHIE_RSP_FLIT_RESPERR_HI+1)    
                    <= std_logic_vector(to_unsigned(2, CHIE_RSP_FLIT_RESP_WIDTH));  -- CHIE_COMP_RESP_UC
            end if;

            send_data <= '1';

          end if;

          send_response <= '0';
          decrement_rxrspcrdt(core_id) := '1';

          tx_done := '1';



          if (running = '1') then
            write(line_out, string'("Sending response"));
            writeline(logfile, line_out);
            write(line_out, string'("Opcode: "));
            write(line_out, 5);   -- only compdbidresps are sent
            writeline(logfile, line_out);
            write(line_out, string'("Target ID: "));
            write(line_out, to_integer(unsigned(txreq_srcid)));
            writeline(logfile, line_out);
            write(line_out, string'("Transaction ID: "));
            write(line_out, to_integer(unsigned(txreq_txnid)));
            writeline(logfile, line_out);
            write(line_out, string'("Data Base ID: "));
            write(line_out, to_integer(unsigned(txreq_txnid)));
            writeline(logfile, line_out);
            write(line_out, string'("####################"));
            writeline(logfile, line_out);
          end if;
        end if;
      end if;


    end procedure chi_rxrsp_response;





    -- Procedure for RXDAT response
    -- RXDAT channel
    procedure chi_rxdat_response ( variable value : out std_logic_vector(31 downto 0) ) is
      constant zeros : std_logic_vector(rnf_count-1 downto 0) := (others => '0');
      constant snpshared_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(1, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 1=SnpShared
      constant snpclean_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(2, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 2=SnpClean
      constant snpunique_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(7, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 7=SnpUnique
      constant snpcleanshared_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(8, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 8=SnpCleanShared
      constant snpcleaninvalid_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(9, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 9=SnpCleanInvalid
      constant snpmakeinvalid_opcode : std_logic_vector(CHIE_SNP_FLIT_OPCODE_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(10, CHIE_SNP_FLIT_OPCODE_WIDTH)); -- 10=SnpMakeInvalid
      
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

      variable amo_old_data_chunk_addr : integer := 0;
      variable amo_old_data_chunk_size : integer := 0;
      variable amo_old_data : std_logic_vector(511 downto 0) := (others => '0');
      variable data_id : std_logic_vector(1 downto 0) := (others => '0');
      variable data_id_int : integer := 0;

    begin

      -- 
      rxdatflitpend(core_id) <= '1';
      rxdat_procedure <= '1';

      -- Flit number and data-ID
      flit_num := to_integer(unsigned(data_flit_num));
      if (do_reverseresponse_test = '1' and reverse_resp_triggered = '1') then 
        if (dat_flits_to_send = 2) then
          data_id := std_logic_vector(to_unsigned(dat_flits_to_send-flit_num*2, 2));
        elsif (dat_flits_to_send = 1) then
          data_id := "00";
        else 
          data_id := std_logic_vector(to_unsigned(dat_flits_to_send-1-flit_num, 2));
        end if;
      else
        if (dat_flits_to_send = 2) then
          data_id := std_logic_vector(to_unsigned(flit_num*2, 2));
        else 
          data_id := std_logic_vector(to_unsigned(flit_num, 2));
        end if;
      end if;
      data_id_int := to_integer(unsigned(data_id));

      core_id := to_integer(signed(txreq_srcid));
      cacheline_addr := to_integer(unsigned(txreq_addr(mem_address_space_w-1 downto 6)));
      opcode := to_integer(signed(txreq_opcode));

      -- For the snoop test
      if ( do_snoop_test = '0' ) then
        snoop_mask(core_id) := '0';
      end if;

      sharers := snoop_mask and tmp_directory(cacheline_addr);
      is_owner := tmp_directory(cacheline_addr)(core_id);

      -- For the snoop test
      if ( expect_empty_snpresp = '1' and do_snoop_test = '1' ) then
        sharers(core_id) := '1';
      end if;


      -- If there is Write requests pending, let them go first before the data is sent/snooped -> Ongoing transaction is stalled
        -- This is also controlled by the unit/corner test signals if the tests are executed
      if ( bypass_mshr_valid(bypass_mshr_read_idx) = '1' and do_snoop_test = '0' and
            ( (flit_num = 0 and dirty_resp_triggered = '0' and mixed_data_resp_done = '0') 
              or (flit_num = 0 and dirty_resp_triggered = '1' and mixed_data_resp_done = '0')
              or (flit_num = 0 and (dirty_resp_triggered = '1' or mixed_resp_triggered = '1') and mixed_data_resp_done = '1') ) ) then
          handle_writereq <= '1';
          send_data <= '0';      

          -- Do not let the tb do another write-req in the middle of (sending dat flitnum=1) some other request than the test request
          if (mixed_data_resp_done = '1') then
            mixed_data_resp_done := '0';
          end if;
      
      -- Do a request switch if there is tested mixed data responses
      elsif ( do_mixeddata_test = '1' and (dirty_resp_triggered = '1' or mixed_resp_triggered = '1') and flit_num = 1 ) then

        -- Dirty ReadUnique stall, addr should be 8007e904 , 
        if txreq_addr(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0) = "00000000000010000000000001111110100100000100" and intermediate_resp = '0' then 
          switch_to_next_req <= '1'; -- Switch to next req, first in buffer, 
          send_data <= '0';

        -- Switch back to preceding request
        elsif intermediate_resp = '1' then
          switch_back <= '1';
          send_data <= '0';
        end if;

      -- ReadUnique and line is in other RNFs -> SnpUnique
      elsif ( opcode = 7 and sharers /= zeros ) then
          send_snoop <= '1';
          send_data <= '0';
          snoopees <= sharers;
          snoop_addr <= txreq_addr;
          snoop_txnid <= txreq_txnid;
          snoop_opcode <= snpunique_opcode;

      -- CleanUnique or MakeUnique (dataless-transaction -> no data included with response) 
      elsif ( opcode = 11 or opcode = 12 ) then
        if (sharers /= zeros) then
          send_snoop <= '1';
          send_data <= '0';
          snoopees <= sharers;
          snoop_addr <= txreq_addr;
          snoop_txnid <= txreq_txnid;
          if opcode = 11 then 
            snoop_opcode <= snpcleaninvalid_opcode;
          elsif opcode = 12 then 
            snoop_opcode <= snpmakeinvalid_opcode;
          end if;
            
        else 
          sharers(core_id) := '1'; -- used sharers-var to update directory
          tmp_directory(cacheline_addr) := sharers;
          tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive
          send_response <= '1';
          send_data <= '0';
        end if;

      -- ReadShared/ReadClean and line is Exclusive or Modified in other RNF -> SnpShared
      elsif ( (opcode = 1 or opcode = 2) and sharers /= zeros and (tmp_cacheline_state(cacheline_addr) = "10" or tmp_cacheline_state(cacheline_addr) = "11"
                or (do_snoop_test = '1' and do_rettosrc_snoop = '1')) ) then

          send_snoop <= '1';
          send_data <= '0';
          snoopees <= sharers;
          snoop_addr <= txreq_addr;
          snoop_txnid <= txreq_txnid;
          
          if (opcode = 1) then  -- ReadShared
            snoop_opcode <= snpshared_opcode;
          elsif (opcode = 2) then   -- ReadClean
            snoop_opcode <= snpclean_opcode;
          end if;

      -- AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
      elsif ( (opcode = 48 or opcode = 49 or opcode = 50 
            or opcode = 51 or opcode = 52 or opcode = 53 
            or opcode = 54 or opcode = 55 or opcode = 56) and amo_data_ready = '0') then
        if ( tmp_directory(cacheline_addr) /= zeros ) then

            send_snoop <= '1';
            send_data <= '0';
            snoop_addr <= txreq_addr;
            snoop_txnid <= txreq_txnid;
            snoop_opcode <= snpunique_opcode;
            if ( txreq_excl_snoopme = "1" ) then
              snoopees <= tmp_directory(cacheline_addr);
            else 
              snoopees <= sharers;
            end if;

        else 
          send_data <= '0';
          send_response <= '1';
        end if;

      -- Line is Shared or not owned by other RNFs -> send CompData
      else 

        if (to_integer(signed(rxdat_crdt_count(core_id))) > 0) then         

          -- qos and ids
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI downto (core_id*CHIE_DAT_FLIT_WIDTH))                                <= txreq_qos;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI+1)       <= txreq_srcid;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI+1)     <= txreq_tgtid;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI+1)     <= txreq_txnid;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI+1)   <= txreq_tgtid;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)     <= data_id;
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI+1)  <= (others => '0');

          -- OPCODE
          if (do_separate_resp = '1' and (opcode = 2 or opcode = 7)) then
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1) 
                      <= std_logic_vector(to_unsigned(11, CHIE_DAT_FLIT_OPCODE_WIDTH)); -- DataSepResp 
          else 
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1) 
                      <= std_logic_vector(to_unsigned(4, CHIE_DAT_FLIT_OPCODE_WIDTH)); -- CompData 
          end if;

          -- DATA AND CACHELINE STATE
            -- Data is sent back to RNF according to the Request type and cacheline state.
            -- If cacheline is invalid, 0 is sent. If it is Shared/Exclusive, the stored value is sent back.
            -- If the requester wasn't already the owner of the cacheline, there is done snoops to the exclusive owners.
          -- ReadUnique
          if ( opcode = 7 ) then   

            -- Data and cacheline state
            if ( send_unique_dirty_cline = '1' and dirty_resp_triggered = '1' ) then
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1) 
                                                <= (CHIE_DAT_FLIT_DATA_WIDTH-1 downto CHIE_DAT_FLIT_DATA_WIDTH-1 => '0', 
                                                    CHIE_DAT_FLIT_DATA_WIDTH-2 downto CHIE_DAT_FLIT_DATA_WIDTH-17 => '1' , 
                                                    CHIE_DAT_FLIT_DATA_WIDTH-18 downto 0 => '0');
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "110";   --UDPD TEST
              if ( flit_num = dat_flits_to_send-1 ) then
                send_unique_dirty_cline := '0'; -- Do response with the CompData_UD_PD just once
              end if;
            else 
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         
                          <= tmp_LLCache(cacheline_addr)(128*data_id_int+CHIE_DAT_FLIT_DATA_WIDTH-1 downto 128*data_id_int);
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "010";  -- data is given as: not dirty, UniqueClean UC
            end if;

            -- LLC updates
            if ( flit_num = dat_flits_to_send-1 ) then
            -- Cacheline in SHARED(/VALID) state, return stored value 
              if ( tmp_cacheline_state(cacheline_addr) = "01" ) then
                sharers(core_id) := '1'; -- used sharers-var to update directory
                tmp_directory(cacheline_addr) := sharers;
                tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive

              -- Invalid state, return new value and make owner
              elsif ( tmp_cacheline_state(cacheline_addr) = "00" ) then
                zero_mask(core_id) := '1';
                tmp_directory(cacheline_addr) := zero_mask;

                if ( send_unique_dirty_cline = '1' and dirty_resp_triggered = '1' ) then
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(3, 2)); -- Modified, UDPD TEST
                else
                  tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(2, 2)); -- Exclusive
                end if;
              -- If Requester is already owner of the cacheline, no LLC changes
              end if;

            end if;

          -- ReadShared / ReadClean
          elsif ( opcode = 1 or opcode = 2 ) then
            -- Data and cacheline state
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "001";  -- data is given as: not dirty, SharedClean SC
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         
                        <= tmp_LLCache(cacheline_addr)(128*data_id_int+CHIE_DAT_FLIT_DATA_WIDTH-1 downto 128*data_id_int);
            
            -- LLC update
            if ( flit_num = dat_flits_to_send-1 ) then
              -- Cacheline in Shared/Valid state, return stored value 
              if ( tmp_cacheline_state(cacheline_addr) = "01" ) then
                sharers(core_id) := '1'; 
                tmp_directory(cacheline_addr) := sharers;
              
              -- Invalid state, return new value
              elsif ( tmp_cacheline_state(cacheline_addr) = "00" ) then
                zero_mask(core_id) := '1';
                tmp_directory(cacheline_addr) := zero_mask;
                tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Shared
              -- If Requester is already owner of the cacheline, no LLC changes

              end if;
            end if;

            -- AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
          elsif ( opcode = 48 or opcode = 49 or opcode = 50 or opcode = 51 
                or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56 ) then
            -- Data and cacheline state
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "000";  -- data is given as: Invalid
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1)         
                        <= tmp_LLCache(cacheline_addr)(128*data_id_int+CHIE_DAT_FLIT_DATA_WIDTH-1 downto 128*data_id_int);

            if ( flit_num = dat_flits_to_send-1 ) then
              tmp_directory(cacheline_addr) := zero_mask;
              tmp_cacheline_state(cacheline_addr) := std_logic_vector(to_unsigned(1, 2)); -- Valid
            end if;


          end if;

          -- FwdState, CBusy, DBID, CCID
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI+1)   <= (others => '0'); -- indicates data state in Snoopee in snoop responses with Direct Cache Transfer
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI+1)  <= (others => '0'); -- completer busyness, implemention defined
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI+1)      <= txreq_txnid;     -- HNF's txnid, REQ's txnid given, used in CompAck response
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI+1)       <= txreq_addr(5 downto 4); -- requested 128 bit chunk, compared to DataID value in RNF                
          -- TagOP, Tag, TU, TraceTag, BE
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI+1)    <= (others => '0');  -- not in CHI B
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAGOP_HI+1)       <= (others => '0');  -- not in CHI B
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TAG_HI+1)          <= (others => '0');  -- not in CHI B
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TU_HI+1)     <= (others => '0');
          -- inapplicable with CompData response data transfers (the whole line must be valid with Read-reqs, with atomics whole line is invalid(old data))
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TRACETAG_HI+1)     <= (others => '0');  

          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI+1)       <= txreq_addr(5 downto 4); -- requested 128 bit chunk, compared to DataID value in RNF    

          -- fill the rest of the flit, for some reason the datflit width is defined wider in OpenNoC than CHI specifies for 256data
          rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_WIDTH-1 downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI+1)       <= (others => '0');  

          rxdatflitv(core_id) <= '1';

          decrement_rxdatcrdt(core_id) := '1';

          -- Print package
          if (running = '1') then
            write(line_out, string'("Sending data packet:"));
            writeline(logfile, line_out);
            write(line_out, string'("Target ID: "));
            write(line_out, to_integer(unsigned(txreq_srcid)));
            writeline(logfile, line_out);
            write(line_out, string'("Transaction ID: "));
            write(line_out, to_integer(unsigned(txreq_txnid)));
            writeline(logfile, line_out);
            write(line_out, string'("Critical Chunk ID: "));
            write(line_out, to_integer(unsigned(txreq_addr(5 downto 4))));
            writeline(logfile, line_out);
            write(line_out, string'("Data Chunk ID: "));
            write(line_out, flit_num);
            writeline(logfile, line_out);
            write(line_out, string'("Address: "));
            write(line_out, txreq_addr);
            writeline(logfile, line_out);
            write(line_out, string'("####################"));
            writeline(logfile, line_out);
          end if;

          -- if all data flits are sent
              -- Conditions for sent data responses, responses are made in reverse for some tests
          if (flit_num = dat_flits_to_send-1) then
            tx_done := '1';

          --AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55), AtomicSwap(56)
            if ( txreq_expcompack = "0" and amo_data_ready = '1' and (opcode = 48 or opcode = 49 or opcode = 50 
                  or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) ) then 
              -- AMO data should already be ready at this point when using this testbench
              do_amo <= '1';
            else
              waiting_ack_count_next := to_integer(signed(waiting_ack_count(core_id))) + 1;
              waiting_ack_count(core_id) <= std_logic_vector(to_unsigned(waiting_ack_count_next, 32));
              waiting_ack <= '1';
            end if;

            -- reset the data packet counter
            data_flit_num := (others => '0');
            send_data <= '0';

          elsif (flit_num < dat_flits_to_send-1) then
            flit_num := flit_num + 1;
            data_flit_num := std_logic_vector(to_unsigned(flit_num, 32));

          end if;

        else 
          rxdatflitv(core_id) <= '0';
        end if; -- end of credit condition
      end if; -- end of snoop condition
    end procedure chi_rxdat_response;


    -- Procedure for handling ReadNoSnp transactions.
    -- Especially for reading from the bootrom address space. (with CVA6-OP-CHI)
    procedure chi_rxdat_nosnprsp ( variable value : out std_logic_vector(31 downto 0) ) is
      variable flit_num : integer := 0;
      variable core_id : integer := 0;
      variable waiting_ack_count_next : integer := 0;
      variable data_field : std_logic_vector(511 downto 0) := (others => '0');
      variable addr_5_3_int : integer := 0;
    begin

      core_id := to_integer(signed(txreq_srcid));
      rxdatflitpend(core_id) <= '1';
      flit_num := to_integer(unsigned(data_flit_num)); 
      addr_5_3_int := to_integer(unsigned(txreq_addr(5 downto 3)));

      -- If the request was to read from bootrom address space
      if (txreq_addr >= bootrom_base) then
        -- First request for the bootrom data with address. The data should be at the bootrom data_o port at the second next cycle
        if (bootrom_req = '0') then
          bootrom_addr <= (63 downto CHIE_REQ_FLIT_ADDR_WIDTH => '0') & txreq_addr;
          bootrom_req <= '1';
        elsif (bootrom_read_done = '0' and bootrom_req = '1') then
          bootrom_read_done <= '1';
        else 

          -- place data to the correct place in data field
          data_field((64*addr_5_3_int)+63 downto (64*addr_5_3_int)) := bootrom_rdata;

          if (to_integer(signed(rxdat_crdt_count(core_id))) > 0) then

                      -- qos and ids
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI downto (core_id*CHIE_DAT_FLIT_WIDTH))                                <= txreq_qos;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_QOS_HI+1)       <= txreq_srcid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TGTID_HI+1)     <= txreq_tgtid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_SRCID_HI+1)     <= txreq_txnid;
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_TXNID_HI+1)   <= txreq_tgtid;

            if (do_separate_resp = '1') then
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1) 
                                                                            <= std_logic_vector(to_unsigned(11, CHIE_DAT_FLIT_OPCODE_WIDTH)); -- DataSepResp 
            else
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_HOMENID_HI+1) 
                                                                            <= std_logic_vector(to_unsigned(4, CHIE_DAT_FLIT_OPCODE_WIDTH)); -- CompData 
            end if;
            
            --
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_OPCODE_HI+1)  <= (others => '0');
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESPERR_HI+1)    <= "000";  -- data is given as: invalid (non-coherent data)

            if (dat_flits_to_send = 2) then
            -- DataID according to flit_num
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   
                        <= std_logic_vector(to_unsigned(flit_num*2, 2));
            else 
              rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATAID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CCID_HI+1)   
                        <= data_flit_num(1 downto 0);
            end if;

            -- Data chunk to be sent
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DATA_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_BE_HI+1) 
                      <= data_field(((flit_num+1)*(512/dat_flits_to_send)-1) downto ((flit_num)*(512/dat_flits_to_send)));

            -- FwdState, CBusy, DBID, CCID
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_RESP_HI+1)   <= (others => '0'); -- indicates data state in Snoopee in snoop responses with Direct Cache Transfer
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_FWDSTATE_HI+1)  <= (others => '0'); -- completer busyness, implemention defined
            rxdatflit((core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_DBID_HI downto (core_id*CHIE_DAT_FLIT_WIDTH)+CHIE_DAT_FLIT_CBUSY_HI+1)      <= txreq_txnid;     -- HNF's txnid, REQ's txnid given, used in CompAck response
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

            -- if data flits are sent
            if (flit_num = dat_flits_to_send-1) then
              if (txreq_expcompack = "1") then
                waiting_ack_count_next := to_integer(signed(waiting_ack_count(core_id))) + 1;
                waiting_ack_count(core_id) <= std_logic_vector(to_unsigned(waiting_ack_count_next, 32));
                waiting_ack <= '1';
              end if;

              -- reset the data packet counter
              data_flit_num := (others => '0');
              send_uncached_data <= '0';

              bootrom_req <= '0';
              bootrom_read_done <= '0';

            else 
              flit_num := flit_num + 1;
              data_flit_num := std_logic_vector(to_unsigned(flit_num, 32));
            end if;

          else 
            rxdatflitv(core_id) <= '0';
          end if; -- end of credit condition
        end if; 
      else 
      end if;
        

    end procedure chi_rxdat_nosnprsp;


    -- Procedure for receiving TXREQ transactions
    -- TXREQ channel
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

      -- Allocate requests to the TB-MSHR
      for order_id in 0 to rnf_count-1 loop

        core_id := sort_array(order_id);

        if (txreqflitv(core_id) = '1') then
          opcode := to_integer(signed(txreqflit((core_id*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_OPCODE_HI downto (core_id*CHIE_REQ_FLIT_WIDTH)+CHIE_REQ_FLIT_RETURNTXNID_HI+1)));

          if (opcode = 23 or opcode = 26 or opcode = 27) then -- WriteCleanFull, WriteBackPtl/-FUll
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


    -- Take next pending transaction from the MSHR
    -- Write and stalled transactions bypass others.
    procedure next_transaction( variable value : out std_logic_vector(31 downto 0) ) is
      variable opcode : integer := 0;
      variable core_id : integer := 0;
      variable address : std_logic_vector(CHIE_REQ_FLIT_ADDR_WIDTH-1 downto 0) := (others => '0');
      variable order : integer := 0;

    begin
      value := (others => '0');
    
    if (do_snoop_test = '1') then   -- Snoop test request

        if (do_unique_snoop = '1') then
          opcode := 7;
          txreq_opcode              <= std_logic_vector(to_unsigned(7, CHIE_REQ_FLIT_OPCODE_WIDTH)); -- ReadUnique
        elsif (do_shared_snoop = '1') then
          opcode := 1;
          txreq_opcode              <= std_logic_vector(to_unsigned(1, CHIE_REQ_FLIT_OPCODE_WIDTH)); -- ReadShared
        elsif (do_clean_snoop = '1' or do_rettosrc_snoop = '1') then
          opcode := 2;
          txreq_opcode              <= std_logic_vector(to_unsigned(2, CHIE_REQ_FLIT_OPCODE_WIDTH)); -- ReadClean
        elsif (do_cleaninvalid_snoop = '1') then
          opcode := 11;
          txreq_opcode              <= std_logic_vector(to_unsigned(11, CHIE_REQ_FLIT_OPCODE_WIDTH)); -- CleanUnique
        elsif (do_makeinvalid_snoop = '1') then
          opcode := 12;
          txreq_opcode              <= std_logic_vector(to_unsigned(12, CHIE_REQ_FLIT_OPCODE_WIDTH)); -- MakeUnique
          expect_empty_snpresp := '1';
        end if;

        
        txreq_valid               <= '1';
        txreq_qos                 <= (others => '0');
        txreq_tgtid               <= (others => '0');
        txreq_srcid               <= std_logic_vector(to_unsigned(0, CHIE_REQ_FLIT_SRCID_WIDTH));
        txreq_txnid               <= std_logic_vector(to_unsigned(22, CHIE_REQ_FLIT_TXNID_WIDTH));
        txreq_returnnid           <= (others => '0');
        txreq_endian              <= (others => '0');
        txreq_returntxnid         <= std_logic_vector(to_unsigned(5, CHIE_REQ_FLIT_RETURNTXNID_WIDTH));
        txreq_size                <= std_logic_vector(to_unsigned(6, CHIE_REQ_FLIT_SIZE_WIDTH));
        txreq_addr                <= X"0008007E940"; -- 8101th  X"8007E940"
        txreq_ns                  <= (others => '0');
        txreq_likelyshared        <= std_logic_vector(to_unsigned(1, CHIE_REQ_FLIT_LIKELYSHARED_WIDTH));
        txreq_allowretry          <= std_logic_vector(to_unsigned(1, CHIE_REQ_FLIT_ALLOWRETRY_WIDTH));
        txreq_order               <= (others => '0');
        txreq_pcrdtype            <= (others => '0');
        txreq_memattr             <= "1101";
        txreq_snpattr             <= (others => '0');
        txreq_lpid                <= (others => '0');
        txreq_excl_snoopme        <= (others => '0');
        txreq_expcompack          <= std_logic_vector(to_unsigned(1, CHIE_REQ_FLIT_EXPCOMPACK_WIDTH));
        txreq_tagop               <= (others => '0');
        txreq_tracetag            <= (others => '0');

        -- ReadUnique(7)/ReadShared(1)/ReadClean(2)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55)/AtomicSwap(56)
        if (opcode = 7 or opcode = 1 or opcode = 2 or opcode = 11 or opcode = 12 or opcode = 48 or opcode = 49 or opcode = 50 
            or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) then 
          send_data <= '1';
        elsif (opcode = 4) then -- ReadNoSnp
          send_uncached_data <= '1';
        else
          --
        end if;


        if (running = '1') then
          write(line_out, string'("--------- Handling SNOOPTEST request: ---------"));
          writeline(logfile, line_out);
        end if;


      -- Check first if there is left any stalled request 
        -- stall could happen when there has been received Write req just when previous req was about to snoop for cacheline
      elsif (stalled_req_valid = '1') then

        opcode := to_integer(signed(stalled_req_opcode));
        core_id := to_integer(signed(stalled_req_srcid));
        
        txreq_valid               <= stalled_req_valid;
        txreq_qos                 <= stalled_req_qos;
        txreq_tgtid               <= stalled_req_tgtid;
        txreq_srcid               <= stalled_req_srcid;
        txreq_txnid               <= stalled_req_txnid;
        txreq_returnnid           <= stalled_req_returnnid;
        txreq_endian              <= stalled_req_endian;
        txreq_returntxnid         <= stalled_req_returntxnid;
        txreq_opcode              <= stalled_req_opcode;
        txreq_size                <= stalled_req_size;
        txreq_addr                <= stalled_req_addr;
        txreq_ns                  <= stalled_req_ns;
        txreq_likelyshared        <= stalled_req_likelyshared;
        txreq_allowretry          <= stalled_req_allowretry;
        txreq_order               <= stalled_req_order;
        txreq_pcrdtype            <= stalled_req_pcrdtype;
        txreq_memattr             <= stalled_req_memattr;
        txreq_snpattr             <= stalled_req_snpattr;
        txreq_lpid                <= stalled_req_lpid;
        txreq_excl_snoopme        <= stalled_req_excl_snoopme;
        txreq_expcompack          <= stalled_req_expcompack;
        txreq_tagop               <= stalled_req_tagop;
        txreq_tracetag            <= stalled_req_tracetag;

        data_flit_num := stalled_rxdat_flitnum;

        -- ReadUnique(7)/ReadShared(1)/ReadClean(2)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55)/AtomicSwap(56)
        if (opcode = 7 or opcode = 1 or opcode = 2 or opcode = 11 or opcode = 48 or opcode = 49 or opcode = 50 
            or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) then 
          send_data <= '1';
        elsif (opcode = 4) then -- ReadNoSnp
          if (to_integer(signed(stalled_req_order)) /= 0) then
            send_response <= '1';
          else 
            send_uncached_data <= '1';
          end if;
        else
          --
        end if;

        stalled_req_valid <= '0';

        if (running = '1') then
          write(line_out, string'("--------- Handling request: ---------"));
          writeline(logfile, line_out);
          write(line_out, string'("Opcode: "));
          write(line_out, to_integer(unsigned(stalled_req_opcode)));
          writeline(logfile, line_out);
          write(line_out, string'("Source ID: "));
          write(line_out, to_integer(unsigned(stalled_req_srcid)));
          writeline(logfile, line_out);
          write(line_out, string'("Transaction ID: "));
          write(line_out, to_integer(unsigned(stalled_req_txnid)));
          writeline(logfile, line_out);
          write(line_out, string'("Address: "));
          write(line_out, stalled_req_addr(31 downto 0));
          writeline(logfile, line_out);
          write(line_out, string'("####################"));
          writeline(logfile, line_out);
        end if;

      -- Take next entry from MSHR
      elsif (bypass_mshr_valid(bypass_mshr_read_idx) = '1') then

        opcode := to_integer(signed(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1)));
        core_id := to_integer(signed(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1)));
        address := bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1);

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

        -- WriteCleanFull / WritebackPtl / WritebackFull
        if (opcode = 23 or opcode = 26 or opcode = 27) then
          send_response <= '1';
        else
          -- ??
        end if;

        -- Check that writecleanfull is done
        if (opcode = 23 and dirty_resp_triggered = '1') then
          wrcleanfull_done := '1';
        elsif ( (opcode = 26 or opcode = 27) and writebackptl_triggered = '1' and address = "00000000000010000000000001111110100100000000" and 
                writebackptl_done = '0') then -- 8100th cacheline (h8007e900)
                
          writebackptl_done := '1';
        end if;

        if (running = '1') then
          write(line_out, string'("--------- Handling request: ---------"));
          writeline(logfile, line_out);
          write(line_out, string'("Opcode: "));
          write(line_out, to_integer(unsigned(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Source ID: "));
          write(line_out, to_integer(unsigned(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Transaction ID: "));
          write(line_out, to_integer(unsigned(bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_TXNID_HI downto CHIE_REQ_FLIT_SRCID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Address: "));
          write(line_out, bypass_mshr(bypass_mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1));
          writeline(logfile, line_out);
          write(line_out, string'("####################"));
          writeline(logfile, line_out);
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

        -- Give L-credit to core which request was used
        if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= RNF_MSHR_ENTRY_SLOTS) then     -- 
          txreqlcrdv(core_id) <= '1';
          txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
        end if;

      elsif (mshr_vld(mshr_read_idx) = '1') then

        opcode := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1)));
        core_id := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1)));
        address := mshr(mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1);
        order := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_ORDER_HI downto CHIE_REQ_FLIT_ALLOWRETRY_HI+1)));

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

        -- ReadShared(1)/ReadClean(2)/ReadUnique(7)/CleanUnique(11)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55)/AtomicSwap(56)
        -- Note: CleanUnique is supposed to send COMP_UC(RSP), but it requires coherence control first
        if (opcode = 1 or opcode = 2 or opcode = 7 or opcode = 11 or opcode = 48 or opcode = 49 or opcode = 50 
            or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) then 
          if (do_separate_resp = '1' and (opcode = 7 or opcode = 2) and order = 0) then
            send_response <= '1';
          else 
            send_data <= '1';
          end if;

        elsif (opcode = 4) then -- ReadNoSnp(4)
          if (do_separate_resp = '1' or order /= 0) then
            send_response <= '1';
          else 
            send_uncached_data <= '1';
          end if;

        elsif (opcode = 28) then -- WriteNoSnp(28)
          send_response <= '1';
        else
          --
        end if;

        -- Check that the correct request is done in unit tests
        if (readunique_triggered = '1' and opcode = 7 and address = "00000000000010000000000001111110100100000100") then -- 8100th cacheline, the second word (h8007e904)
          readunique_done := '1';
        elsif (readshared_triggered = '1' and (opcode = 1 or opcode = 2) and address = "00000000000010000000000001111110100100000000") then -- 8100th cacheline, the first word (h8007e900)
          readshared_done := '1';
        end if;

        if (running = '1') then
          write(line_out, string'("--------- Handling request: ---------"));
          writeline(logfile, line_out);
          write(line_out, string'("Opcode: "));
          write(line_out, to_integer(unsigned(mshr(mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Source ID: "));
          write(line_out, to_integer(unsigned(mshr(mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Transaction ID: "));
          write(line_out, to_integer(unsigned(mshr(mshr_read_idx)(CHIE_REQ_FLIT_TXNID_HI downto CHIE_REQ_FLIT_SRCID_HI+1))));
          writeline(logfile, line_out);
          write(line_out, string'("Address: "));
          write(line_out, mshr(mshr_read_idx)(CHIE_REQ_FLIT_ADDR_HI downto CHIE_REQ_FLIT_SIZE_HI+1));
          writeline(logfile, line_out);
          write(line_out, string'("####################"));
          writeline(logfile, line_out);
        end if;

        -- Invalidate the entry when it's used
        mshr_vld(mshr_read_idx) := '0';
        mshr(mshr_read_idx) := (others => '0');

        -- Increase the MSHR read index
        if (mshr_read_idx = TB_MSHR_WIDTH-1) then
          mshr_read_idx := 0;
        else
          mshr_read_idx := mshr_read_idx+1;
        end if;

        -- Give L-credit to core which req was used
        if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= RNF_MSHR_ENTRY_SLOTS) then     -- 
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

    -- Take in bypassing write request in middle of previous request if it was just about to do snoops for a cacheline.
      -- There could have been issued a write req for the cacheline from the owner.
    procedure switch_req( variable value : out std_logic_vector(31 downto 0) ) is
      variable opcode : integer := 0;
      variable core_id : integer := 0;
      variable order : integer := 0;
    begin
      -- Store the stalled request to be issued afterwards
      stalled_req_valid               <= txreq_valid;
      stalled_req_qos                 <= txreq_qos;
      stalled_req_tgtid               <= txreq_tgtid;
      stalled_req_srcid               <= txreq_srcid;
      stalled_req_txnid               <= txreq_txnid;
      stalled_req_returnnid           <= txreq_returnnid;
      stalled_req_endian              <= txreq_endian;
      stalled_req_returntxnid         <= txreq_returntxnid;
      stalled_req_opcode              <= txreq_opcode;
      stalled_req_size                <= txreq_size;
      stalled_req_addr                <= txreq_addr;
      stalled_req_ns                  <= txreq_ns;
      stalled_req_likelyshared        <= txreq_likelyshared;
      stalled_req_allowretry          <= txreq_allowretry;
      stalled_req_order               <= txreq_order;
      stalled_req_pcrdtype            <= txreq_pcrdtype;
      stalled_req_memattr             <= txreq_memattr;
      stalled_req_snpattr             <= txreq_snpattr;
      stalled_req_lpid                <= txreq_lpid;
      stalled_req_excl_snoopme        <= txreq_excl_snoopme;
      stalled_req_expcompack          <= txreq_expcompack;
      stalled_req_tagop               <= txreq_tagop;
      stalled_req_tracetag            <= txreq_tracetag;
      
      stalled_rxdat_flitnum           <= data_flit_num;

      -- Switch to next req in the buffer when testing mixed rxdat response
      if (switch_to_next_req = '1') then

        if ( mshr_vld(mshr_read_idx) = '1') then
          opcode := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_OPCODE_HI downto CHIE_REQ_FLIT_RETURNTXNID_HI+1)));
          core_id := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_SRCID_HI downto CHIE_REQ_FLIT_TGTID_HI+1)));
          order := to_integer(signed(mshr(mshr_read_idx)(CHIE_REQ_FLIT_ORDER_HI downto CHIE_REQ_FLIT_ALLOWRETRY_HI+1)));

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

          -- reset the flit number for the picked request
          data_flit_num := (others => '0');

          -- ReadUnique(7)/ReadShared(1)/ReadClean(2)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55)/AtomicSwap(56)
          if (opcode = 7 or opcode = 1 or opcode = 2 or opcode = 48 or opcode = 49 or opcode = 50 
              or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) then 
            send_data <= '1';
          elsif (opcode = 4) then -- ReadNoSnp
            if (order /= 0) then
              send_response <= '1';
            else 
              send_uncached_data <= '1';
            end if;
          else
            --
          end if;

          -- Invalidate the MSHR entry when it's used
          mshr_vld(mshr_read_idx) := '0';
          mshr(mshr_read_idx) := (others => '0');

          -- Increase the read index
          if (mshr_read_idx = TB_MSHR_WIDTH-1) then
            mshr_read_idx := 0;
          else
            mshr_read_idx := mshr_read_idx+1;
          end if;

          -- Give L-credit to core which req was used
          if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= RNF_MSHR_ENTRY_SLOTS) then     -- 
            txreqlcrdv(core_id) <= '1';
            txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
          end if;
          
          switch_to_next_req <= '0';
          intermediate_resp <= '1';

        end if;

      -- Switch to next req in buffer when testing mixed rxdat response
      elsif (switch_back = '1') then

        opcode := to_integer(signed(stalled_req_opcode));
        core_id := to_integer(signed(stalled_req_srcid));
        order := to_integer(signed(stalled_req_order));

        txreq_valid <= stalled_req_valid;
        txreq_qos <= stalled_req_qos;
        txreq_tgtid <= stalled_req_tgtid;
        txreq_srcid <= stalled_req_srcid;
        txreq_txnid <= stalled_req_txnid;
        txreq_returnnid <= stalled_req_returnnid;
        txreq_endian <= stalled_req_endian;
        txreq_returntxnid <= stalled_req_returntxnid;
        txreq_opcode <= stalled_req_opcode;
        txreq_size <= stalled_req_size;
        txreq_addr <= stalled_req_addr;
        txreq_ns <= stalled_req_ns;
        txreq_likelyshared <= stalled_req_likelyshared;
        txreq_allowretry <= stalled_req_allowretry;
        txreq_order <= stalled_req_order;
        txreq_pcrdtype <= stalled_req_pcrdtype;
        txreq_memattr <= stalled_req_memattr;
        txreq_snpattr <= stalled_req_snpattr;
        txreq_lpid <= stalled_req_lpid;
        txreq_excl_snoopme <= stalled_req_excl_snoopme;
        txreq_expcompack <= stalled_req_expcompack;
        txreq_tagop <= stalled_req_tagop;
        txreq_tracetag <= stalled_req_tracetag;

        data_flit_num := stalled_rxdat_flitnum;

        -- ReadUnique(7)/ReadShared(1)/ReadClean(2)/AtomicLoad (ADD=48, CLR=49, EOR=50, SET=51, SMAX=52, SMIN=53, UMAX=54, UMIN=55)/AtomicSwap(56)
        if (opcode = 7 or opcode = 1 or opcode = 2 or opcode = 48 or opcode = 49 or opcode = 50 
            or opcode = 51 or opcode = 52 or opcode = 53 or opcode = 54 or opcode = 55 or opcode = 56) then 
          send_data <= '1';
        elsif (opcode = 4) then -- ReadNoSnp
          if (order /= 0) then
            send_response <= '1';
          else 
            send_uncached_data <= '1';
          end if;
        else
          --
        end if;

        
        switch_back <= '0';
        intermediate_resp <= '0';
        do_mixeddata_test := '0';
        dirtycleandata_test_done := '1';
        mixed_data_resp_done := '1';

      elsif (handle_writereq = '1') then
        -- Take in the received writereq
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

        -- WriteCleanFull / WriteBackPtl / WriteBackFull
        if (opcode = 23 or opcode = 26 or opcode = 27) then
          send_response <= '1';
        else
          -- ??
        end if;

        -- Invalidate the MSHR entry when it's used
        bypass_mshr_valid(bypass_mshr_read_idx) := '0';
        bypass_mshr(bypass_mshr_read_idx) := (others => '0');

        -- Increase the read index
        if (bypass_mshr_read_idx = TB_BYPASS_MSHR_WIDTH-1) then
          bypass_mshr_read_idx := 0;
        else
          bypass_mshr_read_idx := bypass_mshr_read_idx+1;
        end if;

        -- Give L-credit to core which request was used
        if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= RNF_MSHR_ENTRY_SLOTS) then     -- 
          txreqlcrdv(core_id) <= '1';
          txreq_crdt_counter_tmp(core_id) := std_logic_vector(to_unsigned(to_integer(signed(txreq_crdt_counter_tmp(core_id))) + 1, 32));
        end if;

        handle_writereq <= '0';
      end if;
      
    end procedure switch_req;

    -- Can be used for MSHR reordering if consecutive requests to same cacheline from same RNF
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


    -- AMO variables here to make them easier to get visible in simulation
      variable amo_old_data_chunk_addr : integer := 0;
      variable amo_old_data_chunk_size : integer := 0;
      variable amo_old_data : std_logic_vector(255 downto 0) := (others => '0');
      variable amo_old_data_int : integer := 0;
      variable amo_data_chunk : std_logic_vector(255 downto 0) := (others => '0');
      variable amo_data_int : integer := 0;
      variable amo_new_data : std_logic_vector(255 downto 0) := (others => '0');

      
    -- Execute the requested atomic operation
    procedure calculate_amo( variable value : out std_logic_vector(31 downto 0) ) is
      variable opcode : integer := 0;
      variable cacheline_addr : integer := 0;

    begin

      opcode := to_integer(signed(txreq_opcode));
      cacheline_addr := to_integer(unsigned(txreq_addr(mem_address_space_w-1 downto 6)));

      -- AMO initial data from the cacheline
      amo_old_data_chunk_addr := to_integer(unsigned(txreq_addr(5 downto 0)));
      amo_old_data_chunk_size := 2**(to_integer(unsigned(txreq_size))); -- the CHI sizes are defined as exponents of power of 2 for different sizes, e.g. size(32bytes)='d5

      amo_old_data(amo_old_data_chunk_size*8-1 downto 0) := tmp_LLCache(cacheline_addr)(amo_old_data_chunk_addr*8+amo_old_data_chunk_size*8-1 downto amo_old_data_chunk_addr*8);
      amo_old_data_int := to_integer(unsigned(amo_old_data));

      amo_data_chunk(amo_old_data_chunk_size*8-1 downto 0) := amo_data(amo_old_data_chunk_addr*8+amo_old_data_chunk_size*8-1 downto amo_old_data_chunk_addr*8);
      amo_data_int := to_integer(unsigned(amo_data_chunk));
      amo_new_data := (others => '0');

      if (amo_data_ready = '1') then

        if (opcode = 48) then -- CHIE_ATOMICLOAD_ADD
          amo_new_data := std_logic_vector(unsigned(amo_old_data) + unsigned(amo_data_chunk));
        elsif (opcode = 49) then -- CHIE_ATOMICLOAD_CLR (oldata AND (NOT txndata)
          amo_new_data := amo_old_data AND (NOT amo_data_chunk);
        elsif (opcode = 50) then -- CHIE_ATOMICLOAD_EOR (bitwise XOR)
          amo_new_data := amo_old_data XOR amo_data_chunk;
        elsif (opcode = 51) then -- CHIE_ATOMICLOAD_SET
          amo_new_data := amo_old_data OR amo_data_chunk;
        elsif (opcode = 52) then -- CHIE_ATOMICLOAD_SMAX
          if ((signed(amo_old_data) < signed(amo_data_chunk))) then
            amo_new_data := amo_data_chunk;
          else
            amo_new_data := amo_old_data;
          end if;
        elsif (opcode = 53) then -- CHIE_ATOMICLOAD_SMIN
          if ((signed(amo_old_data) > signed(amo_data_chunk))) then
            amo_new_data := amo_data_chunk;
          else
            amo_new_data := amo_old_data;
          end if;
        elsif (opcode = 54) then -- CHIE_ATOMICLOAD_UMAX
          if ((unsigned(amo_old_data) < unsigned(amo_data_chunk))) then
            amo_new_data := amo_data_chunk;
          else
            amo_new_data := amo_old_data;
          end if;
        elsif (opcode = 55) then -- CHIE_ATOMICLOAD_UMIN
          if ((unsigned(amo_old_data) > unsigned(amo_data_chunk))) then
            amo_new_data := amo_data_chunk;
          else
            amo_new_data := amo_old_data;
          end if;
        elsif (opcode = 56) then -- CHIE_ATOMICSWAP
          amo_new_data := amo_data_chunk;
        end if;

        tmp_LLCache(cacheline_addr)(amo_old_data_chunk_addr*8+amo_old_data_chunk_size*8-1 downto amo_old_data_chunk_addr*8) := amo_new_data(amo_old_data_chunk_size*8-1 downto 0);
        do_amo <= '0';
        amo_done <= '1';
      end if;
    end procedure calculate_amo;




    -- IO variables here to make them easier to get visible in simulation
    variable io_old_data_chunk_size : integer := 0;
    variable io_data_chunk : std_logic_vector(255 downto 0) := (others => '0');
    variable io_data_int : integer := 0;
    variable io_old_data_chunk_addr : integer := 0;      
    variable io_old_data : std_logic_vector(255 downto 0) := (others => '0');
    variable io_old_data_int : integer := 0;
    variable io_new_data : std_logic_vector(255 downto 0) := (others => '0');

    -- Simple IO writes and reads, the write address is always the same but all values are stored consecutively, read gives value of the last write
    procedure write_read_io( variable value : out std_logic_vector(31 downto 0) ) is
      variable opcode : integer := 0;
      variable cacheline_addr : integer := 0;
      variable io_data_int : integer := 0;
    begin
      -- 
      
      cacheline_addr := to_integer(unsigned(txreq_addr(io_address_space_w-1 downto 6)));
      io_old_data_chunk_addr := to_integer(unsigned(txreq_addr(5 downto 0)));
      io_old_data_chunk_size := 2**(to_integer(unsigned(txreq_size))); -- the CHI sizes are defined as exponents of power of 2 for different sizes, e.g. size(32bytes)='d5
      io_old_data(io_old_data_chunk_size*8-1 downto 0) := io_space(cacheline_addr)(io_old_data_chunk_addr*8+io_old_data_chunk_size*8-1 downto io_old_data_chunk_addr*8);
      io_old_data_int := to_integer(unsigned(io_old_data));
      io_data_chunk(io_old_data_chunk_size*8-1 downto 0) := io_data(io_old_data_chunk_addr*8+io_old_data_chunk_size*8-1 downto io_old_data_chunk_addr*8);
      io_data_int := to_integer(unsigned(io_data_chunk));
      io_new_data := (others => '0');

      write(io_line_out, string'("IO: "));
      write(io_line_out, io_data_int);
      writeline(io_file, io_line_out);

      if (write_io_data = '1') then
        
        io_new_data := io_data_chunk;
        io_space(cacheline_addr)(io_old_data_chunk_addr*8+io_old_data_chunk_size*8-1 downto io_old_data_chunk_addr*8) <= io_new_data(io_old_data_chunk_size*8-1 downto 0);

        -- For unit test
        if (writenosnp_triggered = '1') then 
          writenosnp_cnt := writenosnp_cnt + io_data_int;
          if (writenosnp_cnt = 45 and writenosnp_done = '0') then
            writenosnp_done := '1';
            tmp_LLCache(to_integer(unsigned(result_cacheline_addr(63 downto 6))))(31 downto 0) := std_logic_vector(to_unsigned(1, 32));
            tmp_LLCache(to_integer(unsigned(result_cacheline_addr(63 downto 6))))(63 downto 32) := std_logic_vector(to_unsigned(writenosnp_cnt, 32));
          end if;
        end if;
      end if;

      write_io_data <= '0';
      io_done <= '1';

    end procedure write_read_io;




    -- Testbench transaction state control
        -- Controls what to do next with handled transaction
    procedure transaction_control( variable value : out std_logic_vector(31 downto 0) ) is
      --
      variable opcode : integer := 0;
    begin
      value := (others => '0');
      opcode := to_integer(signed(txreq_opcode));
        
      if do_amo = '1' then
        calculate_amo(value);
      end if;

      if write_io_data = '1' then
        write_read_io(value);
      end if;

      if send_data = '1' then
        chi_rxdat_response(value);
      elsif send_uncached_data = '1' then
        chi_rxdat_nosnprsp(value);
      end if;

      if handle_writereq = '1' or switch_to_next_req = '1' or switch_back = '1' then
        switch_req(value);
      end if;

      if send_response = '1' then
        chi_rxrsp_response(value);
      end if;

      if send_snoop = '1' then
        chi_rxsnp_snoop(value);
      elsif snoop_sent = '1' and sent_snoop_count_var = 0 then
        
        if do_snoop_test = '1' then
          if correct_response = '1' then
            tmp_LLCache(to_integer(unsigned(result_cacheline_addr(63 downto 6))))(31 downto 0) := std_logic_vector(to_unsigned(1, 32));
          else 
            tmp_LLCache(to_integer(unsigned(result_cacheline_addr(63 downto 6))))(31 downto 0) := std_logic_vector(to_unsigned(404, 32));
          end if; 

          txreq_valid <= '0';
          do_snoop_test := '0';
          correct_response := '0';
          tmp_LLCache(to_integer(unsigned(finished_rnf_cnt_addr(63 downto 6))))((16*32)-1 downto (15*32)) := std_logic_vector(to_unsigned(0, 32));
        
        elsif (opcode = 11) then -- CleanUnique (Dataless)
          chi_rxrsp_response(value);
        else 
          send_data <= '1';
        end if;
        
        snoop_sent <= '0';
      end if;

      if (response_sent = '1' and copybackdata_received = '1') or (waiting_ack = '1' and compack_received = '1') or (amo_done = '1') or (io_done = '1') then
        response_sent <= '0';
        copybackdata_received <= '0';
        waiting_ack <= '0';
        compack_received <= '0';
        txreq_valid <= '0';
        amo_done <= '0';
        amo_data_ready <= '0';
        amo_data := (others => '0');
        amo_data_be := (others => '0');
        io_data := (others => '0');
        io_data_be := (others => '0');
        io_data_ready <= '0';
        io_done <= '0';
        rxdatflit <= (others => '0');
        rxrspflit <= (others => '0');
        rxsnpflit <= (others => '0');
      end if;
    
    end procedure transaction_control;




    variable i : integer;
    variable value : std_logic_vector(31 downto 0);
    file resultfile : text;
    variable result_int : integer;
    variable result_vec : std_logic_vector(31 downto 0);
    variable check_cacheline_addr : integer; -- 
    file mem_init              : text;
    variable good : boolean;
    variable imem_word : std_logic_vector(riscv_imemwidth-1 downto 0);
    variable imem_cacheline : std_logic_vector(511 downto 0);
    variable chunk : integer;

  -- TTA TB variables
    -- type imem_slv_array is array (natural range <>) of
    --   std_logic_vector (IMEMDATAWIDTH-1 downto 0);
    -- variable imem_r : imem_slv_array (0 to 2**IMEMADDRWIDTH-1);
    -- variable imem_word : std_logic_vector(IMEMDATAWIDTH-1 downto 0);

    -- constant imem_word_nextPO2 : integer := 2**bit_width(IMEMDATAWIDTH-1);
    -- constant imem_word_padding : std_logic_vector(imem_word_nextPO2-IMEMDATAWIDTH-1 downto 0)
    --                            := (others => '0');
    -- variable imem_word_padded : std_logic_vector(imem_word_nextPO2-1 downto 0);
    -- constant imem_data_count : integer := imem_word_nextPO2/16;
    -- variable imem_data : imem_arr(0 to imem_data_count - 1);
    
    -- variable dmem_word : std_logic_vector(32-1 downto 0);
    -- variable dmem_size : integer;
    -- variable cqmem_size : integer;
    -- variable dmem_start : integer;
    -- variable cqmem_start : integer;
    -- variable imem_start : integer;
    -- variable imem_size : integer;
    -- variable k : integer;
    -- file dmem_init : text;

    -- file dmem_dump_file      : text;

    -- variable seed1    : integer := 733035985;
    -- variable seed2    : integer := 787335972;
    -- variable rand     : real;
    -- variable val_in   : std_logic_vector(31 downto 0);

    variable completion_req_counter : integer := 0;
    variable completion_address : std_logic_vector(MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 0) 
                                    := ((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 7 => '0') & "1001000");
                                    --((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 14 => '0') & (13 downto 2 => '1') & "00");
                                    --((MSG_ADDR_HI-MSG_OPTIONS_2_HI-1 downto 1 => '0') & '1');

    variable decrement : std_logic := '1';
    variable zero : std_logic := '0';
    -- rxsnp test
    variable end_cnt : integer := 0;
    variable j : integer;
    variable k : integer;
    variable l : integer;


------------------------------------------------------------
------------------------------------------------------------
-- SIMULATION ----------------------------------------------
  begin
      file_open(logfile, log_path, write_mode);
      file_open(unit_file, unitresult_path, write_mode);
      file_open(io_file, io_path, write_mode);

      update_llc := (others => '0');
      snp_done <= '0';
      send_snoop <= '0';
      invalid_snp_rsp := (others => '0');
      amo_data_received := (others => '0');
      send_data <= '0';
      send_uncached_data <= '0';
      write_io_data <= '0';
      send_response <= '0';
      waiting_ack <= '0';
      response_sent <= '0';
      snoop_sent <= '0';
      amo_data_ready <= '0';
      do_amo <= '0';
      amo_done <= '0';
      compack_received <= '0';
      copybackdata_received <= '0';
      handle_writereq <= '0';
      switch_to_next_req <= '0';
      switch_back <= '0';
      intermediate_resp <= '0';
      data_flit_num := (others => '0');
      txreq_valid <= '0';
      stalled_req_valid <= '0';
      bootrom_req <= '0';
      bootrom_read_done <= '0';
      rxdat_crdt_count <= (others => (others => '0'));
      rxsnp_crdt_count <= (others => (others => '0'));
      rxrsp_crdt_count <= (others => (others => '0'));
      waiting_ack_count <= (others => (others => '0'));
      txrsp_crdt_counter <= (others => (others => '0'));
      txreq_crdt_counter <= (others => (others => '0'));
      txdat_crdt_counter <= (others => (others => '0'));

      bootrom_addr <= (others => '0');
      nreset <= '0';

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
      txreqlcrdv <= (others=>'0');
      txdatlcrdv <= (others=>'0');
      txrsplcrdv <= (others=>'0');

      txlinkactiveack <= (others=>'0'); 
      rxlinkactivereq <= (others=>'0'); 
      rxactive <= (others=>'0'); 

      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait until rising_edge(clk);

      nreset <= '1';

      
      -- wake_up_cnt in ariane_verilog_wrap set to 1024cycles
      -- After 515 cycles l15 should be initialized 
      for i in 0 to 1023 loop
        wait_cycle_update_counters(zero, zero, zero);
      end loop;

    -- Activate Link interfaces
    while true loop
      for core_id in 0 to rnf_count-1 loop
        if (txlinkactivereq(core_id) = '1') then
          txlinkactiveack(core_id) <= '1';
          rxlinkactivereq(core_id) <= '1';
          rxactive(core_id) <= '1';
        end if;

      end loop;

      -- RX link ready, TX should also be ready here -> Exit from the loop
      if ( rxlinkactivereq = (rxlinkactivereq'range =>'1') and rxlinkactiveack = (rxlinkactiveack'range =>'1') ) then
            exit;
      end if;

      wait_cycle_update_counters(zero, zero, zero);
    end loop;

  -- Zero Initialize the LLC
      for i in LLCache'range loop
        LLCache(i) <= (others => '0');
        cacheline_state(i) <= (others => '0');  -- invalid
        directory(i) <= (others => '0');  -- no sharers/owners
      end loop;

      tmp_LLCache := (others => (others => '0'));
      tmp_cacheline_state := (others => (others => '0'));
      tmp_directory := (others => (others => '0'));

    io_space <= (others => (others => '0'));

  -- Initialize the LLC with the memory image
      i := 0;
      -- 16x32bit=512bit cacheline
      chunk := 0;
      imem_cacheline := (others => '0');
      file_open(mem_init, imem_image, read_mode);
      while (not endfile(mem_init)) loop
          readline(mem_init, line_in);
          read(line_in, imem_word, good);
          assert good
          report "Read error in instruction memory initialization file"
          severity failure;

          imem_cacheline(32*(chunk+1)-1 downto 32*chunk) := imem_word;

          if (chunk = 15) then
            tmp_LLCache(i) := imem_cacheline;
            tmp_cacheline_state(i) := "01"; -- Valid
            i := i+1;  
            imem_cacheline := (others => '0');
            chunk := 0;
          else 
            chunk := chunk + 1;
          end if;

      end loop;
      -- Add the last image line to the cache
      tmp_LLCache(i) := imem_cacheline;
      tmp_cacheline_state(i) := "01"; -- Valid
      -- Close the memory image file
      file_close(mem_init);

      LLCache <= tmp_LLCache;
      cacheline_state <= tmp_cacheline_state;
      directory <= tmp_directory;

      update_addr <= (others => '0');


      check_cacheline_addr := to_integer(unsigned(result_cacheline_addr_2(63 downto 6)));
      if (do_rettosrc_snoop = '1') then
        tmp_LLCache(check_cacheline_addr)(4*32-1 downto 3*32) :=  std_logic_vector(to_unsigned(255, 32));
      end if;

      -- Send TX-L-credits
      for i in 0 to RNF_MSHR_ENTRY_SLOTS-1 loop  -- loop -RNF_MSHR_ENTRY_SLOTS- times so txreq/dat gets all the L-credits
        for core_id in 0 to rnf_count-1 loop
          if (to_integer(signed(txreq_crdt_counter_tmp(core_id))) /= RNF_MSHR_ENTRY_SLOTS) then
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
  

      value := (others=>'0');


------------------------------------------------------------
------------------------------------------------------------
-- MAIN LOOP -----------------------------------------------
      while value = X"00000000" loop

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
          --check_next_mshr_enrty(value);
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
        if update_llc /= (update_llc'range => '0') then
          update_LLC_txdat(value);
        end if;

        -- Check if all the cores have added to the the sync value and wait so that cores have ended executing, approximately 300 cycles
            -- "finished_rnf_cnt_addr" address can be used in programs to catch the program finish
        if (to_integer(unsigned(tmp_LLCache(to_integer(unsigned(finished_rnf_cnt_addr(63 downto 6))))(31 downto 0))) = rnf_count) then
          if (end_cnt = 300) then
  -- PROGRAM COMPLETED
            report "Cores done!";
            write(line_out, string'("############ Cores done ############"));
            writeline(logfile, line_out);
            exit;
          elsif (end_cnt = 1) then
            end_cnt := end_cnt + 1;
            report "Handled transactions written to run.log";
            write(line_out, string'("############ Program completed ############"));
            writeline(logfile, line_out);
            running := '0';
            prog_end := '1';
          else 
            end_cnt := end_cnt + 1;
          end if;
        end if;


        -- With unit and corner tests, the address checked in this condition is used to check when the actual program has begun
        if ((unit_test = '1' or corner_test = '1') and to_integer(unsigned(tmp_LLCache(to_integer(unsigned(start_rnf_cnt_addr(63 downto 6))))(63 downto 32))) = rnf_count 
            and running = '0' and prog_end = '0') then
            write(line_out, string'("############ Program start ############"));
            writeline(logfile, line_out);
            running := '1';
        end if;

        if ((unit_test = '1' or corner_test = '1') and to_integer(unsigned(tmp_LLCache(to_integer(unsigned(finished_rnf_cnt_addr(63 downto 6))))((16*32)-1 downto (15*32)))) = 1 ) then

          -- Check if dummy request is triggered for snoop test
          if ((do_shared_snoop = '1' or do_unique_snoop = '1' or do_clean_snoop = '1' or do_cleaninvalid_snoop = '1' 
              or do_rettosrc_snoop = '1' or do_makeinvalid_snoop = '1') and do_snoop_test = '0') then
            write(line_out, string'("############ SNOOP TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            do_snoop_test := '1';
          elsif (send_unique_dirty_cline = '1' and dirty_resp_triggered = '0') then
            write(line_out, string'("############ WRITECLEANFULL/COMPDATA_UD_PD TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            dirty_resp_triggered := '1';
          elsif (do_readunique_test = '1' and readunique_triggered = '0') then
            write(line_out, string'("############ READUNIQUE TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            readunique_triggered := '1';
          elsif (do_readshared_test = '1' and readshared_triggered = '0') then
            write(line_out, string'("############ READSHARED TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            readshared_triggered := '1';
          elsif (do_writebackptl_test = '1' and writebackptl_triggered = '0') then
            write(line_out, string'("############ WRITEBACKPTL TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            writebackptl_triggered := '1';
          elsif (do_writenosnp_test = '1' and writenosnp_triggered = '0') then
            write(line_out, string'("############ WRITENOSNP TEST TRIGGERED ############"));
            writeline(logfile, line_out);
            writenosnp_triggered := '1';
          elsif (do_mixeddata_test = '1' and mixed_resp_triggered = '0') then
            write(line_out, string'("############ MIXED DATA RESPONSE TRIGGERED ############"));
            writeline(logfile, line_out);
            mixed_resp_triggered := '1';
          elsif (do_reverseresponse_test = '1' and reverse_resp_triggered = '0') then
            write(line_out, string'("############ REVERSED DATA RESPONSE TRIGGERED ############"));
            writeline(logfile, line_out);
            reverse_resp_triggered := '1';
          end if;

        elsif ((unit_test = '1' or corner_test = '1') and to_integer(unsigned(tmp_LLCache(to_integer(unsigned(finished_rnf_cnt_addr(63 downto 6))))((16*32)-1 downto (15*32)))) = 0 ) then

          if (do_reverseresponse_test = '1' and reverse_resp_triggered = '1') then
            write(line_out, string'("############ REVERSED DATA RESPONSES STOPPED ############"));
            writeline(logfile, line_out);
            reverse_resp_triggered := '0';
          end if;

        end if;

      end loop;

      clk_ena  <= '0';

      -- Write out the results
      file_open(resultfile, resfile_path, write_mode);

      -- "result_cacheline_addr", address for program result prints (result_file.log)
      check_cacheline_addr := to_integer(unsigned(result_cacheline_addr(63 downto 6))); -- NOTE: there is taken only address for getting one 512bit cacheline
      j := 0; -- word idx
      k := 64; -- intended results count 
      l := 0; -- cacheline idx
      while (j < k) loop


          result_int := to_integer(unsigned(tmp_LLCache(check_cacheline_addr)((j+1)*32-1 downto (j)*32)));
          result_vec := tmp_LLCache(check_cacheline_addr)((j+1)*32-1 downto (j)*32);
          write(line_out, "Data at address " & integer'image(j+16*l) & ": " & integer'image(result_int));
          writeline(resultfile, line_out);
          write(line_out, "Data vector at address " & integer'image(j+16*l) & ": ");
          write(line_out, result_vec);
          writeline(resultfile, line_out);

          write(line_out, string'("############################## "));
          writeline(resultfile, line_out);
          
          if ((unit_test = '1' or corner_test = '1') and j = 0 and l = 0 and result_int = 1) then
            if ((dirty_resp_triggered = '1' and wrcleanfull_done = '1') or (readunique_triggered = '1' and readunique_done = '1') or 
                (readshared_triggered = '1' and readshared_done = '1') or (writebackptl_triggered = '1' and writebackptl_done = '1') or 
                (writenosnp_triggered = '1' and writenosnp_done = '1') or do_amoadd_swap_test = '1' or do_atomicload_test = '1' or 
                do_unique_snoop = '1' or do_shared_snoop = '1' or do_clean_snoop = '1' or do_cleaninvalid_snoop = '1' or
                do_makeinvalid_snoop = '1' or do_rettosrc_snoop = '1' or
                dirtycleandata_test_done = '1' or do_reverseresponse_test = '1' or do_coherencystress_test = '1') then
              write(line_out, string'("######################## Program finished successfully ########################"));
              writeline(logfile, line_out);

              write(unit_line_out, integer'image(1));
              writeline(unit_file, unit_line_out);

            else 

              write(unit_line_out, integer'image(0));
              writeline(unit_file, unit_line_out);

            end if;

          end if;

          if (j = 15) then
            check_cacheline_addr := check_cacheline_addr+1;
            j := 0;
            k := k-16;
            l := l+1;
          else 
            j := j+1;
          end if;
      end loop;


      write(line_out, string'("Output written to result_file.log"));
      writeline(logfile, line_out);
      file_close(logfile);
      file_close(resultfile);

      assert false report "Simulation finished!" severity failure;

  end process;

end testbench;


