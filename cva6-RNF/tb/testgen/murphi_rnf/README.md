# Murphi model of the RN-F coherence FSM

`rnf_fsm.m` is a [rumur](https://github.com/Smattr/rumur) Murphi model
of the CHI-E RN-F (CVA6 + L1.5 + rnf_link) coherence FSM.

It is the **dual** of `../murphi/hnf_fsm_v2.m`: that model has the
HN-F as DUT and abstracts the RN-Fs; this one has the RN-F as DUT and
abstracts the counterparty (HN-F + remote RN-Fs) as a CHI-legal
non-deterministic environment.  In production verification the
environment is replaced by **gem5's SLICC CHI model** via the
co-simulation TB; Murphi's role is to enumerate every RN-F-side
state and decision so the vector replay covers the protocol surface.

## Scope

- 1 RN-F (the DUT)
- 1 cache line
- 1 outstanding TX REQ at a time (MSHR depth = 1)
- 1 pending RX snoop at a time
- 1 software op queue slot

State vars: `l1 ∈ {I, SC, UC, SD, UD}`, `tx_op`, `tx_phase`,
`tx_expcompack`, `tx_data_dirty`, `rx_snp`, `rx_resp_owed`,
`rx_resp_kind`, `sw_queue`.

## What this model checks

| Invariant | Meaning |
|---|---|
| `L1StateValid` | L1 always in {I,SC,UC,SD,UD} |
| `TxIdleMeansNoOp` | `TX_IDLE` ⇔ no outstanding REQ |
| `TxBusyMeansHasOp` | non-idle phase implies REQ is held |
| `ExpCompAckOnlyDuringTx` | `tx_expcompack=1` only during outstanding REQ |
| `CompAckOnlyForAckBearing` | CompAck never fires for Evict/WriteBack/Atomic |
| `SnoopOwnedIffPending` | `rx_resp_owed` ⇔ `rx_snp ≠ rx_None` |

Plus deadlock detection (rumur fires automatically): every reachable
state has at least one firing rule.

## Run

```bash
rumur rnf_fsm.m --output rnf_fsm.c
cc -std=c11 -march=native -mcx16 -O3 -o rnf_fsm rnf_fsm.c -lpthread
./rnf_fsm
```

Or via the DOT generator:

```bash
./to_dot.py             # rnf_fsm_murphi.dot + .png
./to_dot.py --no-render # DOT only
```

### Current result

```
State Space Explored: 27432 states, 106338 rules fired in 0s.
Status: No error found.
```

## Code reuse

`to_dot.py` reuses the rumur runner, model patcher (`patch_model`),
verifier, and trace parser from `../murphi/to_dot.py`.  Only the
RN-F-specific bits live here:

- `MODEL` path → `rnf_fsm.m`
- `make_dump_block` → Murphi Put statements for RN-F state vars
- `normalize_state_body` → fingerprint regex for the RN-F vars
- `state_short` / `classify` → labelling for the DOT output

The shared module is imported via a `sys.path` insert pointing one
directory up.

## Where this fits in the verification flow

```
                            +-----------------+
                            | rnf_fsm.m       |   <-- this directory
                            | (RN-F + env)    |
                            +-----------------+
                                     |
                                     | (BFS over reachable states)
                                     v
                            +-----------------+
                            | vectors_rnf/    |   (TODO -- see gen_from_rnf.py)
                            | one .txt / tgt  |
                            +-----------------+
                                     |
                                     | (replay driver)
                                     v
              +-----------------------------------------+
              | CVA6 + L1.5 + rnf_link (DUT)            |
              | <----> gem5 SLICC CHI model (env)       |
              +-----------------------------------------+
                                     |
                                     | (compare observed vs expected)
                                     v
                              PASS / FAIL
```

`gen_from_rnf.py` (analogous to `../gen_from_murphi.py`) will turn the
Murphi reachable graph into per-target replay vectors.  Not yet
written.
