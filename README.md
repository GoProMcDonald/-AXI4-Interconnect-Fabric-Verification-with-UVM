# AXI4 Interconnect Fabric Verification (UVM)

A complete, publishable verification project for a **multi-master / multi-slave AXI4 interconnect (crossbar)**.  
The repo includes a **synthesizable simplified crossbar RTL**, a **UVM environment** (master agents, virtual sequencer, scoreboard, coverage, tests), **protocol assertions (SVA)**, **backpressure injection**, and ready-to-run **Questa / VCS** scripts plus a **Jenkinsfile** for CI regressions.

## Highlights

- **Crossbar RTL (synthesizable):** address decode per slave; AW/AR arbitration per slave (**RR** or **WRR+QoS**); W follows the most recent AW target; B/R routed back by **ID prefix**; full ready/valid backpressure.
- **UVM environment:** active master agents (driver/monitor/sequencer), virtual sequencer, scoreboard with a byte-accurate memory mirror, and functional coverage with key crosses.
- **Protocol assurance:** interface-embedded SVA — payload stability on `VALID && !READY`, bounded **WLAST → B**, and **ID/QoS** stability while stalled; covergroups for burst length / QoS / backpressure.
- **Stress & fairness:** random backpressure hooks, long bursts (up to 256 beats), and QoS/weight sweeps to verify fairness and throughput under load.
- **CI-ready:** minimal `vsim.do` / `run_vcs.sh` for smoke tests; **Jenkinsfile** template for nightly or PR regressions.

## Repository Layout

rtl/ # Crossbar and reusable RTL (synthesizable)
axi_types_pkg.sv # Common widths + packed structs (AW/AR/W/B/R)
rr_arbiter.sv # Round-robin arbiter
wrr_arbiter.sv # Weighted RR with QoS
skid_buffer.sv # 1-deep elastic buffer
axi_interconnect.sv# Crossbar (DUT)
tb/ # UVM testbench
axi_if.sv # AXI interface + SVA + coverage + stall hooks
axi_slave_mem.sv # Simple memory-model slave (read/write)
axi_uvm_pkg.sv # Items/agents/env/scoreboard/coverage/tests
tb_top.sv # Testbench top (instantiates DUT/slaves, run_test)
sim/
vsim.do # Questa compile/run
run_vcs.sh # VCS compile/run
jenkins/
Jenkinsfile # Declarative pipeline for CI

markdown
Copy
Edit

## Requirements

- **Simulator:** Siemens **Questa** 2021.2+ or Synopsys **VCS** O-2022.06+
- **UVM:** built-in or available via `$UVM_HOME`
- **Shell:** Bash (for VCS script)

## Quick Start

### Questa
```bash
cd sim
vsim -c -do vsim.do
VCS
bash
Copy
Edit
cd sim
bash run_vcs.sh
Select tests via +UVM_TESTNAME:

bash
Copy
Edit
# Default randomized mixed read/write across masters
bash run_vcs.sh +UVM_TESTNAME=base_test

# Backpressure stress
bash run_vcs.sh +UVM_TESTNAME=backpressure_test

# QoS/WRR fairness sweep
bash run_vcs.sh +UVM_TESTNAME=qos_fairness_test
Useful flags: +ntb_random_seed=<seed> to reproduce; remove -c in Questa to open GUI and add waveform commands.

Verification Scope
Functionality: correct address routing; W follows its AW target; ID-based B/R return; RR/WRR fairness; robustness under backpressure; no deadlock in covered scenarios.

Assertions: handshake stability; bounded WLAST → B; ID/QoS stability while stalled (extendable to a full AXI checker set).

Coverage: burst lengths (1/16/256), QoS tiers, backpressure hits, and selected crosses.

Scoreboard: byte-level mirror for writes; hooks to extend to end-to-end read-data checks via passive slave-side monitors.

CI / Regression
Use jenkins/Jenkinsfile as a template: smoke build, randomized seeds (nightly), and QoS/backpressure suites; logs are archived per build to enable seed-accurate reproduction.

Design Notes & Assumptions
Data width 64b; byte strobes; INCR bursts assumed; master index encoded in the ID prefix for return routing.

RTL favors clarity and interview readability while remaining synthesizable; extend as needed for WRAP/FIXED, error responses, same-ID ordering rules, etc.

License
Released under MIT License (adjust to your policy if required).
