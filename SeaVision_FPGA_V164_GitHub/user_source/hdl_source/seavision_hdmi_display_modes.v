// SeaVision V1.5.7 - HDMI-only video effects.  The detector input must be
// connected BEFORE this block.  No DDR reconfiguration or sensor-ISP switching.
// Mode 00: RGB, 01: 3x3 Sobel white edges, 10: gray, 11: binary.
// Grayscale (R>>2)+(G>>1)+(B>>2) and binary threshold 110 are taken
// from the original V1.4.4 SC520 isp_top algorithm.
// The streaming Sobel has the same 3x3 kernel/threshold (80) as V1.4.4,
// but operates on one pixel per HDMI beat instead of two pixels per pair.
// It is an equivalent class of filter, not bit-exact to the 4-pixel ISP path.
// It uses two 1280x8 line memories.  Border pixels remain black.
// Output is COMBINATIONAL from current RGB and registered Sobel taps.
// No added output-clock delay: hdmi_mixer keeps its original pixel/OSD timing.
module seavision_hdmi_display_modes #(
    parameter integer IMG_WIDTH = 1280,
    parameter [11:0] EDGE_TH = 12'd80
)(
    input wire clk,
    input wire rst_n,
    input wire [23:0] rgb_in,
    input wire de_in,
    input wire sof_in,
    input wire [1:0] mode_in,
    output reg [23:0] rgb_out
);
    wire [7:0] y_now = {2'b0,rgb_in[23:18]}
                       + {1'b0,rgb_in[15:9]}
                       + {2'b0,rgb_in[7:2]};
    wire [23:0] gray_now = {y_now,y_now,y_now};
    wire [23:0] binary_now = (y_now>=8'd110) ? 24'hffffff : 24'h000000;
    // Synchronous read-before-write line memories; no reset fan-out to RAM.
    (* ram_style="block" *) reg [7:0] line_mid[0:IMG_WIDTH-1];
    (* ram_style="block" *) reg [7:0] line_top[0:IMG_WIDTH-1];
    reg [10:0] x;
    reg [10:0] y;
    reg [7:0] top_q,mid_q,bot_q;
    reg [7:0] top_prev1,top_prev2,mid_prev1,mid_prev2,bot_prev1,bot_prev2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0;y<=0;
            top_q<=0;mid_q<=0;bot_q<=0;
            top_prev1<=0;top_prev2<=0;
            mid_prev1<=0;mid_prev2<=0;
            bot_prev1<=0;bot_prev2<=0;
        end else if (de_in) begin
            // All three q registers refer to the SAME incoming column
            // one cycle after sampling, so the three Sobel rows stay aligned.
            top_q <= line_top[x];
            mid_q <= line_mid[x];
            bot_q <= y_now;
            line_top[x] <= line_mid[x];
            line_mid[x] <= y_now;
            top_prev2 <= top_prev1; top_prev1 <= top_q;
            mid_prev2 <= mid_prev1; mid_prev1 <= mid_q;
            bot_prev2 <= bot_prev1; bot_prev1 <= bot_q;
            if (sof_in) begin
                // First active pixel is x=0,y=0 in the input video timing.
                x <= 11'd1;
                y <= 11'd0;
            end else if (x == IMG_WIDTH-1) begin
                x <= 11'd0;
                if (y==11'd719) y<=11'd0;
                else y<=y+1'b1;
            end else x<=x+1'b1;
        end
    end
    function [11:0] sobel_magnitude;
        input [7:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
        reg signed [11:0] gx,gy;
        reg [11:0] ax,ay;
        begin
            gx= -$signed({1'b0,a00}) + $signed({1'b0,a02})
                -($signed({1'b0,a10})<<<1) + ($signed({1'b0,a12})<<<1)
                -$signed({1'b0,a20}) + $signed({1'b0,a22});
            gy= $signed({1'b0,a00}) + ($signed({1'b0,a01})<<<1)
                +$signed({1'b0,a02}) -$signed({1'b0,a20})
                -($signed({1'b0,a21})<<<1)-$signed({1'b0,a22});
            ax=gx[11]? -gx : gx;
            ay=gy[11]? -gy : gy;
            sobel_magnitude=ax+ay;
        end
    endfunction
    wire [11:0] mag=sobel_magnitude(
         top_prev2,top_prev1,top_q,
         mid_prev2,mid_prev1,mid_q,
         bot_prev2,bot_prev1,bot_q);
    // One-sample horizontal filter phase is a visual-only effect; metadata
    // and true RGB detection input remain pixel-aligned with the original stream.
    wire [23:0] edge_now=(x>=11'd3 && y>=11'd2 && mag>=EDGE_TH)
                         ?24'hffffff:24'h000000;
    always @(*) begin
        case(mode_in)
        2'b01:rgb_out=edge_now;
        2'b10:rgb_out=gray_now;
        2'b11:rgb_out=binary_now;
        default:rgb_out=rgb_in;
        endcase
    end
endmodule
