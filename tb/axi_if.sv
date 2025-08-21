`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_types_pkg::*;

interface axi_if #(parameter int ID_W=AXI_ID_W, ADDR_W=AXI_ADDR_W, DATA_W=AXI_DATA_W) (input logic clk, rst_n);
  localparam int STRB_W = DATA_W/8;
  // AW
  logic               aw_valid, aw_ready; axi_aw_ar_t aw;
  // W
  logic               w_valid,  w_ready;  axi_w_t     w;
  // B
  logic               b_valid;  logic b_ready; axi_b_t b;
  // AR
  logic               ar_valid, ar_ready; axi_aw_ar_t ar;
  // R
  logic               r_valid;  logic r_ready; axi_r_t  r;

  // -------------- SVA: handshake & sequencing --------------
  // Stable payload when VALID && !READY
  property p_stable_when_wait(sig_valid, sig_ready, bus);
    @(posedge clk) disable iff(!rst_n)
      (sig_valid && !sig_ready) |-> $stable(bus);
  endproperty
  // Basic rules
  aw_stable: assert property(p_stable_when_wait(aw_valid,aw_ready,aw));
  w_stable : assert property(p_stable_when_wait(w_valid ,w_ready ,w));
  ar_stable: assert property(p_stable_when_wait(ar_valid,ar_ready,ar));
  r_stable : assert property(p_stable_when_wait(r_valid ,r_ready ,r));

  // Write response eventually after WLAST
  property p_b_after_last;
    int c; @(posedge clk) disable iff(!rst_n)
      (w_valid && w_ready && w.last, c=0, 1'b1) |-> ##[1:32] (b_valid && b_ready);
  endproperty
  b_after_last: assert property(p_b_after_last);

  // QoS and ID stable during handshake
  id_qos_stable_aw: assert property(@(posedge clk) disable iff(!rst_n)
    (aw_valid && !aw_ready) |-> ($stable(aw.id) && $stable(aw.qos)));
  id_qos_stable_ar: assert property(@(posedge clk) disable iff(!rst_n)
    (ar_valid && !ar_ready) |-> ($stable(ar.id) && $stable(ar.qos)));

  // Cover: backpressure and long bursts
  covergroup cg_bp @(posedge clk);
    option.per_instance=1;
    cp_backp : coverpoint (aw_valid && !aw_ready) or (w_valid && !w_ready) or (ar_valid && !ar_ready) {
      bins bp[] = {1'b1};
    }
    cp_len : coverpoint aw.len { bins len1={0}; bins len16={[15:15]}; bins len256={[255:255]}; }
    cp_qos : coverpoint aw.qos { bins low={[0:3]}; bins mid={[4:7]}; bins hi={[8:15]}; }
    cp_cross : cross cp_len, cp_qos;
  endgroup
  cg_bp cg_inst = new();

  // -------------- Backpressure hooks --------------
  bit stall_aw, stall_w, stall_ar; // drive from TB for stress

  // convenient modports
  modport mst (input clk,rst_n,
    output aw_valid, output aw, input aw_ready,
    output w_valid,  output w,  input w_ready,
    input  b_valid,  input b,   output b_ready,
    output ar_valid, output ar, input ar_ready,
    input  r_valid,  input r,   output r_ready,
    input  stall_aw, input stall_w, input stall_ar);

  modport slv (input clk,rst_n,
    input aw_valid, input aw, output aw_ready,
    input w_valid,  input w,  output w_ready,
    output b_valid, output b, input  b_ready,
    input ar_valid, input ar, output ar_ready,
    output r_valid, output r, input  r_ready);
endinterface
