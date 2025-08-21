module skid_buffer #(parameter W=32) (
  input  logic clk, rst_n,
  // upstream
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [W-1:0] in_data,
  // downstream
  output logic        out_valid,
  input  logic        out_ready,
  output logic [W-1:0] out_data
);
  logic hold_valid; logic [W-1:0] hold_data;
  assign in_ready  = !hold_valid || (out_ready && out_valid);
  assign out_valid = hold_valid ? 1'b1 : in_valid;
  assign out_data  = hold_valid ? hold_data : in_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
      hold_valid <= 1'b0;
    else begin
      if (in_valid && in_ready && !out_ready) begin
        hold_valid <= 1'b1; 
        hold_data <= in_data;
      end else if (out_ready) begin
        hold_valid <= 1'b0;
      end
    end
  end
endmodule