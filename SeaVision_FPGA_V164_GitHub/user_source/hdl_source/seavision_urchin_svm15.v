// Full-frame, multi-scale structure classifier. Candidate positions are a grid,
// not dark/color blobs. Single frame RAM; acquisition pauses while scanning.
module seavision_urchin_svm15 #(
 parameter integer W=320,H=180,TARGETS=4,MAX_RUNS=10,MAX_BLOBS=20,
 parameter integer MIN_PIXELS=22,MAX_CHROMA=118)(
 input wire clk,rst_n,in_valid,in_sof,input wire [23:0] in_rgb,
 output wire ready,capturing,output reg busy,done,overflow,
 output reg [5:0] count,
 output reg [TARGETS*12-1:0] center_x,center_y,box_x0,box_y0,box_x1,box_y1,
 output reg [31:0] processing_cycles,
 output wire [7:0] threshold0,threshold1,threshold2);
 reg [7:0] frame[0:W*H-1];
 reg [15:0] wr_addr,rd_addr;reg [7:0] frame_q;
 reg [3:0] state;
 wire [7:0] gray=(in_rgb[23:16]>>2)+(in_rgb[15:8]>>1)+(in_rgb[7:0]>>2);
 wire frame_we=(state==0 && in_valid && in_sof)||(state==1 && in_valid);
 wire [15:0] frame_wa=state==0 ? 16'd0 : wr_addr;
 always @(posedge clk)begin
  if(frame_we)frame[frame_wa]<=gray;
  frame_q<=frame[rd_addr];
 end
 assign ready=state==0;assign capturing=state==1;
 assign threshold0=0;assign threshold1=0;assign threshold2=0;
 reg [9:0] wx,wy;reg [7:0] size,step;
 reg [1:0] scale;reg [7:0] patch_addr;
 reg [31:0] cycles;
 wire feature_done;wire signed [39:0] feature_score;
 wire unused_valid;wire [3:0] unused_index;wire [7:0] unused_feature;
 seavision_structure15 classifier(.clk(clk),.rst_n(rst_n),
 .load(state==5),.load_addr(patch_addr),.load_data(frame_q),.start(state==6),
 .done(feature_done),.score(feature_score),.feature_valid(unused_valid),
 .feature_index(unused_index),.feature_value(unused_feature));
 reg signed [39:0] best_score[0:TARGETS-1];
 reg [7:0] best_size[0:TARGETS-1];
 reg [9:0] best_cx[0:TARGETS-1],best_cy[0:TARGETS-1];
 reg [5:0] slot,weakest;reg duplicate;integer i;
 wire [9:0] cx=wx+(size>>1),cy=wy+(size>>1);
 // Bounded nonmaximum suppression. Overlapping scales select highest score.
 always @*begin
  slot=count;duplicate=0;weakest=0;
  for(i=0;i<TARGETS;i=i+1)begin
   if(best_score[i]<best_score[weakest])weakest=i;
   if(i<count && !duplicate &&
     cx+(size>>2)+(best_size[i]>>2)>=best_cx[i] &&
     best_cx[i]+(size>>2)+(best_size[i]>>2)>=cx &&
     cy+(size>>2)+(best_size[i]>>2)>=best_cy[i] &&
     best_cy[i]+(size>>2)+(best_size[i]>>2)>=cy)begin slot=i;duplicate=1;end
  end
  if(!duplicate && count==TARGETS)slot=weakest;
 end
 wire [11:0] sx_product=patch_addr[3:0]*size;
 wire [11:0] sy_product=patch_addr[7:4]*size;
 reg [9:0] sx,sy;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;busy<=0;done<=0;overflow<=0;count<=0;
   box_x0<=0;box_y0<=0;box_x1<=0;box_y1<=0;center_x<=0;center_y<=0;
   processing_cycles<=0;cycles<=0;wr_addr<=0;rd_addr<=0;
   scale<=0;wx<=5;wy<=32;size<=24;step<=6;patch_addr<=0;
  end else begin
   done<=0;if(busy)cycles<=cycles+1'b1;
   case(state)
   0:if(in_valid && in_sof)begin wr_addr<=1;busy<=1;cycles<=0;state<=1;end
   1:if(in_valid)begin
     if(wr_addr==W*H-1)begin state<=2;scale<=0;size<=24;step<=6;wx<=5;wy<=32;
      count<=0;box_x0<=0;box_x1<=0;box_y0<=0;box_y1<=0;center_x<=0;center_y<=0;
     end else wr_addr<=wr_addr+1'b1;
   end
   2:begin patch_addr<=0;state<=11;end
   11:begin sx<=wx+(sx_product>>4);sy<=wy+(sy_product>>4);state<=3;end
   3:begin rd_addr<=sy*W+sx;state<=4;end
   4:state<=5;
   5:if(patch_addr==255)state<=6;else begin patch_addr<=patch_addr+1'b1;state<=11;end
   6:state<=7;
   7:if(feature_done)state<=8;
   8:begin
     if(feature_score>=0 && slot<TARGETS && ((!duplicate && count<TARGETS) || feature_score>best_score[slot]))begin
      best_score[slot]<=feature_score;best_size[slot]<=size;
      best_cx[slot]<=cx;best_cy[slot]<=cy;
      box_x0[slot*12+:12]<=wx;box_y0[slot*12+:12]<=wy;
      box_x1[slot*12+:12]<=wx+size-1;box_y1[slot*12+:12]<=wy+size-1;
      center_x[slot*12+:12]<=cx;center_y[slot*12+:12]<=cy;
      if(!duplicate && count<TARGETS)count<=count+1'b1;
     end
     state<=9;
   end
   9:begin
    if(wx+size+step<=W-5)begin wx<=wx+step;state<=2;end
    else if(wy+size+step<=H-5)begin wx<=5;wy<=wy+step;state<=2;end
    else if(scale<3)begin scale<=scale+1'b1;wx<=5;wy<=32;state<=2;
     case(scale)0:begin size<=40;step<=10;end
     1:begin size<=64;step<=16;end
     default:begin size<=96;step<=24;end endcase
    end else state<=10;
   end
   10:begin processing_cycles<=cycles;busy<=0;done<=1;state<=0;end
   default:state<=0;
   endcase
  end
 end
endmodule
