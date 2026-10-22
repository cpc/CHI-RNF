-- Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
-- Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
--
-- SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
--
-- Licensed under the Solderpad Hardware License v2.1 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at:
--
--     https://solderpad.org/licenses/SHL-2.1/
--
-- Unless required by applicable law or agreed to in writing, any work
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
-- implied.  See the License for the specific language governing
-- permissions and limitations under the License.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
--use work.ariane_pkg.all;
use work.cache_subsystem_pkg.all;
use work.wt_cache_pkg.all;
use work.riscv.all;


entity rnf_wrapper is

  generic (
    CHIE_REQ_ADDR_WIDTH_PARAM     : integer := 44;
    CHIE_SNP_ADDR_WIDTH_PARAM     : integer := 41;
    CHIE_NID_WIDTH_PARAM          : integer := 7;                           
    CHIE_DATA_WIDTH_PARAM         : integer := 256;
    CHIE_BE_WIDTH_PARAM           : integer := 32;
    CHIE_DATACHECK_WIDTH_PARAM    : integer := 32;
    CHIE_POISON_WIDTH_PARAM       : integer := 4;
    CHIE_REQ_RSVDC_WIDTH_PARAM    : integer := 0;
    CHIE_DAT_RSVDC_WIDTH_PARAM    : integer := 0;
    HNF_NID_PARAM                 : integer := 15;
    XP_LCRD_NUM_PARAM             : integer := 15;
    CACHED_REGION_BASE            : std_logic_vector := X"80000000";
    CACHED_REGION_SIZE            : std_logic_vector := X"80000";
    BOOT_REGION_BASE              : std_logic_vector := X"FFF1010000";
    BOOT_REGION_SIZE              : std_logic_vector := X"10000";
    IO_REGION_BASE                : std_logic_vector := X"FFF1000000";
    IO_REGION_SIZE                : std_logic_vector := X"1000";
    corecount_g                   : integer := 2);

  port (
    clk : in std_logic;
    rst_n : in std_logic;
    clk_en : in std_logic;

      --CHI signals
    rxrspflitv : in std_logic_vector(corecount_g-1 downto 0);
    rxrspflit : in std_logic_vector(corecount_g*CHIE_RSP_FLIT_WIDTH-1 downto 0);
    rxrspflitpend : in std_logic_vector(corecount_g-1 downto 0);
    -- from data channel
    rxdatflitv : in std_logic_vector(corecount_g-1 downto 0);
    rxdatflit : in std_logic_vector(corecount_g*CHIE_DAT_FLIT_WIDTH-1 downto 0);
    rxdatflitpend : in std_logic_vector(corecount_g-1 downto 0);
    -- to snoop channel         TODO
    rxsnpflitv : in std_logic_vector(corecount_g-1 downto 0);
    rxsnpflit : in std_logic_vector(corecount_g*CHIE_SNP_FLIT_WIDTH-1 downto 0);
    rxsnpflitpend : in std_logic_vector(corecount_g-1 downto 0);
    -- Credits back from responder?
    txreqlcrdv : in std_logic_vector(corecount_g-1 downto 0);
    txrsplcrdv : in std_logic_vector(corecount_g-1 downto 0);
    txdatlcrdv : in std_logic_vector(corecount_g-1 downto 0);
    -- OUTPUTS
    -- Credits to requestor
    rxrsplcrdv : out std_logic_vector(corecount_g-1 downto 0);
    rxdatlcrdv : out std_logic_vector(corecount_g-1 downto 0);
    rxsnplcrdv : out std_logic_vector(corecount_g-1 downto 0);
    -- to request channel
    txreqflitv : out std_logic_vector(corecount_g-1 downto 0);
    txreqflit : out std_logic_vector(corecount_g*CHIE_REQ_FLIT_WIDTH-1 downto 0);
    txreqflitpend : out std_logic_vector(corecount_g-1 downto 0);
    -- response channel
    txrspflitv : out std_logic_vector(corecount_g-1 downto 0);
    txrspflit : out std_logic_vector(corecount_g*CHIE_RSP_FLIT_WIDTH-1 downto 0) ;
    txrspflitpend : out std_logic_vector(corecount_g-1 downto 0);
    -- to data channel
    txdatflitv : out std_logic_vector(corecount_g-1 downto 0);
    txdatflit : out std_logic_vector(corecount_g*CHIE_DAT_FLIT_WIDTH-1 downto 0) ;
    txdatflitpend : out std_logic_vector(corecount_g-1 downto 0);
    -- Link layer handshake
    txlinkactivereq : out std_logic_vector(corecount_g-1 downto 0);
    txlinkactiveack : in std_logic_vector(corecount_g-1 downto 0);
    rxlinkactivereq : in std_logic_vector(corecount_g-1 downto 0);
    rxlinkactiveack : out std_logic_vector(corecount_g-1 downto 0);
    txactive : out std_logic_vector(corecount_g-1 downto 0);
    rxactive : in std_logic_vector(corecount_g-1 downto 0)
    );

