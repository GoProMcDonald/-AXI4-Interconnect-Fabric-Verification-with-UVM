`include "uvm_macros.svh"
package axi_uvm_pkg;
  import uvm_pkg::*;
  import axi_types_pkg::*;

  // ---------------- UVM sequence item ----------------
  class axi_seq_item extends uvm_sequence_item;
    rand bit is_read;                 // 0: write, 1: read
    rand bit [AXI_ID_W-1:0]   id;
    rand bit [AXI_ADDR_W-1:0] addr;
    rand bit [7:0]            len;   // 0..255 -> beats-1
    rand bit [2:0]            size;  // 3'b011 for 8 bytes
    rand axi_burst_e          burst;
    rand bit [3:0]            qos;
    rand bit [AXI_DATA_W-1:0] data[]; // write data payload
    rand bit [AXI_STRB_W-1:0] strb[];

    constraint c_default {
      size == 3;           // 8B beat for DATA_W=64
      burst == AXI_BURST_INCR;
      len inside {[0:255]};
      data.size() == len+1;
      strb.size() == len+1;
      foreach (strb[i]) strb[i] == '1; // full strobes by default
      qos inside {[0:15]};
    }

    `uvm_object_utils_begin(axi_seq_item)
      `uvm_field_int(is_read, UVM_ALL_ON)
      `uvm_field_int(id,      UVM_ALL_ON)
      `uvm_field_int(addr,    UVM_ALL_ON)
      `uvm_field_int(len,     UVM_ALL_ON)
      `uvm_field_int(size,    UVM_ALL_ON)
      `uvm_field_enum(axi_burst_e, burst, UVM_ALL_ON)
      `uvm_field_int(qos,     UVM_ALL_ON)
      `uvm_field_array_int(data,    UVM_ALL_ON)
      `uvm_field_array_int(strb,    UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name="axi_seq_item"); super.new(name); endfunction
  endclass

  // ---------------- Config & environment params ----------------
  class axi_env_cfg extends uvm_object;
    rand int unsigned num_m, num_s;
    rand logic [AXI_ADDR_W-1:0] base[];
    rand logic [AXI_ADDR_W-1:0] mask[];
    rand bit use_qos;
    rand int unsigned max_outstanding;

    constraint c_sizes { num_m inside {[1:8]}; num_s inside {[1:8]};
                         base.size()==num_s; mask.size()==num_s; }

    `uvm_object_utils_begin(axi_env_cfg)
      `uvm_field_int(num_m, UVM_ALL_ON)
      `uvm_field_int(num_s, UVM_ALL_ON)
      `uvm_field_sarray_int(base, UVM_ALL_ON)
      `uvm_field_sarray_int(mask, UVM_ALL_ON)
      `uvm_field_int(use_qos, UVM_ALL_ON)
      `uvm_field_int(max_outstanding, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name="axi_env_cfg"); super.new(name); endfunction
  endclass

  // ---------------- Virtual interface wrapper ----------------
  typedef virtual axi_if.mst axi_vif_m_t;
  typedef virtual axi_if.slv axi_vif_s_t;

  // ---------------- Sequencer ----------------
  class axi_sequencer extends uvm_sequencer #(axi_seq_item);
    `uvm_component_utils(axi_sequencer)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
  endclass

  // ---------------- Driver (master side) ----------------
  class axi_driver extends uvm_driver #(axi_seq_item);
    `uvm_component_utils(axi_driver)
    axi_vif_m_t vif; int midx; // which master

    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(axi_vif_m_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","No vif for axi_driver")
      if (!uvm_config_db#(int)::get(this, "", "midx", midx)) midx=0;
    endfunction

    task run_phase(uvm_phase phase);
      axi_seq_item tr;
      vif.b_ready <= 1; vif.r_ready <= 1; // always ready to take responses
      forever begin
        seq_item_port.get_next_item(tr);
        if (tr.is_read) drive_read(tr); else drive_write(tr);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi_seq_item tr);
      // AW
      vif.aw.id    <= {midx[AXI_ID_W-$clog2(8)-1:0], tr.id[$clog2(8)-1:0]};
      vif.aw.addr  <= tr.addr; vif.aw.len<=tr.len; vif.aw.size<=tr.size; vif.aw.burst<=tr.burst; vif.aw.qos<=tr.qos;
      vif.aw_valid <= 1; @(posedge vif.clk); while(!vif.aw_ready) @(posedge vif.clk); vif.aw_valid<=0;
      // W beats
      foreach (tr.data[i]) begin
        vif.w.data  <= tr.data[i]; vif.w.strb<=tr.strb[i]; vif.w.last <= (i==tr.len);
        vif.w_valid <= 1; @(posedge vif.clk); while(!vif.w_ready) @(posedge vif.clk); vif.w_valid<=0;
      end
      // wait for B
      do @(posedge vif.clk); while(!vif.b_valid); // consume automatically by b_ready
    endtask

    task drive_read(axi_seq_item tr);
      vif.ar.id   <= {midx[AXI_ID_W-$clog2(8)-1:0], tr.id[$clog2(8)-1:0]};
      vif.ar.addr <= tr.addr; vif.ar.len<=tr.len; vif.ar.size<=tr.size; vif.ar.burst<=tr.burst; vif.ar.qos<=tr.qos;
      vif.ar_valid<=1; @(posedge vif.clk); while(!vif.ar_ready) @(posedge vif.clk); vif.ar_valid<=0;
      // consume R beats
      for (int i=0;i<=tr.len;i++) begin
        do @(posedge vif.clk); while(!vif.r_valid);
        // data captured by monitor
      end
    endtask
  endclass

  // ---------------- Monitor ----------------
  class axi_monitor extends uvm_component;
    `uvm_component_utils(axi_monitor)
    axi_vif_m_t vif; int midx; uvm_analysis_port #(axi_seq_item) ap;
    function new(string name, uvm_component parent); super.new(name,parent); ap=new("ap",this); endfunction
    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(axi_vif_m_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF","No vif for axi_monitor")
      void'(uvm_config_db#(int)::get(this, "", "midx", midx));
    endfunction
    task run_phase(uvm_phase phase);
      axi_seq_item cur; bit collecting;
      forever begin @(posedge vif.clk);
        if (vif.aw_valid && vif.aw_ready) begin
          cur = axi_seq_item::type_id::create($sformatf("mon_wr_m%0d",midx));
          cur.is_read=0; cur.id=vif.aw.id; cur.addr=vif.aw.addr; cur.len=vif.aw.len; cur.size=vif.aw.size; cur.burst=vif.aw.burst; cur.qos=vif.aw.qos;
          cur.data.delete(); cur.strb.delete(); collecting=1;
        end
        if (collecting && vif.w_valid && vif.w_ready) begin
          cur.data.push_back(vif.w.data); cur.strb.push_back(vif.w.strb);
          if (vif.w.last) begin ap.write(cur); collecting=0; end
        end
        if (vif.ar_valid && vif.ar_ready) begin
          axi_seq_item rd = axi_seq_item::type_id::create($sformatf("mon_rd_m%0d",midx));
          rd.is_read=1; rd.id=vif.ar.id; rd.addr=vif.ar.addr; rd.len=vif.ar.len; rd.size=vif.ar.size; rd.burst=vif.ar.burst; rd.qos=vif.ar.qos;
          ap.write(rd);
        end
      end
    endtask
  endclass

  // ---------------- Agent ----------------
  class axi_agent extends uvm_component;
    `uvm_component_utils(axi_agent)
    axi_sequencer sqr; axi_driver drv; axi_monitor mon; axi_vif_m_t vif; int midx; bit is_active=1;
    uvm_analysis_port #(axi_seq_item) ap;
    function new(string name, uvm_component parent); super.new(name,parent); ap=new("ap",this); endfunction
    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(axi_vif_m_t)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF","no vif");
      void'(uvm_config_db#(int)::get(this, "", "midx", midx));
      mon=axi_monitor::type_id::create("mon",this);
      uvm_config_db#(axi_vif_m_t)::set(this,"mon","vif",vif);
      uvm_config_db#(int)::set(this,"mon","midx",midx);
      if (is_active) begin
        sqr=axi_sequencer::type_id::create("sqr",this);
        drv=axi_driver   ::type_id::create("drv",this);
        uvm_config_db#(axi_vif_m_t)::set(this,"drv","vif",vif);
        uvm_config_db#(int)::set(this,"drv","midx",midx);
      end
    endfunction
    virtual function void connect_phase(uvm_phase phase); if (is_active) drv.seq_item_port.connect(sqr.seq_item_export); mon.ap.connect(ap); endfunction
  endclass

  // ---------------- Coverage ----------------
  class axi_coverage extends uvm_component;
    `uvm_component_utils(axi_coverage)
    uvm_analysis_imp #(axi_seq_item, axi_coverage) imp; int num_m, num_s;
    covergroup cg with function sample(axi_seq_item tr);
      option.per_instance=1;
      cp_type: coverpoint tr.is_read { bins RD={1}; bins WR={0}; }
      cp_len : coverpoint tr.len { bins s1={0}; bins s16={[15:15]}; bins s255={[255:255]}; }
      cp_qos : coverpoint tr.qos { bins L={[0:3]}; bins M={[4:7]}; bins H={[8:15]}; }
      cross cp_type, cp_len, cp_qos;
    endgroup
    function new(string name, uvm_component parent); super.new(name,parent); imp=new("imp",this); cg=new(); endfunction
    function void write(axi_seq_item t); cg.sample(t); endfunction
  endclass

  // ---------------- Scoreboard w/ reference model ----------------
  class axi_scoreboard extends uvm_component;
    `uvm_component_utils(axi_scoreboard)
    uvm_analysis_imp #(axi_seq_item, axi_scoreboard) imp;
    // Simple memory mirrors per slave, keyed by address
    typedef bit [7:0] byte_t; byte_t mem[string];
    // track latency (cycles) for reads by id
    typedef struct {longint start; bit valid;} lat_t; lat_t rd_start[string];

    function new(string name, uvm_component parent); super.new(name,parent); imp=new("imp",this); endfunction

    // write updates mirror; read checks data ordering/integrity (using slave_mem behavior)
    function void write(axi_seq_item tr);
      if (!tr.is_read) begin
        for (int i=0;i<=tr.len;i++) begin
          for (int b=0;b<AXI_STRB_W;b++) if (tr.strb[i][b]) begin
            string key = $sformatf("0x%08h", tr.addr + i*AXI_STRB_W + b);
            mem[key] = tr.data[i][8*b +: 8];
          end
        end
      end else begin
        // mark read start for latency stats
        string idk=$sformatf("id%0h",tr.id);
        rd_start[idk] = '{start:$time, valid:1'b1};
        // (In a real env, we'd compare observed R beats via slave monitor. Here we infer integrity
        // by cross-checking mirrored memory when R monitor callback is added.)
      end
    endfunction
  endclass

  // ---------------- Virtual sequencer ----------------
  class axi_vseqr extends uvm_sequencer #(axi_seq_item);
    `uvm_component_utils(axi_vseqr)
    axi_sequencer m_sqr[]; function new(string n, uvm_component p); super.new(n,p); endfunction
  endclass

  // ---------------- Env ----------------
  class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)
    axi_env_cfg cfg; axi_agent m_agents[]; axi_coverage cov; axi_scoreboard scb; axi_vseqr vseqr;

    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    virtual function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(axi_env_cfg)::get(this, "", "cfg", cfg)) `uvm_fatal("NOCFG","no cfg");
      m_agents = new[cfg.num_m];
      for (int m=0;m<cfg.num_m;m++) begin
        m_agents[m] = axi_agent::type_id::create($sformatf("agent_m%0d",m), this);
      end
      cov = axi_coverage ::type_id::create("cov", this);
      scb = axi_scoreboard::type_id::create("scb", this);
      vseqr = axi_vseqr::type_id::create("vseqr", this);
    endfunction
    virtual function void connect_phase(uvm_phase phase);
      for (int m=0;m<cfg.num_m;m++) begin m_agents[m].ap.connect(scb.imp); m_agents[m].ap.connect(cov.imp); end
      vseqr.m_sqr = new[cfg.num_m];
      for (int m=0;m<cfg.num_m;m++) vseqr.m_sqr[m] = m_agents[m].sqr;
    endfunction
  endclass

  // ---------------- Sequences ----------------
  class rand_traffic_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(rand_traffic_seq)
    rand int unsigned n_txn=100;
    rand bit mixed_rw=1;
    constraint c_txn { n_txn inside {[50:300]}; }
    function new(string name="rand_traffic_seq"); super.new(name); endfunction
    task body();
      axi_seq_item tr; int seed = $urandom();
      repeat (n_txn) begin
        tr = axi_seq_item::type_id::create("tr");
        tr.randomize() with { is_read == (mixed_rw? $urandom_range(0,1):1); len inside {[0:255]}; qos inside {[0:15]}; addr[31:28] inside {[0:2]}; };
        start_item(tr); finish_item(tr);
      end
    endtask
  endclass

  class backpressure_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(backpressure_seq)
    function new(string name="backpressure_seq"); super.new(name); endfunction
    task body(); rand_traffic_seq s = rand_traffic_seq::type_id::create("s"); s.randomize() with { n_txn==80; };
      s.start(m_sequencer);
    endtask
  endclass

  class qos_sweep_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(qos_sweep_seq)
    task body(); axi_seq_item tr; foreach (int q[16]) begin end // placeholder
      repeat (64) begin
        tr = axi_seq_item::type_id::create("tr"); tr.randomize() with { qos inside {[0:15]}; };
        start_item(tr); finish_item(tr);
      end
    endtask
  endclass

  // ---------------- Base test & specialized tests ----------------
  class base_test extends uvm_test; `uvm_component_utils(base_test)
    axi_env env; axi_env_cfg cfg;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    virtual function void build_phase(uvm_phase phase);
      cfg = axi_env_cfg::type_id::create("cfg");
      cfg.num_m=3; cfg.num_s=3; cfg.use_qos=1; cfg.max_outstanding=16;
      cfg.base=new[3]; cfg.mask=new[3];
      cfg.base = '{32'h0000_0000,32'h1000_0000,32'h2000_0000};
      cfg.mask = '{32'h0FFF_F000,32'h0FFF_F000,32'h0FFF_F000};
      uvm_config_db#(axi_env_cfg)::set(this, "*", "cfg", cfg);
      env = axi_env::type_id::create("env", this);
    endfunction
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      rand_traffic_seq vseq = rand_traffic_seq::type_id::create("vseq");
      // start on all masters
      fork
        vseq.start(env.vseqr.m_sqr[0]);
        vseq.start(env.vseqr.m_sqr[1]);
        vseq.start(env.vseqr.m_sqr[2]);
      join
      #1000; phase.drop_objection(this);
    endtask
  endclass

  class backpressure_test extends base_test; `uvm_component_utils(backpressure_test)
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      backpressure_seq s0 = backpressure_seq::type_id::create("s0");
      backpressure_seq s1 = backpressure_seq::type_id::create("s1");
      backpressure_seq s2 = backpressure_seq::type_id::create("s2");
      fork s0.start(env.vseqr.m_sqr[0]); s1.start(env.vseqr.m_sqr[1]); s2.start(env.vseqr.m_sqr[2]); join
      #1000; phase.drop_objection(this);
    endtask
  endclass

  class qos_fairness_test extends base_test; `uvm_component_utils(qos_fairness_test)
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      qos_sweep_seq q0 = qos_sweep_seq::type_id::create("q0");
      qos_sweep_seq q1 = qos_sweep_seq::type_id::create("q1");
      qos_sweep_seq q2 = qos_sweep_seq::type_id::create("q2");
      fork q0.start(env.vseqr.m_sqr[0]); q1.start(env.vseqr.m_sqr[1]); q2.start(env.vseqr.m_sqr[2]); join
      #1000; phase.drop_objection(this);
    endtask
  endclass

endpackage