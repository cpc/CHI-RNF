# CHI-RNF — An Open-Source AMBA CHI E.b Fully-Coherent Request Node

An AMBA CHI E.b Request Node (RN-F) integrated with the CVA6 RISC-V core,
together with the verification flow used to qualify it: a formally-backed
directed test generator, an IP-level testbench, and a gem5 SLICC
co-simulation environment.

Licensed under the Solderpad Hardware License v2.1 — see [`LICENSE`](LICENSE).
Non-hardware files (generators, run scripts, Murphi models) carry a plain
Apache-2.0 header, which Solderpad v2.1 explicitly permits. Bundled and
derived third-party components keep their own licences: OpenPiton and 19
OpenSPARC-derived files under `cache/` and `src/` are BSD-3-Clause
(Princeton), `opennoc/` is Mulan PSL v2, and `common_cells/` and `axi2mem/`
are Solderpad v0.51. See [`NOTICE`](NOTICE) for the full list; per-file
headers are authoritative.

---

## Paper

**Open-Source End-to-End-Verified CHI E.b Coherent Requester Interface**

Abdesattar Kalache, Teemu Rinne, Joonas Multanen, Uffke Drechsler\*,
Pekka Jääskeläinen
Customized Parallel Computing Group, Tampere University, Finland —
\*Codasip

*IEEE Nordic Circuits and Systems Conference (NorCAS) 2026, Tampere,
Finland, 20–21 October 2026 — System-on-Chip track.*

> Coherent many-core architectures form the foundation of modern
> high-performance computing systems. Industrial systems have standardized on
> advanced coherence protocols, such as AMBA CHI and Compute Express Link
> (CXL), which support scalable, topology-agnostic multi-chiplet designs with
> robust feature sets and chip-to-chip (C2C) interoperability guarantees.
> However, due to the immense complexity of designing and verifying these
> systems, academia and open-source hardware platforms have lagged behind,
> often limited to simpler, non-scalable alternatives.
>
> To this end, this paper presents the microarchitectural design,
> implementation, and an end-to-end validation methodology for an open-source
> AMBA CHI Request Node (RN-F). At the hardware level, we detail a highly
> parameterizable RN-F microarchitecture with a robust bridging interface
> designed for seamless integration with RISC-V cores like the CVA6. To
> overcome the notorious verification effort associated with protocol
> conformance, we propose a formally-backed verification environment using a
> model-based Directed Test Generator (DTG). By extracting the protocol state
> machine from a formal Murϕ model to feed an IP-level verification
> environment, through which we achieve 100% functional coverage. Furthermore,
> we demonstrate system-level correctness through a novel gem5 SLICC
> co-simulation framework. Finally, the RN-F is synthesized on a 22nm node,
> providing performance and area baselines across different hardware
> configurations. The design reaches 1.35GHz pipeline frequency and meets
> frequencies between 900 and 1000MHz across various design points.

*Index terms:* AMBA CHI, Open-Source Coherent Multi-core, RISC-V

---

## Getting started

```bash
export PROJ_ROOT=$(pwd)
git submodule update --init --recursive
```

`PROJ_ROOT` is the repository root (the parent of `cva6-RNF/`) and is
expanded inside every file list.

To build and run the IP-level testbench:

```bash
cd cva6-RNF/tb
make COVERAGE=1 rnf-ip-sim
```

---

## Repository structure

```
.
├── cva6-RNF/              RN-F design, testbenches and build flows
│   ├── cache/
│   │   ├── rnf_cache/     RN-F cache: coherence pipeline, MSHR, tag/data
│   │   │                  SRAM wrappers, request register, TX/RX encoders
│   │   ├── rnf_link/      CHI link layer: per-channel flit pack/unpack
│   │   │                  (REQ/RSP/DAT/SNP) and the activation handshake
│   │   └── include/       Shared headers: chie_defines.v (opcode source of
│   │                      truth), rnf_param.v, rnf_defines.v, wt_cache_pkg
│   ├── src/               HN-F: MSHR, cache pipeline, snoop filter, atomics
│   ├── opennoc/           OpenNoC interconnect RTL (HN-F, HN-I, RN-I, SN-F)
│   ├── openpiton/         OpenPiton submodule — CVA6 core and package chain
│   ├── tb/                Testbenches (see below)
│   ├── fpga/              Vivado non-project flow for the VCU118 prototype
│   ├── synthesis/         22 nm synthesis scripts and reports
│   └── sw/                Bare-metal test programs
├── sw/                    System-level software for the co-simulation
├── docs/                  Reference documents
└── LICENSE
```

### Testbenches — `cva6-RNF/tb/`

| Entry point | Scope |
|---|---|
| `rnf_ip_tb.sv` | **IP-level.** RN-F cache + link against the abstract HN-F in `chi_hnf_responder.sv`. No CVA6, no SystemC. Driven by replayed Murϕ-derived vectors. See [`RNF_IP_TESTING.md`](cva6-RNF/tb/RNF_IP_TESTING.md). |
| `riscv_rnf_hnf_tb.sv` | RN-F against the RTL HN-F and the behavioural interconnect. |
| `cosim/riscv_rnf_gem5_tb.sv` | **Full-system co-simulation.** CVA6 cores against gem5's SLICC CHI model over shared memory. |
| `cosim/tlm_rnf_hnf_tb.sv` | SystemC TLM RN-F model paired with the RTL HN-F. |
| `chi_icn_beh.sv` | Behavioural interconnect used by the system testbenches. |
| `chi_monitor.sv` | CHI protocol monitor. |
| `rnf_coverage/` | Functional coverage model: phase tracker plus covergroups, bound into both the IP-level and co-simulation testbenches. |

