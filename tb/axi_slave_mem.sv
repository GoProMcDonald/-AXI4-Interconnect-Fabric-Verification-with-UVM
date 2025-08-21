import axi_types_pkg::*;

module axi_slave_mem #(
  parameter int ID_W=AXI_ID_W,
  parameter int ADDR_W=AXI_ADDR_W,
  parameter int DATA_W=AXI_DATA_W,
  parameter int MEM_BYTES=1<<20 // 1MB per slave
)(
  input  logic clk, rst_n,
  // Slave side (looks like a device behind interconnect)
  input  axi_aw_ar_t aw; input logic aw_valid; output logic aw_ready,
  input  axi_w_t     w;  input logic w_valid;  output logic w_ready,
  output axi_b_t     b;  output logic b_valid; input  logic b_ready,
  input  axi_aw_ar_t ar; input logic ar_valid; output logic ar_ready,
  output axi_r_t     r;  output logic r_valid; input  logic r_ready
);
  localparam int STRB_W = DATA_W/8;
  // byte-addressable memory
  logic [7:0] mem [0:MEM_BYTES-1];

  // write FSM
  typedef enum logic [1:0] {W_IDLE,W_DATA,W_RESP} wst_e; wst_e wst;
  logic [ADDR_W-1:0] waddr; logic [7:0] wlen; logic [2:0] wsize; logic [ID_W-1:0] wid;

  // read FSM
  typedef enum logic [1:0] {R_IDLE,R_DATA} rst_e; rst_e rst;
  logic [ADDR_W-1:0] raddr; logic [7:0] rlen; logic [2:0] rsize; logic [ID_W-1:0] rid;

  assign aw_ready = (wst==W_IDLE);
  assign ar_ready = (rst==R_IDLE);
  assign w_ready  = (wst==W_DATA);
  assign b_valid  = (wst==W_RESP);
  assign r_valid  = (rst==R_DATA);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin wst<=W_IDLE; rst<=R_IDLE; end
    else begin
      // Write channel
      case (wst)
        W_IDLE: if (aw_valid && aw_ready) begin
          waddr<=aw.addr; wlen<=aw.len; wsize<=aw.size; wid<=aw.id; wst<=W_DATA; end
        W_DATA: if (w_valid && w_ready) begin
          // write bytes gated by strobe
          for (int bidx=0;bidx<STRB_W;bidx++) if (w.strb[bidx]) begin
            int byte_addr = (waddr + bidx);
            if (byte_addr < MEM_BYTES) mem[byte_addr] <= w.data[8*bidx +: 8];
          end
          waddr <= waddr + STRB_W; // assuming INCR & DATA_W aligned
          if (w.last || (wlen==0)) wst<=W_RESP; else wlen<=wlen-1;
        end
        W_RESP: if (b_ready) wst<=W_IDLE;
      endcase
      // Read channel
      case (rst)
        R_IDLE: if (ar_valid && ar_ready) begin
          raddr<=ar.addr; rlen<=ar.len; rsize<=ar.size; rid<=ar.id; rst<=R_DATA; end
        R_DATA: if (r_ready) begin
          // assemble data
          axi_r_t rtmp; rtmp.id=rid; rtmp.resp=2'b00; rtmp.last=(rlen==0);
          for (int bidx=0;bidx<STRB_W;bidx++) begin
            int byte_addr = (raddr + bidx);
            rtmp.data[8*bidx +: 8] = (byte_addr<MEM_BYTES)? mem[byte_addr] : '0;
          end
          // drive combinationally via r output below
          raddr <= raddr + STRB_W;
          if (rlen==0) rst<=R_IDLE; else rlen<=rlen-1;
        end
      endcase
    end
  end

  // comb outputs
  assign r.id   = rid;   assign r.resp = 2'b00;
  assign r.data = '{default:'0}; // will be overridden by registered path; keep simple
  // emulate data from mem on valid
  always_comb begin
    axi_r_t tmp; tmp.id=rid; tmp.resp=2'b00; tmp.last=(rlen==0);
    for (int bidx=0;bidx<STRB_W;bidx++) begin
      int byte_addr = (raddr + bidx);
      tmp.data[8*bidx +: 8] = (byte_addr<MEM_BYTES)? mem[byte_addr] : '0;
    end
    r = tmp;
  end

  assign b.id = wid; assign b.resp=2'b00; // always OKAY
endmodule
