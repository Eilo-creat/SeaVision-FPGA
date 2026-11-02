// V152: independent region tracking, 4x subsampling, two-frame confirmation.
module seavision_pink_tracker #(parameter integer IMG_W=1280,IMG_H=720,
 parameter integer MIN_PIXELS=110,MIN_WIDTH=12,MIN_HEIGHT=12)(
 input wire clk,rst_n,input wire [23:0] rgb,input wire de,user_sof,
 output wire valid_view,output wire [11:0] x0_view,y0_view,x1_view,y1_view);
 wire [5:0] count;
 wire [11:0] x0,y0,x1,y1;wire busy,over;wire [31:0] cycles;
 seavision_pink_stream #(.IMG_W(IMG_W),.IMG_H(IMG_H),.TARGETS(1)) regions(
 .clk(clk),.rst_n(rst_n),.rgb(rgb),.de(de),.user_sof(user_sof),.display_mode(2'b00),
 .count_view(count),.box_x0_view(x0),.box_y0_view(y0),.box_x1_view(x1),.box_y1_view(y1),
 .detector_busy(busy),.detector_overflow(over),.capture_cycles_view(cycles));
 assign valid_view=count!=0;
 assign x0_view=x0<<2;assign y0_view=y0<<2;assign x1_view=x1<<2;assign y1_view=y1<<2;
endmodule
