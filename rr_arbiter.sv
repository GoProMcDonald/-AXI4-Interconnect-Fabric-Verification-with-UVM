module rr_arbiter #(parameter N=4) (
  input  logic         clk, rst_n,
  input  logic [N-1:0] req,
  output logic [N-1:0] gnt,
  input  logic         accept // one-cycle pulse when downstream accepts grant
);
  logic [N-1:0] mask;
  logic [N-1:0] req_masked;
  assign req_masked = req & mask;

  always_comb begin
    gnt = '0;
    if (req_masked != '0) begin
      for (int i=0;i<N;i++) 
        if (req_masked[i]) begin 
          gnt[i]=1'b1; 
          break; 
        end
    end else begin
      for (int i=0;i<N;i++) 
        if (req[i]) begin 
          gnt[i]=1'b1; 
          break; 
        end
    end
  end

  // rotate mask at each accepted grant for fairness
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
      mask <= '1; // initial: grant lowest index first
    else if (accept) begin
      // next mask clears bits up to granted index
      for (int i=0;i<N;i++) 
        if (gnt[i]) begin
        mask <= { {N{i{1'b1}}} } >> i; // circular style
        break;
      end
    end
  end
endmodule