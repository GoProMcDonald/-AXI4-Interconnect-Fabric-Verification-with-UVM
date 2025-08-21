`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_types_pkg::*;
import axi_uvm_pkg::*;

module tb_top;
  // clock/reset
  logic clk=0; 
  always #5 clk=~clk; 
  logic rst_n=0; 

  initial begin 
    rst_n=0; 
    repeat(10) 
      @(posedge clk); 
    rst_n=1; 
  end

  // Param
  localparam int NUM_M=3, NUM_S=3;

  // Master side ifs and slave side ifs (arrays)
  axi_if m_if[NUM_M](.clk(clk), .rst_n(rst_n));
  axi_if s_if[NUM_S](.clk(clk), .rst_n(rst_n));

  // DUT wires as arrays
  axi_aw_ar_t m_aw   [NUM_M]; logic m_aw_valid[NUM_M]; logic m_aw_ready[NUM_M];
  axi_w_t     m_w    [NUM_M]; logic m_w_valid [NUM_M]; logic m_w_ready [NUM_M];
  axi_b_t     m_b    [NUM_M]; logic m_b_valid [NUM_M]; logic m_b_ready [NUM_M];
  axi_aw_ar_t m_ar   [NUM_M]; logic m_ar_valid[NUM_M]; logic m_ar_ready[NUM_M];
  axi_r_t     m_r    [NUM_M]; logic m_r_valid [NUM_M]; logic m_r_ready [NUM_M];

  axi_aw_ar_t s_aw   [NUM_S]; logic s_aw_valid[NUM_S]; logic s_aw_ready[NUM_S];
  axi_w_t     s_w    [NUM_S]; logic s_w_valid [NUM_S]; logic s_w_ready [NUM_S];
  axi_b_t     s_b    [NUM_S]; logic s_b_valid [NUM_S]; logic s_b_ready [NUM_S];
  axi_aw_ar_t s_ar   [NUM_S]; logic s_ar_valid[NUM_S]; logic s_ar_ready[NUM_S];
  axi_r_t     s_r    [NUM_S]; logic s_r_valid [NUM_S]; logic s_r_ready [NUM_S];

  // Connect interfaces to arrays
  generate
    for (genvar m=0;m<NUM_M;m++) begin
      assign m_aw[m]      = m_if[m].aw; assign m_aw_valid[m]=m_if[m].aw_valid; assign m_if[m].aw_ready=m_aw_ready[m];
      assign m_w[m]       = m_if[m].w;  assign m_w_valid[m] =m_if[m].w_valid;  assign m_if[m].w_ready =m_w_ready[m];
      assign m_if[m].b    = m_b[m];     assign m_if[m].b_valid=m_b_valid[m];   assign m_b_ready[m]=m_if[m].b_ready;
      assign m_ar[m]      = m_if[m].ar; assign m_ar_valid[m]=m_if[m].ar_valid; assign m_if[m].ar_ready=m_ar_ready[m];
      assign m_if[m].r    = m_r[m];     assign m_if[m].r_valid=m_r_valid[m];   assign m_r_ready[m]=m_if[m].r_ready;
    end
    for (genvar s=0;s<NUM_S;s++) begin
      assign s_if[s].aw   = s_aw[s]; assign s_if[s].aw_valid=s_aw_valid[s]; assign s_aw_ready[s]=s_if[s].aw_ready;
      assign s_if[s].w    = s_w[s];  assign s_if[s].w_valid =s_w_valid[s];  assign s_w_ready[s] =s_if[s].w_ready;
      assign s_b[s]       = s_if[s].b; assign s_b_valid[s]=s_if[s].b_valid; assign s_if[s].b_ready=s_b_ready[s];
      assign s_if[s].ar   = s_ar[s]; assign s_if[s].ar_valid=s_ar_valid[s]; assign s_ar_ready[s]=s_if[s].ar_ready;
      assign s_if[s].r    = s_r[s];  assign s_r_valid[s] =s_if[s].r_valid;  assign s_if[s].r_ready=s_r_ready[s];
    end
  endgenerate

  // DUT
  axi_interconnect #(.NUM_M(NUM_M), .NUM_S(NUM_S)) dut (
    .clk, .rst_n,
    .m_aw(m_aw), .m_aw_valid(m_aw_valid), .m_aw_ready(m_aw_ready),
    .m_w(m_w),   .m_w_valid(m_w_valid),   .m_w_ready(m_w_ready),
    .m_b(m_b),   .m_b_valid(m_b_valid),   .m_b_ready(m_b_ready),
    .m_ar(m_ar), .m_ar_valid(m_ar_valid), .m_ar_ready(m_ar_ready),
    .m_r(m_r),   .m_r_valid(m_r_valid),   .m_r_ready(m_r_ready),
    .s_aw(s_aw), .s_aw_valid(s_aw_valid), .s_aw_ready(s_aw_ready),
    .s_w(s_w),   .s_w_valid(s_w_valid),   .s_w_ready(s_w_ready),
    .s_b(s_b),   .s_b_valid(s_b_valid),   .s_b_ready(s_b_ready),
    .s_ar(s_ar), .s_ar_valid(s_ar_valid), .s_ar_ready(s_ar_ready),
    .s_r(s_r),   .s_r_valid(s_r_valid),   .s_r_ready(s_r_ready)
  );

  // 3 memory slaves
  generate for (genvar s=0;s<NUM_S;s++) begin: SLAVES
    axi_slave_mem u_mem(
      .clk, .rst_n,
      .aw(s_aw[s]), .aw_valid(s_aw_valid[s]), .aw_ready(s_aw_ready[s]),
      .w(s_w[s]),   .w_valid(s_w_valid[s]),   .w_ready(s_w_ready[s]),
      .b(s_b[s]),   .b_valid(s_b_valid[s]),   .b_ready(s_b_ready[s]),
      .ar(s_ar[s]), .ar_valid(s_ar_valid[s]), .ar_ready(s_ar_ready[s]),
      .r(s_r[s]),   .r_valid(s_r_valid[s]),   .r_ready(s_r_ready[s])
    );
  end endgenerate

  // UVM hookups
  initial begin
    // export master vif/midx to agents
    for (int m=0;m<NUM_M;m++) begin
      uvm_config_db#(virtual axi_if.mst)::set(null, $sformatf("uvm_test_top.env.agent_m%0d.drv",m), "vif", m_if[m]);
      uvm_config_db#(virtual axi_if.mst)::set(null, $sformatf("uvm_test_top.env.agent_m%0d.mon",m), "vif", m_if[m]);
      uvm_config_db#(int)::set(null, $sformatf("uvm_test_top.env.agent_m%0d.*",m), "midx", m);
    end
  end

  initial begin 
    run_test(); 
  end
  
endmodule
