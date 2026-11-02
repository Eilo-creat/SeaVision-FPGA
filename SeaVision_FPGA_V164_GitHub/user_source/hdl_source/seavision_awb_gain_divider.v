// Exact saturated unsigned Q16 ratio for the original AWB consumer.
// Same throughput (one sample/clock) and start-to-done latency (50 registers).
// Compute only the 20 quotient bits actually consumed; detect overflow first.
// denominator=0 saturates, matching unsigned restoring division followed by clamp.
module seavision_awb_gain_divider(
 input wire clk,rst,start,
 input wire [31:0] denominator,
 input wire [47:0] numerator,
 output wire [47:0] quotient,
 output wire done
);
 reg [31:0] rem_q[0:20],den_q[0:20];
 reg [19:0] bits_q[0:20];
 reg [20:0] overflow_q;
 reg [49:0] valid_q;
 reg [19:0] result_delay[0:28];
 wire initial_overflow = ({4'd0,numerator[47:20]} >= denominator);
 integer i;
 always @(posedge clk or posedge rst) begin
   if(rst) valid_q<=0;
   else valid_q<={valid_q[48:0],start};
 end
 // Data needs no reset: only values with valid_q asserted are consumed.
 always @(posedge clk) begin
   rem_q[0] <= initial_overflow ? 32'd0 : {4'd0,numerator[47:20]};
   den_q[0] <= denominator;
   bits_q[0] <= numerator[19:0];
   overflow_q[0] <= initial_overflow;
 end
 genvar k;
 generate for(k=0;k<20;k=k+1) begin: divide_bit
   wire [32:0] trial = {rem_q[k],bits_q[k][19]};
   wire [32:0] difference = trial - {1'b0,den_q[k]};
   always @(posedge clk) begin
     den_q[k+1] <= den_q[k];
     rem_q[k+1] <= difference[32] ? trial[31:0] : difference[31:0];
     bits_q[k+1] <= {bits_q[k][18:0],!difference[32]};
     overflow_q[k+1] <= overflow_q[k];
   end
 end endgenerate
 always @(posedge clk) begin
   result_delay[0] <= overflow_q[20] ? 20'hfffff : bits_q[20];
   for(i=1;i<29;i=i+1) result_delay[i]<=result_delay[i-1];
 end
 assign quotient={28'd0,result_delay[28]};
 assign done=valid_q[49];
endmodule
