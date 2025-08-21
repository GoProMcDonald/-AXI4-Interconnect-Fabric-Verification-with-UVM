package axi_types_pkg;
// ----------------- Global parameters -----------------
parameter int AXI_ID_W = 4;
parameter int AXI_ADDR_W = 32;
parameter int AXI_DATA_W = 64; // 64-bit data
parameter int AXI_STRB_W = AXI_DATA_W/8;


typedef enum logic [1:0] {
  AXI_BURST_FIXED=2'b00, 
  AXI_BURST_INCR=2'b01, 
  AXI_BURST_WRAP=2'b10
  } axi_burst_e;


typedef struct packed {
  logic [AXI_ID_W-1:0] id;
  logic [AXI_ADDR_W-1:0] addr;
  logic [7:0] len; // beats-1 (0..255)
  logic [2:0] size; // log2(bytes)
  axi_burst_e burst;
  logic [3:0] qos;
  logic [3:0] cache;
  logic [2:0] prot;
} axi_aw_ar_t;


typedef struct packed {
  logic [AXI_DATA_W-1:0] data;
  logic [AXI_STRB_W-1:0] strb;
  logic last;
} axi_w_t;


typedef struct packed {
  logic [AXI_ID_W-1:0] id;
  logic [1:0] resp; // OKAY/EXOKAY/SLVERR/DECERR
} axi_b_t;


typedef struct packed {
  logic [AXI_ID_W-1:0] id;
  logic [AXI_DATA_W-1:0] data;
  logic [1:0] resp;
  logic last;
} axi_r_t;


endpackage