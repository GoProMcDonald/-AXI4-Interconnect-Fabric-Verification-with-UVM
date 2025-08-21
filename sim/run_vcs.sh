#!/usr/bin/env bash
set -euo pipefail
TOP=tb_top
vcs -full64 -sverilog -timescale=1ns/1ps \
+incdir+../rtl +incdir+../tb \
+define+UVM_NO_DEPRECATED +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR \
../rtl/axi_types_pkg.sv \
../rtl/rr_arbiter.sv ../rtl/wrr_arbiter.sv ../rtl/skid_buffer.sv \
../rtl/axi_interconnect.sv \
../tb/axi_if.sv ../tb/axi_slave_mem.sv ../tb/axi_uvm_pkg.sv ../tb/tb_top.sv \
-l compile.log
./simv +UVM_TESTNAME=base_test -l run.log
