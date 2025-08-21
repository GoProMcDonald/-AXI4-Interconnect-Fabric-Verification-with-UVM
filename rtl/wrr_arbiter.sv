module wrr_arbiter #(parameter N=4, parameter W=4) (
  input  logic         clk, rst_n,
  input  logic [N-1:0] req,
  input  logic [W-1:0] weight [N], // per-port weight (>=1)
  input  logic [3:0]   qos   [N],  // per-request QoS hint
  output logic [N-1:0] gnt,
  input  logic         accept
);
  // Simple WRR: expand requests into slots per weight; prefer higher qos
  // (Compact implementation for simulation; not optimized for synthesis.)
  typedef struct packed {
    logic [3:0] qos; 
    int idx;
    } slot_t;

  slot_t slots [N*16];
  int    nslots;
  always_comb begin
    nslots = 0; 
    gnt='0;
    // build slot list
    for (int i=0;i<N;i++) 
      if (req[i]) begin
      int w = (weight[i]==0)?1:weight[i];
      for (int k=0;k<w;k++) begin 
        slots[nslots] = '{qos:qos[i], idx:i}; 
        nslots++; 
      end
    end
    // pick max qos then lowest index among them
    int best_idx=-1; 
    logic [3:0] best_qos=0; 
    bit found=0;
    for (int s=0;s<nslots;s++) begin
      if (!found || slots[s].qos>best_qos || (slots[s].qos==best_qos && slots[s].idx<best_idx)) begin
        found=1; 
        best_qos=slots[s].qos; 
        best_idx=slots[s].idx;
      end
    end
    if (found) 
      gnt[best_idx]=1'b1;
  end
endmodule