end rnf_wrapper;

architecture structural of rnf_wrapper is
    --
    component rnf_top is
        generic (
              -- values mostly according to rnf_param.v
              CHIE_REQ_ADDR_WIDTH_PARAM     : integer;
              CHIE_SNP_ADDR_WIDTH_PARAM     : integer;
              CHIE_NID_WIDTH_PARAM          : integer;                           
              CHIE_DATA_WIDTH_PARAM         : integer;
              CHIE_BE_WIDTH_PARAM           : integer;
              CHIE_DATACHECK_WIDTH_PARAM    : integer;
              CHIE_POISON_WIDTH_PARAM       : integer;
              CHIE_REQ_RSVDC_WIDTH_PARAM    : integer;
              CHIE_DAT_RSVDC_WIDTH_PARAM    : integer;
              HNF_NID_PARAM                 : integer;
              XP_LCRD_NUM_PARAM             : integer;
              CACHED_REGION_BASE            : std_logic_vector;
              CACHED_REGION_SIZE            : std_logic_vector;
              BOOT_REGION_BASE              : std_logic_vector;
              BOOT_REGION_SIZE              : std_logic_vector;
              IO_REGION_BASE                : std_logic_vector;
              IO_REGION_SIZE                : std_logic_vector;
              RNF_NID                       : integer
              );
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            clk_en : in std_logic;

            --CHI signals
            rxrspflitv : in std_logic;
            rxrspflit : in std_logic_vector(CHIE_RSP_FLIT_WIDTH-1 downto 0);
            rxrspflitpend : in std_logic;
            -- from data channel
            rxdatflitv : in std_logic;
            rxdatflit : in std_logic_vector(CHIE_DAT_FLIT_WIDTH-1 downto 0);
            rxdatflitpend : in std_logic;
            -- to snoop channel         TODO
            rxsnpflitv : in std_logic;
            rxsnpflit : in std_logic_vector(CHIE_SNP_FLIT_WIDTH-1 downto 0);
            rxsnpflitpend : in std_logic;
            -- Credits back from responder?
            txreqlcrdv : in std_logic;
            txrsplcrdv : in std_logic;
            txdatlcrdv : in std_logic;
            -- OUTPUTS
            -- Credits to requestor
            rxrsplcrdv : out std_logic;
            rxdatlcrdv : out std_logic;
            rxsnplcrdv : out std_logic;
            -- to request channel
            txreqflitv : out std_logic;
            txreqflit : out std_logic_vector(CHIE_REQ_FLIT_WIDTH-1 downto 0);
            txreqflitpend : out std_logic;
            -- response channel
            txrspflitv : out std_logic;
            txrspflit : out std_logic_vector(CHIE_RSP_FLIT_WIDTH-1 downto 0) ;
            txrspflitpend : out std_logic;
            -- to data channel
            txdatflitv : out std_logic;
            txdatflit : out std_logic_vector(CHIE_DAT_FLIT_WIDTH-1 downto 0) ;
            txdatflitpend : out std_logic;
            -- Link layer handshake
            txlinkactivereq : out std_logic;
            txlinkactiveack : in std_logic;
            rxlinkactivereq : in std_logic;
            rxlinkactiveack : out std_logic;
            txactive : out std_logic;
            rxactive : in std_logic
        );
    end component;
