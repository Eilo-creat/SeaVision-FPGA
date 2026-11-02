// V150: PRE-enhancement RGB; command held throughout toggle/ack CDC handshake.
module seavision_exposure_meter #(parameter integer W=1280,H=720,UPDATE_FRAMES=4)(
 input wire pixel_clk,pixel_rst_n,input wire [23:0] rgb,input wire de,sof,
 input wire ctrl_clk,ctrl_rst_n,output reg command_valid,output reg [1:0] command
);
 reg [11:0] x,y;
 reg [19:0] n,clipped;
 reg [27:0] total;
 reg [7:0] frames;
 reg seen_frame,request_toggle,ack_toggle;
 reg [1:0] held_command;
 (* async_reg="true" *) reg ack_meta,ack_sync,req_meta,req_sync;
 reg req_seen;
 wire [7:0] lum=(rgb[23:16]>>2)+(rgb[15:8]>>1)+(rgb[7:0]>>2);
 wire clip_pixel=rgb[23:16]>=250 && rgb[15:8]>=250 && rgb[7:0]>=250;
 wire sample=de && x[3:0]==0 && y[3:0]==0 && x>=20 && x<W-20 && y>=128 && y<H-20;
 wire [27:0] n28={8'd0,n};
 wire [27:0] mean_hi=(n28<<7)+(n28<<6); // 192, bright normal target
 wire [27:0] mean_very_hi=(n28<<7)+(n28<<6)+(n28<<4); // 208
 wire [27:0] mean_lo=(n28<<7)+(n28<<4); // 144, lift dim scenes
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin
   x<=0;y<=0;n<=0;clipped<=0;total<=0;frames<=0;seen_frame<=0;
   request_toggle<=0;held_command<=0;ack_meta<=0;ack_sync<=0;
  end else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   if(sof)begin
    x<=de?1:0;y<=0;n<=0;clipped<=0;total<=0;seen_frame<=1;
    if(seen_frame && n>=128)begin
     if(frames==UPDATE_FRAMES-1)begin
      if(request_toggle==ack_sync)begin
       // Small specular highlights and saturated pink must not darken the scene.
       if(clipped>(n>>2) && total>mean_hi)held_command<=3;
       else if(total>mean_very_hi || (clipped>(n>>3) && total>mean_hi))held_command<=1;
       else if(total<mean_lo && clipped<=(n>>3))held_command<=2;
       else held_command<=0;
       request_toggle<=~request_toggle;frames<=0;
      end
     end else frames<=frames+1'b1;
    end
   end else if(de)begin
    if(sample)begin n<=n+1'b1;total<=total+lum;if(clip_pixel)clipped<=clipped+1'b1;end
    if(x==W-1)begin x<=0;y<=y==H-1?0:y+1'b1;end else x<=x+1'b1;
   end
  end
 end
 always @(posedge ctrl_clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin req_meta<=0;req_sync<=0;req_seen<=0;ack_toggle<=0;command_valid<=0;command<=0;end
  else begin
   req_meta<=request_toggle;req_sync<=req_meta;command_valid<=0;
   if(req_sync!=req_seen)begin
    command<=held_command;command_valid<=1;req_seen<=req_sync;ack_toggle<=req_sync;
   end
  end
 end
endmodule