Everything that needs a second simulation kernel lives in
[`cosim/`](cva6-RNF/tb/cosim/): the two co-simulation testbench tops, the
SystemC TLM RN-F bridge (`chi_tlm_rnf.{h,cpp}`) with its `sc_main` stub and
SV port stub, the TLM file list, and the coverage bind for the gem5 TB.

File lists: `rnf_ip_flist` (IP-level), `chi_flist` (full system),
`cosim/chi_tlm_flist` (TLM).

### Co-simulation infrastructure

[`cva6-RNF/tb/cosim/`](cva6-RNF/tb/cosim/) holds the two testbenches that need
a second simulation kernel. Their external requirements differ sharply:

- **SystemC TLM** (`tlm_rnf_hnf_tb.sv`) is self-contained. The TLM RN-F model
  `chi_tlm_rnf.{h,cpp}` builds with `sccom` against the SystemC library that
  ships with Questa, so `make QUESTA=<path> all sim` is sufficient.
- **gem5 full-system** (`riscv_rnf_gem5_tb.sv`) cannot be built from this
  repository alone — see below.

#### gem5 co-simulation

The full-system flow pairs the RTL RN-F in this repository with gem5's SLICC
CHI Ruby home node and DRAM model. The two simulators run as separate
processes and exchange CHI flits through a POSIX shared-memory segment, so
gem5 supplies the point of coherence and memory while Questa drives the real
RN-F RTL. This is what makes the co-simulation a check of the RTL against an
independent CHI implementation rather than against a testbench model.

**The gem5 side is not part of this repository.** It lives in

> **<https://github.com/Kalache-abdesattar/gem5_co_simulation>**

and users must refer to that repository for the co-simulation infrastructure
and its build and run instructions. It provides the patched gem5 build
(`X86_CHI`), the CHI VIP with its IPC bridge, the SystemC wrapper
(`questa_top_ipc_wrap.sv`) that Questa elaborates alongside the RTL, and the
`chi_hnf_only.py` run configuration. Without it, `riscv_rnf_gem5_tb.sv` has no
home node to talk to.

| Side | Provided by |
|---|---|
| CVA6 cores, RN-F cache and CHI link, flit adapter, coverage bind | this repository |
| CHI HN-F state machine, DRAM model, IPC bridge, SystemC wrapper | [`gem5_co_simulation`](https://github.com/Kalache-abdesattar/gem5_co_simulation) |
| System software under test | `sw/`, `cva6-RNF/sw/` |

Two practical notes. gem5 must be started first, since it creates the
shared-memory segment that Questa attaches to during `start_of_simulation`.
And the flit geometry differs across the boundary — 256-bit RTL DAT beats
against a 512-bit IPC flit, 12-bit against 8-bit TXNID — which
`riscv_rnf_gem5_tb.sv` reconciles by packing and splitting DAT flits.
[`tb/readme.md`](cva6-RNF/tb/readme.md) documents the full field mapping, the
build sequence on both sides, and the current known issues.

### Verification flow — `cva6-RNF/tb/testgen/`

The directed test generator and its supporting analysis.

| Path | Purpose |
|---|---|
| `murphi_rnf/rnf_fsm.m` | Murϕ model of the RN-F: one node against a non-deterministic CHI-legal environment. Source of the directed vectors. |
| `murphi/hnf_fsm_v2.m` | Two-sided model — HN-F plus `NUM_RNF` RN-F agents, carrying the system coherence invariants. |
| `murphi_sys/sys_fsm.m` | Full-system model: detailed RN-Fs, a simplified HN-F and an abstract external requester. |
| `gen_from_rnf*.py` | Vector generators — BFS over the model's transition graph, prefix-shared 2-switch targets, and race-cell enumeration. |
| `gen_random_vectors.py` | Alphabet-matched constrained-random baseline. |
| `run_convergence.sh` | Coverage-versus-executed-events sweep. |
| `coverage_exclude.do` | Coverage exclusions, each with its justification recorded inline. |
| `COVERAGE_MODEL.md` | What each covergroup measures and why. |

Verifying a Murϕ model (requires [rumur](https://github.com/Smattr/rumur)):

```bash
cd cva6-RNF/tb/testgen/murphi_rnf
rumur --output rnf_fsm.c rnf_fsm.m
cc -std=c11 -march=native -mcx16 -O3 -o rnf_fsm rnf_fsm.c -lpthread
./rnf_fsm
```

---

## CHI message support

| Channel | Messages |
|---|---|
| **REQ** | ReadClean, ReadUnique, ReadNoSnp, WriteNoSnpPtl, WriteBackFull, AtomicLoad (ADD/CLR/SET/EOR/SMAX/UMAX/SMIN/UMIN), AtomicSwap |
| **SNP** | SnpUnique, SnpShared, SnpClean, SnpCleanInvalid, SnpCleanShared, SnpMakeInvalid |
| **RSP** | Comp, ReadReceipt, RespSepData, DBIDResp, CompDBIDResp, DBIDRespOrd, CompAck, SnpResp |
| **DAT** | CompData, DataSepResp, CopyBackWrData, NonCopyBackWrData, SnpRespData |

Cache line states: **UD, UC, SC, I** — mapping to MESI M, E, S, I.

The AtomicLoad variants cover the RISC-V A-extension AMOs. Distributed
virtual memory (DVM), RAS and poison signalling, the retry and
credit-grant flow, and the dataless store-upgrade optimisation
(CleanUnique) are not yet implemented.