begin
    --
    -- ASETA MYÖS JOKA CORELLE OMA CORE-ID (RNF_PARAM)
    RNF_GEN : for i in 0 to corecount_g-1 generate
      rnf : rnf_top
        generic map(
              -- values mostly according to rnf_param.v
              CHIE_REQ_ADDR_WIDTH_PARAM     => CHIE_REQ_ADDR_WIDTH_PARAM,       --44,
              CHIE_SNP_ADDR_WIDTH_PARAM     => CHIE_SNP_ADDR_WIDTH_PARAM,       --41,
              CHIE_NID_WIDTH_PARAM          => CHIE_NID_WIDTH_PARAM,       --7,                           
              CHIE_DATA_WIDTH_PARAM         => CHIE_DATA_WIDTH_PARAM,       --256,
              CHIE_BE_WIDTH_PARAM           => CHIE_BE_WIDTH_PARAM,       --32,
              CHIE_DATACHECK_WIDTH_PARAM    => CHIE_DATACHECK_WIDTH_PARAM,       --32,
              CHIE_POISON_WIDTH_PARAM       => CHIE_POISON_WIDTH_PARAM,       --4,
              CHIE_REQ_RSVDC_WIDTH_PARAM    => CHIE_REQ_RSVDC_WIDTH_PARAM,       --0,
              CHIE_DAT_RSVDC_WIDTH_PARAM    => CHIE_DAT_RSVDC_WIDTH_PARAM,       --0,
              HNF_NID_PARAM                 => HNF_NID_PARAM,       --15,
              XP_LCRD_NUM_PARAM             => XP_LCRD_NUM_PARAM,       --15,
              CACHED_REGION_BASE            => CACHED_REGION_BASE,
              CACHED_REGION_SIZE            => CACHED_REGION_SIZE,
              BOOT_REGION_BASE              => BOOT_REGION_BASE,
              BOOT_REGION_SIZE              => BOOT_REGION_SIZE,
              IO_REGION_BASE                => IO_REGION_BASE,
              IO_REGION_SIZE                => IO_REGION_SIZE,
              RNF_NID                       => i
            )
        port map(
            clk => clk,
            rst_n  => rst_n,
            clk_en => clk_en,

            --CHI signals
            rxrspflitv => rxrspflitv(i),
            rxrspflit => rxrspflit((i+1)*CHIE_RSP_FLIT_WIDTH-1 downto i*CHIE_RSP_FLIT_WIDTH),
            rxrspflitpend => rxrspflitpend(i),
            -- from data channel
            rxdatflitv => rxdatflitv(i),
            rxdatflit => rxdatflit((i+1)*CHIE_DAT_FLIT_WIDTH-1 downto i*CHIE_DAT_FLIT_WIDTH),
            rxdatflitpend => rxdatflitpend(i),
            -- to snoop channel         
            rxsnpflitv => rxsnpflitv(i),
            rxsnpflit => rxsnpflit((i+1)*CHIE_SNP_FLIT_WIDTH-1 downto i*CHIE_SNP_FLIT_WIDTH),
            rxsnpflitpend => rxsnpflitpend(i),
            -- Credits back from responder?
            txreqlcrdv => txreqlcrdv(i),
            txrsplcrdv => txrsplcrdv(i),
            txdatlcrdv => txdatlcrdv(i),
            -- OUTPUTS
            -- Credits to requestor
            rxrsplcrdv => rxrsplcrdv(i),
            rxdatlcrdv => rxdatlcrdv(i),
            rxsnplcrdv => rxsnplcrdv(i),
            -- to request channel
            txreqflitv => txreqflitv(i),
            txreqflit => txreqflit((i+1)*CHIE_REQ_FLIT_WIDTH-1 downto i*CHIE_REQ_FLIT_WIDTH),
            txreqflitpend => txreqflitpend(i),
            -- response channel
            txrspflitv => txrspflitv(i),
            txrspflit => txrspflit((i+1)*CHIE_RSP_FLIT_WIDTH-1 downto i*CHIE_RSP_FLIT_WIDTH),
            txrspflitpend => txrspflitpend(i),
            -- to data channel
            txdatflitv => txdatflitv(i),
            txdatflit => txdatflit((i+1)*CHIE_DAT_FLIT_WIDTH-1 downto i*CHIE_DAT_FLIT_WIDTH),
            txdatflitpend => txdatflitpend(i),
            -- Link handshake
            txlinkactivereq => txlinkactivereq(i),
            txlinkactiveack => txlinkactiveack(i),
            rxlinkactivereq => rxlinkactivereq(i),
            rxlinkactiveack => rxlinkactiveack(i),
            txactive => txactive(i),
            rxactive => rxactive(i)
        );
    end generate RNF_GEN;      

end structural;
