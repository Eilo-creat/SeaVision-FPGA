// V152 integer structural descriptor. All decisions use normalized derivatives.
// No RGB class threshold, mean brightness, or dark-region comparison.
module seavision_structure15(
 input wire clk,rst_n,load,input wire [7:0] load_addr,load_data,
 input wire start,output reg done,output reg signed [39:0] score,
 output reg feature_valid,output reg [3:0] feature_index,output reg [7:0] feature_value);
 reg [7:0] patch[0:255];reg [7:0] addr,q;
 always @(posedge clk)begin
  if(load)patch[load_addr]<=load_data;
  q<=patch[addr];
 end
 reg [5:0] state;
 reg [3:0] x,y;
 reg [7:0] l,r,u,d,c;
 reg signed [9:0] gx,gy;
 reg [9:0] ax,ay;
 reg [10:0] mag;
 reg [3:0] cell_idx;reg [1:0] orient;
 reg signed [15:0] dot;
 reg signed [11:0] lap;
 wire [15:0] abs_dot=dot[15] ? -dot : dot;
 wire [11:0] abs_lap=lap[11] ? -lap : lap;
 reg [20:0] sums[0:14];reg [20:0] total;
 wire signed [5:0] dx=$signed({1'b0,x,1'b0})-6'sd15;
 wire signed [5:0] dy=$signed({1'b0,y,1'b0})-6'sd15;
 reg [28:0] dividend;reg [21:0] rem;
 reg [28:0] quotient;reg [5:0] bits_left;
 reg signed [31:0] product;
 integer k;
 function signed [19:0] weight;
 input [3:0] i;
 begin
  case(i)
0:weight=906;
1:weight=3553;
2:weight=-2379;
3:weight=5922;
4:weight=-15033;
5:weight=3633;
6:weight=-291;
7:weight=1851;
8:weight=1601;
9:weight=-1993;
10:weight=1228;
11:weight=-1176;
12:weight=1762;
13:weight=9618;
14:weight=-10701;
  default:weight=0;
  endcase
 end endfunction
 localparam signed [39:0] BIAS=-311383; // MODEL_BIAS (threshold included)
 wire [21:0] shifted_rem={rem[20:0],dividend[28]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;done<=0;feature_valid<=0;score<=0;
   x<=1;y<=1;addr<=0;feature_index<=0;feature_value<=0;
  end else begin
   done<=0;feature_valid<=0;
   case(state)
   0:if(start)begin
     for(k=0;k<15;k=k+1)sums[k]<=0;
     total<=0;x<=1;y<=1;score<=BIAS;state<=1;
   end
   1:begin addr<={y,x}-8'd1;state<=2;end
   2:state<=3;
   3:begin l<=q;addr<={y,x}+8'd1;state<=4;end
   4:state<=5;
   5:begin r<=q;addr<={y,x}-8'd16;state<=6;end
   6:state<=7;
   7:begin u<=q;addr<={y,x}+8'd16;state<=8;end
   8:state<=9;
   9:begin d<=q;addr<={y,x};state<=10;end
   10:state<=11;
   11:begin c<=q;gx<=$signed({2'b0,r})-$signed({2'b0,l});
       gy<=$signed({2'b0,d})-$signed({2'b0,u});state<=12;end
   12:begin ax<=gx<0?-gx:gx;ay<=gy<0?-gy:gy;
       dot<=gx*dx+gy*dy;
       lap<=$signed({4'b0,l})+$signed({4'b0,r})+$signed({4'b0,u})+$signed({4'b0,d})-$signed({2'b0,c,2'b0});
       cell_idx<=(y<6?0:y<12?3:6)+(x<6?0:x<12?1:2);state<=13;end
   13:begin
       mag<=ax+ay;
       orient<=ax>(ay<<1)?0:ay>(ax<<1)?2:((gx<0)==(gy<0))?1:3;
       state<=14;
   end
   14:begin
       sums[cell_idx]<=sums[cell_idx]+mag;
       sums[9+orient]<=sums[9+orient]+mag;
       sums[13]<=sums[13]+abs_dot;
       sums[14]<=sums[14]+abs_lap;
       total<=total+mag;
       if(x==14)begin x<=1;if(y==14)state<=15;else begin y<=y+1'b1;state<=1;end end
       else begin x<=x+1'b1;state<=1;end
   end
   15:begin sums[13]<=sums[13]/15;sums[14]<=sums[14]>>1;
       if(total==0)total<=1;feature_index<=0;state<=16;end
   16:begin dividend<={sums[feature_index],8'b0};rem<=0;quotient<=0;bits_left<=29;state<=17;end
   17:begin
       dividend<=dividend<<1;quotient<=quotient<<1;
       if(shifted_rem>={1'b0,total})begin rem<=shifted_rem-{1'b0,total};quotient[0]<=1;end
       else rem<=shifted_rem;
       bits_left<=bits_left-1'b1;if(bits_left==1)state<=18;
   end
   18:begin feature_value<=quotient>255?8'd255:quotient[7:0];state<=19;end
   19:begin feature_valid<=1;product<=weight(feature_index)*$signed({1'b0,feature_value});state<=20;end
   20:begin score<=score+{{8{product[31]}},product};
       if(feature_index==14)state<=21;else begin feature_index<=feature_index+1'b1;state<=16;end end
   21:begin done<=1;state<=0;end
   default:state<=0;
   endcase
  end
 end
endmodule

