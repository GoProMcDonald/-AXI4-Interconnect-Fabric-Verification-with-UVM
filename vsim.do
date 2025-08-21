vlib work
vlog +acc -sv +define+UVM_NO_DEPRECATED +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR \
+incdir+../rtl +incdir+../tb \
../rtl/axi_types_pkg.sv \
../rtl/rr_arbiter.sv ../rtl/wrr_arbiter.sv ../rtl/skid_buffer.sv \
../rtl/axi_interconnect.sv \
../tb/axi_if.sv ../tb/axi_slave_mem.sv ../tb/axi_uvm_pkg.sv ../tb/tb_top.sv
vsim -c -do "run -all; quit" tb_top +UVM_TESTNAME=base_test