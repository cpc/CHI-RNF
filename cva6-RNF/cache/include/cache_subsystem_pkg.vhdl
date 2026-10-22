library IEEE;
use IEEE.std_logic_1164.all;

package cache_subsystem_pkg is
  --constant fu_lsu_addrw_g : integer := 16;
  -- Additional params for making tta more generic
  constant TTA_DATA_WIDTH : integer := 32;


  -- From ariane_pkg
  constant DCACHE_LINE_WIDTH : integer := 128;
  constant DCACHE_SET_ASSOC : integer := 4;
  constant DCACHE_INDEX_WIDTH : integer := 11;          --$clog2(`CONFIG_L1D_SIZE / DCACHE_SET_ASSOC);   // clog2(8192/4) = 11 ?
  constant DCACHE_TAG_WIDTH : integer := 45;            --riscv::PLEN - DCACHE_INDEX_WIDTH;      // 56-11 = 45 (?)
  constant DCACHE_USER_LINE_WIDTH : integer := 128;     --(AXI_USER_WIDTH == 1) ? 4 : 128; // in bit       // 128?
  constant DCACHE_USER_WIDTH : integer := 1;            -- = DATA_USER_WIDTH;       // 1?


  -- From riscv_pkg
  constant XLEN : integer := 64;         --cva6_config_pkg::CVA6ConfigXlen;

  -- define.tmp.h
  constant NOC_DATA_WIDTH : integer := 64; 
  -- NoC1 request header field indexes
  -- request header flit1
  constant MSG_DST_CHIPID_HI : integer := 63;
  constant MSG_DST_X_HI : integer := 49;
  constant MSG_DST_Y_HI : integer := 41;
  constant MSG_DST_FBITS_HI : integer := 33;
  constant MSG_LENGTH_HI : integer := 29;
  constant MSG_TYPE_HI : integer := 21;
  constant MSG_MSHRID_HI : integer := 13;
  constant MSG_OPTIONS_1_HI : integer := 5;
  -- request header flit2
  constant MSG_ADDR_HI : integer := 63;
  constant MSG_CACHE_TYPE_HI : integer := 11; -- this was misleading in noc1encoder, included in options2 field
  constant MSG_OPTIONS_2_HI : integer := 15; 
  -- request header flit3
  constant MSG_SRC_CHIPID_HI : integer := 63;
  constant MSG_SRC_X_HI : integer := 49;
  constant MSG_SRC_Y_HI : integer := 41;
  constant MSG_SRC_FBITS_HI : integer := 33; 
  constant MSG_OPTIONS_3_HI : integer := 29;
  -- NoC2 response header field indexes
  -- header flit1 (same fields as in noc1 header flit1, except options is opt4, but still the same width)
  constant MSG_OPTIONS_4_HI : integer := 5;


  -----CHI values-----


-- `define HNF_PARAM #( \
--      parameter CHIE_REQ_ADDR_WIDTH_PARAM    = 44,    \
--      parameter CHIE_SNP_ADDR_WIDTH_PARAM    = 41,    \
--      parameter CHIE_NID_WIDTH_PARAM         = 7,     \
--      parameter CHIE_DATA_WIDTH_PARAM        = 256,   \
--      parameter CHIE_BE_WIDTH_PARAM          = 32,    \
--      parameter CHIE_DATACHECK_WIDTH_PARAM   = 32,    \
--      parameter CHIE_POISON_WIDTH_PARAM      = 4,     \
--      parameter CHIE_REQ_RSVDC_WIDTH_PARAM   = 0,     \
--      parameter CHIE_DAT_RSVDC_WIDTH_PARAM   = 0,     \
--      parameter HNF_MSHR_RNF_NUM_PARAM       = 4,     \
--      parameter HNF_MSHR_RNI_NUM_PARAM       = 0,     \
--      parameter RNF_NID_LIST_PARAM           = {7'd48,7'd16,7'd40,7'd8}, \
--      parameter RNI_NID_LIST_PARAM           = {7'd1}, \
--      parameter HNF_NID_PARAM                = 0,     \
--      parameter SNF_NID_PARAM                = 32,     \
--      parameter XP_LCRD_NUM_PARAM            = 15,    \
--      parameter HNF_SF_ENTRIES_NUM_PARAM     = 131072,\
--      parameter HNF_SF_WAY_NUM_PARAM         = 16,    \
--      parameter HNF_MSHR_EXCL_RN_NUM_PARAM   = 32,    \
--      parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5,     \
--      parameter HNF_MSHR_ENTRIES_NUM_PARAM   = 32,    \
--      parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5,     \
--      parameter HNF_L3_CACHE_SIZE_PARAM      = 4096,  \
--      parameter HNF_L3_WAY_NUM_PARAM         = 16     )


  -- CHI PARAMETERS
    -- values are mostly according to chie_defines.v and RNF_PARAM(rnf_param.v)

  constant CHIE_REQ_ADDR_WIDTH_PARAM      : integer := 44;
  constant CHIE_SNP_ADDR_WIDTH_PARAM      : integer := 41;
  constant CHIE_NID_WIDTH_PARAM           : integer := 7;
  constant CHIE_DATA_WIDTH_PARAM          : integer := 256;
  constant CHIE_BE_WIDTH_PARAM            : integer := CHIE_DATA_WIDTH_PARAM/8;
  constant CHIE_DATACHECK_WIDTH_PARAM     : integer := 0;
  constant CHIE_POISON_WIDTH_PARAM        : integer := 0;
  constant CHIE_REQ_RSVDC_WIDTH_PARAM     : integer := 0;
  constant CHIE_DAT_RSVDC_WIDTH_PARAM     : integer := 0;
  constant HNF_MSHR_RNF_NUM_PARAM         : integer := 2;
  constant HNF_MSHR_RNI_NUM_PARAM         : integer := 0;
  constant HNF_NID_PARAM                  : integer := 2;
  constant SNF_NID_PARAM                  : integer := 32;
  constant XP_LCRD_NUM_PARAM              : integer := 15;
  constant HNF_SF_ENTRIES_NUM_PARAM       : integer := 131072;
  constant HNF_SF_WAY_NUM_PARAM           : integer := 16;
  constant HNF_MSHR_EXCL_RN_NUM_PARAM     : integer := 32;
  constant HNF_MSHR_EXCL_RN_WIDTH_PARAM   : integer := 5;
  constant HNF_MSHR_ENTRIES_NUM_PARAM     : integer := 32;
  constant HNF_MSHR_ENTRIES_WIDTH_PARAM   : integer := 5;
  constant HNF_L3_CACHE_SIZE_PARAM        : integer := 4096;
  constant HNF_L3_WAY_NUM_PARAM           : integer := 16;
  constant CACHED_REGION_BASE             : std_logic_vector  := X"00000000_80000000";
  constant CACHED_REGION_SIZE             : std_logic_vector  := X"00000000_00080000";
  constant BOOT_REGION_BASE               : std_logic_vector  := X"000000FF_F1010000";
  constant BOOT_REGION_SIZE               : std_logic_vector  := X"00000000_00010000";
  constant IO_REGION_BASE                 : std_logic_vector  := X"000000FF_F0c2c000";
  constant IO_REGION_SIZE                 : std_logic_vector  := X"00000000_003E4000";




  -- IO widths
  
  --constant CHIE_RSP_FLIT_WIDTH : integer := 7*2+51;
  --constant CHIE_DAT_FLIT_WIDTH : integer := 7*3+4+32+256+32+256/32+256/128+0+51;
  --constant CHIE_REQ_FLIT_WIDTH : integer := 44+7*3+0+66;
  --constant CHIE_SNP_FLIT_WIDTH : integer := 41+7*2+37;


  -- REQ CHANNEL FIELD WIDTHS
  constant CHIE_REQ_FLIT_TXNID_WIDTH : integer := 12;     
  constant CHIE_REQ_FLIT_OPCODE_WIDTH : integer := 7;      
  constant CHIE_REQ_FLIT_SIZE_WIDTH : integer := 3;         
  constant CHIE_REQ_FLIT_ADDR_WIDTH : integer := 44;        
  constant CHIE_REQ_FLIT_DODWT_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_TGTID_WIDTH : integer := 7;
  constant CHIE_REQ_FLIT_SRCID_WIDTH : integer := 7;
  constant CHIE_REQ_FLIT_LIKELYSHARED_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_QOS_WIDTH : integer := 4;
  constant CHIE_REQ_FLIT_RETURNNID_WIDTH : integer := 7;
  constant CHIE_REQ_FLIT_RETURNTXNID_WIDTH : integer := 12;
  constant CHIE_REQ_FLIT_NS_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_ALLOWRETRY_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_ORDER_WIDTH : integer := 2;
  constant CHIE_REQ_FLIT_PCRDTYPE_WIDTH : integer := 4;
  constant CHIE_REQ_FLIT_MEMATTR_WIDTH : integer := 4;
  constant CHIE_REQ_FLIT_TRACETAG_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_ENDIAN_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_LPID_WIDTH : integer := 8;     -- 
  constant CHIE_REQ_FLIT_EXCL_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_EXPCOMPACK_WIDTH : integer := 1;
  constant CHIE_REQ_FLIT_TAGOP_WIDTH : integer := 2;

  constant CHIE_REQ_FLIT_WIDTH : integer := CHIE_REQ_FLIT_TXNID_WIDTH
                                            +CHIE_REQ_FLIT_OPCODE_WIDTH
                                            +CHIE_REQ_FLIT_SIZE_WIDTH
                                            +CHIE_REQ_FLIT_ADDR_WIDTH
                                            +CHIE_REQ_FLIT_DODWT_WIDTH
                                            +CHIE_REQ_FLIT_TGTID_WIDTH
                                            +CHIE_REQ_FLIT_SRCID_WIDTH
                                            +CHIE_REQ_FLIT_LIKELYSHARED_WIDTH
                                            +CHIE_REQ_FLIT_QOS_WIDTH
                                            +CHIE_REQ_FLIT_RETURNNID_WIDTH
                                            +CHIE_REQ_FLIT_RETURNTXNID_WIDTH
                                            +CHIE_REQ_FLIT_NS_WIDTH
                                            +CHIE_REQ_FLIT_ALLOWRETRY_WIDTH
                                            +CHIE_REQ_FLIT_ORDER_WIDTH
                                            +CHIE_REQ_FLIT_PCRDTYPE_WIDTH
                                            +CHIE_REQ_FLIT_MEMATTR_WIDTH
                                            +CHIE_REQ_FLIT_TRACETAG_WIDTH
                                            +CHIE_REQ_FLIT_ENDIAN_WIDTH
                                            +CHIE_REQ_FLIT_LPID_WIDTH
                                            +CHIE_REQ_FLIT_EXCL_WIDTH
                                            +CHIE_REQ_FLIT_EXPCOMPACK_WIDTH
                                            +CHIE_REQ_FLIT_TAGOP_WIDTH;

  constant CHIE_REQ_FLIT_QOS_HI : integer := CHIE_REQ_FLIT_QOS_WIDTH-1;
  constant CHIE_REQ_FLIT_TGTID_HI : integer := CHIE_REQ_FLIT_QOS_HI + CHIE_REQ_FLIT_TGTID_WIDTH;
  constant CHIE_REQ_FLIT_SRCID_HI : integer := CHIE_REQ_FLIT_TGTID_HI + CHIE_REQ_FLIT_SRCID_WIDTH;
  constant CHIE_REQ_FLIT_TXNID_HI : integer := CHIE_REQ_FLIT_SRCID_HI + CHIE_REQ_FLIT_TXNID_WIDTH;
  constant CHIE_REQ_FLIT_RETURNNID_HI : integer := CHIE_REQ_FLIT_TXNID_HI + CHIE_REQ_FLIT_RETURNNID_WIDTH;
  constant CHIE_REQ_FLIT_ENDIAN_HI : integer := CHIE_REQ_FLIT_RETURNNID_HI + CHIE_REQ_FLIT_ENDIAN_WIDTH;
  constant CHIE_REQ_FLIT_RETURNTXNID_HI : integer := CHIE_REQ_FLIT_ENDIAN_HI + CHIE_REQ_FLIT_RETURNTXNID_WIDTH;     
  constant CHIE_REQ_FLIT_OPCODE_HI : integer := CHIE_REQ_FLIT_RETURNTXNID_HI + CHIE_REQ_FLIT_OPCODE_WIDTH;      
  constant CHIE_REQ_FLIT_SIZE_HI : integer := CHIE_REQ_FLIT_OPCODE_HI + CHIE_REQ_FLIT_SIZE_WIDTH;         
  constant CHIE_REQ_FLIT_ADDR_HI : integer := CHIE_REQ_FLIT_SIZE_HI + CHIE_REQ_FLIT_ADDR_WIDTH;
  constant CHIE_REQ_FLIT_NS_HI : integer := CHIE_REQ_FLIT_ADDR_HI + CHIE_REQ_FLIT_NS_WIDTH; 
  constant CHIE_REQ_FLIT_LIKELYSHARED_HI : integer := CHIE_REQ_FLIT_NS_HI + CHIE_REQ_FLIT_LIKELYSHARED_WIDTH;
  constant CHIE_REQ_FLIT_ALLOWRETRY_HI : integer := CHIE_REQ_FLIT_LIKELYSHARED_HI + CHIE_REQ_FLIT_ALLOWRETRY_WIDTH; 
  constant CHIE_REQ_FLIT_ORDER_HI : integer := CHIE_REQ_FLIT_ALLOWRETRY_HI + CHIE_REQ_FLIT_ORDER_WIDTH;
  constant CHIE_REQ_FLIT_PCRDTYPE_HI : integer := CHIE_REQ_FLIT_ORDER_HI + CHIE_REQ_FLIT_PCRDTYPE_WIDTH;
  constant CHIE_REQ_FLIT_MEMATTR_HI : integer := CHIE_REQ_FLIT_PCRDTYPE_HI + CHIE_REQ_FLIT_MEMATTR_WIDTH;      
  constant CHIE_REQ_FLIT_DODWT_HI : integer := CHIE_REQ_FLIT_MEMATTR_HI + CHIE_REQ_FLIT_DODWT_WIDTH;   -- & snpattr
  constant CHIE_REQ_FLIT_LPID_HI : integer := CHIE_REQ_FLIT_DODWT_HI + CHIE_REQ_FLIT_LPID_WIDTH;
  constant CHIE_REQ_FLIT_EXCL_HI : integer := CHIE_REQ_FLIT_LPID_HI + CHIE_REQ_FLIT_EXCL_WIDTH;
  constant CHIE_REQ_FLIT_EXPCOMPACK_HI : integer := CHIE_REQ_FLIT_EXCL_HI + CHIE_REQ_FLIT_EXPCOMPACK_WIDTH;
  constant CHIE_REQ_FLIT_TAGOP_HI : integer := CHIE_REQ_FLIT_EXPCOMPACK_HI + CHIE_REQ_FLIT_TAGOP_WIDTH;
  constant CHIE_REQ_FLIT_TRACETAG_HI : integer := CHIE_REQ_FLIT_TAGOP_HI + CHIE_REQ_FLIT_TRACETAG_WIDTH;

    -- DAT CHANNEL FIELD WIDTHS
  constant CHIE_DAT_FLIT_QOS_WIDTH : integer := 4;
  constant CHIE_DAT_FLIT_TGTID_WIDTH : integer := 7;
  constant CHIE_DAT_FLIT_SRCID_WIDTH : integer := 7;
  constant CHIE_DAT_FLIT_TXNID_WIDTH : integer := 12;     
  constant CHIE_DAT_FLIT_HOMENID_WIDTH : integer := 7;
  constant CHIE_DAT_FLIT_OPCODE_WIDTH : integer := 4;
  constant CHIE_DAT_FLIT_RESPERR_WIDTH : integer := 2;
  constant CHIE_DAT_FLIT_RESP_WIDTH : integer := 3;   
  constant CHIE_DAT_FLIT_FWDSTATE_WIDTH : integer := 4;   
  constant CHIE_DAT_FLIT_CBUSY_WIDTH : integer := 3;
  constant CHIE_DAT_FLIT_DBID_WIDTH : integer := 12;
  constant CHIE_DAT_FLIT_CCID_WIDTH : integer := 2;
  constant CHIE_DAT_FLIT_DATAID_WIDTH : integer := 2;
  constant CHIE_DAT_FLIT_TAGOP_WIDTH : integer := 2;
  constant CHIE_DAT_FLIT_TRACETAG_WIDTH : integer := 1;
  constant CHIE_DAT_FLIT_BE_WIDTH : integer := CHIE_BE_WIDTH_PARAM; --32;
  constant CHIE_DAT_FLIT_DATA_WIDTH : integer := CHIE_DATA_WIDTH_PARAM; --256;
  constant CHIE_DAT_FLIT_TAG_WIDTH : integer := CHIE_DAT_FLIT_DATA_WIDTH/32;
  constant CHIE_DAT_FLIT_TU_WIDTH : integer := CHIE_DAT_FLIT_DATA_WIDTH/128;

constant CHIE_DAT_FLIT_WIDTH : integer := CHIE_DAT_FLIT_QOS_WIDTH
                                          +CHIE_DAT_FLIT_TGTID_WIDTH
                                          +CHIE_DAT_FLIT_SRCID_WIDTH
                                          +CHIE_DAT_FLIT_TXNID_WIDTH
                                          +CHIE_DAT_FLIT_HOMENID_WIDTH
                                          +CHIE_DAT_FLIT_OPCODE_WIDTH
                                          +CHIE_DAT_FLIT_RESPERR_WIDTH
                                          +CHIE_DAT_FLIT_RESP_WIDTH
                                          +CHIE_DAT_FLIT_FWDSTATE_WIDTH
                                          +CHIE_DAT_FLIT_CBUSY_WIDTH
                                          +CHIE_DAT_FLIT_DBID_WIDTH
                                          +CHIE_DAT_FLIT_CCID_WIDTH
                                          +CHIE_DAT_FLIT_DATAID_WIDTH
                                          +CHIE_DAT_FLIT_TAGOP_WIDTH
                                          +CHIE_DAT_FLIT_TRACETAG_WIDTH
                                          +CHIE_DAT_FLIT_BE_WIDTH
                                          +CHIE_DAT_FLIT_DATA_WIDTH
                                          +CHIE_DAT_FLIT_TAG_WIDTH
                                          +CHIE_DAT_FLIT_TU_WIDTH;

  constant CHIE_DAT_FLIT_QOS_HI : integer := CHIE_DAT_FLIT_QOS_WIDTH-1;
  constant CHIE_DAT_FLIT_TGTID_HI : integer := CHIE_DAT_FLIT_QOS_HI + CHIE_DAT_FLIT_TGTID_WIDTH;
  constant CHIE_DAT_FLIT_SRCID_HI : integer := CHIE_DAT_FLIT_TGTID_HI + CHIE_DAT_FLIT_SRCID_WIDTH;
  constant CHIE_DAT_FLIT_TXNID_HI : integer := CHIE_DAT_FLIT_SRCID_HI + CHIE_DAT_FLIT_TXNID_WIDTH;
  constant CHIE_DAT_FLIT_HOMENID_HI : integer := CHIE_DAT_FLIT_TXNID_HI + CHIE_DAT_FLIT_HOMENID_WIDTH;
  constant CHIE_DAT_FLIT_OPCODE_HI : integer := CHIE_DAT_FLIT_HOMENID_HI + CHIE_DAT_FLIT_OPCODE_WIDTH;
  constant CHIE_DAT_FLIT_RESPERR_HI : integer := CHIE_DAT_FLIT_OPCODE_HI + CHIE_DAT_FLIT_RESPERR_WIDTH;
  constant CHIE_DAT_FLIT_RESP_HI : integer := CHIE_DAT_FLIT_RESPERR_HI + CHIE_DAT_FLIT_RESP_WIDTH;   
  constant CHIE_DAT_FLIT_FWDSTATE_HI : integer := CHIE_DAT_FLIT_RESP_HI + CHIE_DAT_FLIT_FWDSTATE_WIDTH;   
  constant CHIE_DAT_FLIT_CBUSY_HI : integer := CHIE_DAT_FLIT_FWDSTATE_HI + CHIE_DAT_FLIT_CBUSY_WIDTH;
  constant CHIE_DAT_FLIT_DBID_HI : integer := CHIE_DAT_FLIT_CBUSY_HI + CHIE_DAT_FLIT_DBID_WIDTH;
  constant CHIE_DAT_FLIT_CCID_HI : integer := CHIE_DAT_FLIT_DBID_HI + CHIE_DAT_FLIT_CCID_WIDTH;
  constant CHIE_DAT_FLIT_DATAID_HI : integer := CHIE_DAT_FLIT_CCID_HI + CHIE_DAT_FLIT_DATAID_WIDTH;
  constant CHIE_DAT_FLIT_TAGOP_HI : integer := CHIE_DAT_FLIT_DATAID_HI + CHIE_DAT_FLIT_TAGOP_WIDTH;
  constant CHIE_DAT_FLIT_TAG_HI : integer := CHIE_DAT_FLIT_TAGOP_HI + CHIE_DAT_FLIT_TAG_WIDTH;
  constant CHIE_DAT_FLIT_TU_HI : integer := CHIE_DAT_FLIT_TAG_HI + CHIE_DAT_FLIT_TU_WIDTH;
  constant CHIE_DAT_FLIT_TRACETAG_HI : integer := CHIE_DAT_FLIT_TU_HI + CHIE_DAT_FLIT_TRACETAG_WIDTH;
  constant CHIE_DAT_FLIT_BE_HI : integer := CHIE_DAT_FLIT_TRACETAG_HI + CHIE_DAT_FLIT_BE_WIDTH;
  constant CHIE_DAT_FLIT_DATA_HI : integer := CHIE_DAT_FLIT_BE_HI + CHIE_DAT_FLIT_DATA_WIDTH;

    -- RSP CHANNEL FIELD WIDTHS
  constant CHIE_RSP_FLIT_QOS_WIDTH : integer := 4;
  constant CHIE_RSP_FLIT_TGTID_WIDTH : integer := 7;
  constant CHIE_RSP_FLIT_SRCID_WIDTH : integer := 7;
  constant CHIE_RSP_FLIT_TXNID_WIDTH : integer := 12;     
  constant CHIE_RSP_FLIT_OPCODE_WIDTH : integer := 5;
  constant CHIE_RSP_FLIT_RESPERR_WIDTH : integer := 2;
  constant CHIE_RSP_FLIT_RESP_WIDTH : integer := 3; 
  constant CHIE_RSP_FLIT_FWDSTATE_WIDTH : integer := 3;   
  constant CHIE_RSP_FLIT_CBUSY_WIDTH : integer := 3;
  constant CHIE_RSP_FLIT_DBID_WIDTH : integer := 12;
  constant CHIE_RSP_FLIT_PCRDTYPE_WIDTH : integer := 4;
  constant CHIE_RSP_FLIT_TAGOP_WIDTH : integer := 2;
  constant CHIE_RSP_FLIT_TRACETAG_WIDTH : integer := 1;

  constant CHIE_RSP_FLIT_WIDTH : integer := CHIE_RSP_FLIT_QOS_WIDTH
                                            +CHIE_RSP_FLIT_TGTID_WIDTH
                                            +CHIE_RSP_FLIT_SRCID_WIDTH
                                            +CHIE_RSP_FLIT_TXNID_WIDTH
                                            +CHIE_RSP_FLIT_OPCODE_WIDTH
                                            +CHIE_RSP_FLIT_RESPERR_WIDTH
                                            +CHIE_RSP_FLIT_RESP_WIDTH
                                            +CHIE_RSP_FLIT_FWDSTATE_WIDTH
                                            +CHIE_RSP_FLIT_CBUSY_WIDTH
                                            +CHIE_RSP_FLIT_DBID_WIDTH
                                            +CHIE_RSP_FLIT_PCRDTYPE_WIDTH
                                            +CHIE_RSP_FLIT_TAGOP_WIDTH
                                            +CHIE_RSP_FLIT_TRACETAG_WIDTH;

  constant CHIE_RSP_FLIT_QOS_HI : integer := CHIE_RSP_FLIT_QOS_WIDTH-1;
  constant CHIE_RSP_FLIT_TGTID_HI : integer := CHIE_RSP_FLIT_QOS_HI + CHIE_RSP_FLIT_TGTID_WIDTH;
  constant CHIE_RSP_FLIT_SRCID_HI : integer := CHIE_RSP_FLIT_TGTID_HI + CHIE_RSP_FLIT_SRCID_WIDTH;
  constant CHIE_RSP_FLIT_TXNID_HI : integer := CHIE_RSP_FLIT_SRCID_HI + CHIE_RSP_FLIT_TXNID_WIDTH;     
  constant CHIE_RSP_FLIT_OPCODE_HI : integer := CHIE_RSP_FLIT_TXNID_HI + CHIE_RSP_FLIT_OPCODE_WIDTH;
  constant CHIE_RSP_FLIT_RESPERR_HI : integer := CHIE_RSP_FLIT_OPCODE_HI + CHIE_RSP_FLIT_RESPERR_WIDTH;
  constant CHIE_RSP_FLIT_RESP_HI : integer := CHIE_RSP_FLIT_RESPERR_HI + CHIE_RSP_FLIT_RESP_WIDTH; 
  constant CHIE_RSP_FLIT_FWDSTATE_HI : integer := CHIE_RSP_FLIT_RESP_HI + CHIE_RSP_FLIT_FWDSTATE_WIDTH;   
  constant CHIE_RSP_FLIT_CBUSY_HI : integer := CHIE_RSP_FLIT_FWDSTATE_HI + CHIE_RSP_FLIT_CBUSY_WIDTH;
  constant CHIE_RSP_FLIT_DBID_HI : integer := CHIE_RSP_FLIT_CBUSY_HI + CHIE_RSP_FLIT_DBID_WIDTH;
  constant CHIE_RSP_FLIT_PCRDTYPE_HI : integer := CHIE_RSP_FLIT_DBID_HI + CHIE_RSP_FLIT_PCRDTYPE_WIDTH;
  constant CHIE_RSP_FLIT_TAGOP_HI : integer := CHIE_RSP_FLIT_PCRDTYPE_HI + CHIE_RSP_FLIT_TAGOP_WIDTH;
  constant CHIE_RSP_FLIT_TRACETAG_HI : integer := CHIE_RSP_FLIT_TAGOP_HI + CHIE_RSP_FLIT_TRACETAG_WIDTH;

      -- SNP CHANNEL FIELD WIDTHS
  constant CHIE_SNP_FLIT_QOS_WIDTH : integer := 4;
  constant CHIE_SNP_FLIT_SRCID_WIDTH : integer := 7;
  constant CHIE_SNP_FLIT_TXNID_WIDTH : integer := 12; 
  constant CHIE_SNP_FLIT_FWDNID_WIDTH : integer := 7;
  constant CHIE_SNP_FLIT_FWDTXNID_WIDTH : integer := 12;
  constant CHIE_SNP_FLIT_OPCODE_WIDTH : integer := 5;
  constant CHIE_SNP_FLIT_ADDR_WIDTH : integer := 41;
  constant CHIE_SNP_FLIT_NS_WIDTH : integer := 1;
  constant CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH  : integer := 1;
  constant CHIE_SNP_FLIT_RETTOSRC_WIDTH : integer := 1;
  constant CHIE_SNP_FLIT_TRACETAG_WIDTH : integer := 1;
  constant CHIE_SNP_FLIT_TGTID_WIDTH : integer := 7;

  constant CHIE_SNP_FLIT_WIDTH : integer := CHIE_SNP_FLIT_QOS_WIDTH
                                            +CHIE_SNP_FLIT_SRCID_WIDTH
                                            +CHIE_SNP_FLIT_TXNID_WIDTH
                                            +CHIE_SNP_FLIT_FWDNID_WIDTH
                                            +CHIE_SNP_FLIT_FWDTXNID_WIDTH
                                            +CHIE_SNP_FLIT_OPCODE_WIDTH
                                            +CHIE_SNP_FLIT_ADDR_WIDTH
                                            +CHIE_SNP_FLIT_NS_WIDTH
                                            +CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH
                                            +CHIE_SNP_FLIT_RETTOSRC_WIDTH
                                            +CHIE_SNP_FLIT_TRACETAG_WIDTH
                                            +CHIE_SNP_FLIT_TGTID_WIDTH;

  constant CHIE_SNP_FLIT_WIDTH : integer := CHIE_SNP_FLIT_QOS_WIDTH
                                            +CHIE_SNP_FLIT_SRCID_WIDTH
                                            +CHIE_SNP_FLIT_TXNID_WIDTH
                                            +CHIE_SNP_FLIT_FWDNID_WIDTH
                                            +CHIE_SNP_FLIT_FWDTXNID_WIDTH
                                            +CHIE_SNP_FLIT_OPCODE_WIDTH
                                            +CHIE_SNP_FLIT_ADDR_WIDTH
                                            +CHIE_SNP_FLIT_NS_WIDTH
                                            +CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH
                                            +CHIE_SNP_FLIT_RETTOSRC_WIDTH
                                            +CHIE_SNP_FLIT_TRACETAG_WIDTH;

  constant CHIE_SNP_FLIT_QOS_HI : integer := CHIE_SNP_FLIT_QOS_WIDTH-1;
  constant CHIE_SNP_FLIT_SRCID_HI : integer := CHIE_SNP_FLIT_QOS_HI + CHIE_SNP_FLIT_SRCID_WIDTH;
  constant CHIE_SNP_FLIT_TXNID_HI : integer := CHIE_SNP_FLIT_SRCID_HI + CHIE_SNP_FLIT_TXNID_WIDTH; 
  constant CHIE_SNP_FLIT_FWDNID_HI : integer := CHIE_SNP_FLIT_TXNID_HI + CHIE_SNP_FLIT_FWDNID_WIDTH;
  constant CHIE_SNP_FLIT_FWDTXNID_HI : integer := CHIE_SNP_FLIT_FWDNID_HI + CHIE_SNP_FLIT_FWDTXNID_WIDTH;
  constant CHIE_SNP_FLIT_OPCODE_HI : integer := CHIE_SNP_FLIT_FWDTXNID_HI + CHIE_SNP_FLIT_OPCODE_WIDTH;
  constant CHIE_SNP_FLIT_ADDR_HI : integer := CHIE_SNP_FLIT_OPCODE_HI + CHIE_SNP_FLIT_ADDR_WIDTH;
  constant CHIE_SNP_FLIT_NS_HI : integer := CHIE_SNP_FLIT_ADDR_HI + CHIE_SNP_FLIT_NS_WIDTH;
  constant CHIE_SNP_FLIT_DONOTGOTOSD_HI  : integer := CHIE_SNP_FLIT_NS_HI + CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH;
  constant CHIE_SNP_FLIT_RETTOSRC_HI : integer := CHIE_SNP_FLIT_DONOTGOTOSD_HI + CHIE_SNP_FLIT_RETTOSRC_WIDTH;
  constant CHIE_SNP_FLIT_TRACETAG_HI : integer := CHIE_SNP_FLIT_RETTOSRC_HI + CHIE_SNP_FLIT_TRACETAG_WIDTH;
  constant CHIE_SNP_FLIT_TGTID_HI : integer := CHIE_SNP_FLIT_TRACETAG_HI + CHIE_SNP_FLIT_TGTID_WIDTH;




end cache_subsystem_pkg;