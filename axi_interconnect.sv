`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_types_pkg::*;

// Simplified N-master × M-slave AXI4 crossbar with address decode, RR/WRR arbitration,
// per-slave backpressure, and ID-based return routing.
module axi_interconnect #(
  parameter int NUM_M = 2,
  parameter int NUM_S = 3,
  parameter logic [AXI_ADDR_W-1:0] SLAVE_BASE [NUM_S] = '{32'h0000_0000,32'h1000_0000,32'h2000_0000},
  parameter logic [AXI_ADDR_W-1:0] SLAVE_MASK [NUM_S] = '{32'h0FFF_F000,32'h0FFF_F000,32'h0FFF_F000},
  parameter bit  USE_QOS = 1
)(
  input  logic clk, rst_n,
  // Master-side ports (arrays)
  input  axi_aw_ar_t m_aw   [NUM_M]; input  logic m_aw_valid [NUM_M]; output logic m_aw_ready [NUM_M];
  input  axi_w_t     m_w    [NUM_M]; input  logic m_w_valid  [NUM_M]; output logic m_w_ready  [NUM_M];
  output axi_b_t     m_b    [NUM_M]; output logic m_b_valid  [NUM_M]; input  logic m_b_ready  [NUM_M];
  input  axi_aw_ar_t m_ar   [NUM_M]; input  logic m_ar_valid [NUM_M]; output logic m_ar_ready [NUM_M];
  output axi_r_t     m_r    [NUM_M]; output logic m_r_valid  [NUM_M]; input  logic m_r_ready  [NUM_M];

  // Slave-side ports (arrays)
  output axi_aw_ar_t s_aw   [NUM_S]; output logic s_aw_valid [NUM_S]; input  logic s_aw_ready [NUM_S];
  output axi_w_t     s_w    [NUM_S]; output logic s_w_valid  [NUM_S]; input  logic s_w_ready  [NUM_S];
  input  axi_b_t     s_b    [NUM_S]; input  logic s_b_valid  [NUM_S]; output logic s_b_ready  [NUM_S];
  output axi_aw_ar_t s_ar   [NUM_S]; output logic s_ar_valid [NUM_S]; input  logic s_ar_ready [NUM_S];
  input  axi_r_t     s_r    [NUM_S]; input  logic s_r_valid  [NUM_S]; output logic s_r_ready  [NUM_S]
);

  // -------- Address decoding: determine target slave index per AW/AR --------
  function automatic int decode(input logic [AXI_ADDR_W-1:0] addr);
    for (int s=0;s<NUM_S;s++) begin
      if (((addr & ~SLAVE_MASK[s]) == SLAVE_BASE[s])) return s;
    end
    return -1; // DECERR
  endfunction

  // Track write destination per master while W channel is active
  int w_dst [NUM_M]; bit w_active[NUM_M];

  // ---------------- AW arbitration per slave ----------------
  logic [NUM_M-1:0] aw_req [NUM_S]; logic [NUM_M-1:0] aw_gnt [NUM_S];
  logic [NUM_M-1:0] ar_req [NUM_S]; logic [NUM_M-1:0] ar_gnt [NUM_S];

  // Build request vectors
  always_comb begin
    for (int s=0;s<NUM_S;s++) begin 
      aw_req[s]='0; 
      ar_req[s]='0; 
    end
    for (int m=0;m<NUM_M;m++) begin
      int s_aw = decode(m_aw[m].addr);
      int s_ar = decode(m_ar[m].addr);
      if (m_aw_valid[m] && s_aw>=0) 
        aw_req[s_aw][m]=1'b1;
      if (m_ar_valid[m] && s_ar>=0) 
        ar_req[s_ar][m]=1'b1;
    end
  end

  // Grant by RR or WRR depending on USE_QOS
  for (genvar s=0;s<NUM_S;s++) begin: GNT_GEN
    if (USE_QOS) begin : USE_WRR
      logic [3:0] qos_m [NUM_M];
      logic [3:0] weight [NUM_M];
      for (genvar m=0;m<NUM_M;m++) begin 
        assign qos_m[m]=m_aw[m].qos; 
        assign weight[m]=4'(1+m); 
      end
      wrr_arbiter #(.N(NUM_M)) U_AW_WRR (.clk, .rst_n, .req(aw_req[s]), .weight(weight), .qos(qos_m), .gnt(aw_gnt[s]), .accept(s_aw_valid[s] && s_aw_ready[s]));
      for (genvar m=0;m<NUM_M;m++) begin 
        assign qos_m[m]=m_ar[m].qos; 
      end
      wrr_arbiter #(.N(NUM_M)) U_AR_WRR (.clk, .rst_n, .req(ar_req[s]), .weight(weight), .qos(qos_m), .gnt(ar_gnt[s]), .accept(s_ar_valid[s] && s_ar_ready[s]));
    end else begin : USE_RR
      rr_arbiter #(.N(NUM_M)) U_AW_RR (.clk, .rst_n, .req(aw_req[s]), .gnt(aw_gnt[s]), .accept(s_aw_valid[s] && s_aw_ready[s]));
      rr_arbiter #(.N(NUM_M)) U_AR_RR (.clk, .rst_n, .req(ar_req[s]), .gnt(ar_gnt[s]), .accept(s_ar_valid[s] && s_ar_ready[s]));
    end
  end

  // MUX AW/AR onto slave ports
  for (genvar s=0;s<NUM_S;s++) begin: AW_AR_MUX
    // Default
    assign s_aw_valid[s] = |aw_gnt[s];
    assign s_ar_valid[s] = |ar_gnt[s];
    always_comb begin
      s_aw[s] = '0; s_ar[s]='0;
      for (int m=0;m<NUM_M;m++) 
        if (aw_gnt[s][m]) 
          s_aw[s]=m_aw[m];
      for (int m2=0;m2<NUM_M;m2++) 
        if (ar_gnt[s][m2]) 
          s_ar[s]=m_ar[m2];
    end
    // Back to masters ready
    for (genvar m=0;m<NUM_M;m++) begin
      assign m_aw_ready[m] = aw_gnt[s][m] ? s_aw_ready[s] : 1'b0;
      assign m_ar_ready[m] = ar_gnt[s][m] ? s_ar_ready[s] : 1'b0;
    end
  end

  // -------------- W routing per master (stick to last AW target) --------------
  for (genvar m=0;m<NUM_M;m++) begin: W_ROUTING
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin w_active[m]<=0; w_dst[m]<=-1; end
      else begin
        if (m_aw_valid[m] && m_aw_ready[m]) begin 
          w_dst[m] <= decode(m_aw[m].addr); 
          w_active[m] <= 1'b1; 
        end
        if (m_w_valid[m] && m_w_ready[m] && m_w[m].last) begin 
          w_active[m] <= 1'b0; 
        end
      end
    end
  end

  // Combine W from masters to each slave
  logic [NUM_M-1:0] w_req [NUM_S]; logic [NUM_M-1:0] w_gnt [NUM_S];
  always_comb begin
    for (int s=0;s<NUM_S;s++) w_req[s]='0;
    for (int m=0;m<NUM_M;m++) if (w_active[m] && m_w_valid[m] && w_dst[m]>=0) w_req[w_dst[m]][m]=1'b1;
  end
  for (genvar s=0;s<NUM_S;s++) begin: W_ARB
    rr_arbiter #(.N(NUM_M)) U_W_RR (.clk, .rst_n, .req(w_req[s]), .gnt(w_gnt[s]), .accept(s_w_valid[s] && s_w_ready[s]));
    assign s_w_valid[s] = |w_gnt[s];
    always_comb begin s_w[s]='0; for (int m=0;m<NUM_M;m++) if (w_gnt[s][m]) s_w[s]=m_w[m]; end
    for (genvar m=0;m<NUM_M;m++) assign m_w_ready[m] = w_gnt[s][m] ? s_w_ready[s] : 1'b0;
  end

  // -------------- B / R return routing by ID ----------------
  // Route by top bits: assume per-master unique ID prefix (midx)
  function automatic int midx_from_id(input logic [AXI_ID_W-1:0] id); return id[AXI_ID_W-1 -: $clog2(NUM_M)]; endfunction

  // B channel
  for (genvar s=0;s<NUM_S;s++) begin: B_DEMUX
    for (genvar m=0;m<NUM_M;m++) begin : B_TO_M
      assign m_b_valid[m] = (s_b_valid[s] && (midx_from_id(s_b[s].id)==m));
      assign m_b[m]       = s_b[s];
      assign s_b_ready[s] = |{m_b_ready};
    end
  end

  // R channel
  for (genvar s=0;s<NUM_S;s++) begin: R_DEMUX
    for (genvar m=0;m<NUM_M;m++) begin : R_TO_M
      assign m_r_valid[m] = (s_r_valid[s] && (midx_from_id(s_r[s].id)==m));
      assign m_r[m]       = s_r[s];
      assign s_r_ready[s] = |{m_r_ready};
    end
  end
endmodule