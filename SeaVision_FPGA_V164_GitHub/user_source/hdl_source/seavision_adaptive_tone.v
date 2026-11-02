module seavision_adaptive_tone #(parameter integer ENABLE_TONE=1)(
 input wire clk,rst_n,input wire [23:0] rgb_base,rgb_b2,
 input wire de_in,hs_in,vs_in,user_in,last_in,input wire tone_enable,pink_mode,
 output wire [23:0] rgb_out,output wire de_out,hs_out,vs_out,user_out,last_out,
 output reg pink_mode_out
);
 wire [23:0] pink_rgb,urchin_rgb;
 seavision_tone_v155 #(.ENABLE_TONE(ENABLE_TONE)) pink(
 .clk(clk),.rst_n(rst_n),.rgb_base(rgb_base),.rgb_b2(rgb_b2),
 .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.user_in(user_in),.last_in(last_in),.tone_enable(tone_enable),
 .rgb_out(pink_rgb),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out),.user_out(user_out),.last_out(last_out));
 seavision_tone_v149 #(.ENABLE_TONE(ENABLE_TONE)) urchin(
 .clk(clk),.rst_n(rst_n),.rgb_base(rgb_base),.rgb_b2(rgb_b2),
 .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.user_in(user_in),.last_in(last_in),.tone_enable(tone_enable),
 .rgb_out(urchin_rgb),.de_out(),.hs_out(),.vs_out(),.user_out(),.last_out());
 always @(posedge clk or negedge rst_n)if(!rst_n)pink_mode_out<=0;else pink_mode_out<=pink_mode;
 assign rgb_out=pink_mode_out?pink_rgb:urchin_rgb;
endmodule

// V151: sensor AE owns exposure. No second digital darkening feedback loop.
// One-cycle video latency retained. Small common RGB lift preserves R-G/B-G.
module seavision_tone_v155 #(parameter integer ENABLE_TONE=1)(
 input wire clk,rst_n,input wire [23:0] rgb_base,rgb_b2,
 input wire de_in,hs_in,vs_in,user_in,last_in,input wire tone_enable,
 output reg [23:0] rgb_out,output reg de_out,hs_out,vs_out,user_out,last_out
);
 wire hi=rgb_b2[23:16]>=248 || rgb_b2[15:8]>=248 || rgb_b2[7:0]>=248;
 function [7:0] blend;
  input [7:0] a,b;input highlight;
  reg [9:0] s;
  begin
   if(highlight)s={2'd0,a}+({2'd0,a}<<1)+{2'd0,b};
   else s={2'd0,a}+{2'd0,b}+({2'd0,b}<<1);
   blend=s[9:2];
  end
 endfunction
 wire [7:0] r=blend(rgb_base[23:16],rgb_b2[23:16],hi);
 wire [7:0] g=blend(rgb_base[15:8],rgb_b2[15:8],hi);
 wire [7:0] b=blend(rgb_base[7:0],rgb_b2[7:0],hi);
 wire [7:0] rgmax=r>g?r:g;
 wire [7:0] peak=rgmax>b?rgmax:b;
 wire [7:0] headroom=255-peak;
 wire [7:0] lift=(peak>>4)<(headroom>>4)?(peak>>4):(headroom>>4);
 wire [7:0] lifted_r=r+lift,lifted_g=g+lift,lifted_b=b+lift;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;user_out<=0;last_out<=0;end
  else begin
   rgb_out<=(tone_enable && ENABLE_TONE!=0)?{lifted_r,lifted_g,lifted_b}:rgb_b2;
   de_out<=de_in;hs_out<=hs_in;vs_out<=vs_in;user_out<=user_in;last_out<=last_in;
  end
 end
endmodule

// SeaVision V1.3 - video-rate automatic DIGITAL tone control.
// No sensor exposure registers are modified.  B2 + official ISP AWB remain.
// Two goals: avoid pushing already bright channels to 255; adapt slowly
// (one small correction step per frame). Latency: exactly one pixel clock.
module seavision_tone_v149 #(
    parameter integer ENABLE_TONE = 1
)(
    input wire clk, rst_n,
    input wire [23:0] rgb_base, rgb_b2,
    input wire de_in, hs_in, vs_in, user_in, last_in,
    input wire tone_enable,
    output reg [23:0] rgb_out,
    output reg de_out, hs_out, vs_out, user_out, last_out
);
    reg [6:0] sample_div;
    reg [7:0] avg_y;
    reg [7:0] frame_avg;
    reg signed [6:0] exposure_step; // Q0: -32..+8 digital offset, NOT sensor exposure
    reg [13:0] valid_samples, clipped_samples;
    reg [13:0] clipped_previous;
    wire [7:0] r_b2=rgb_b2[23:16],g_b2=rgb_b2[15:8],b_b2=rgb_b2[7:0];
    wire is_clipped=(r_b2>=8'd248 || g_b2>=8'd248 || b_b2>=8'd248);
    wire [9:0] luma_sum = {2'b0,rgb_b2[23:16]} +
        ({2'b0,rgb_b2[15:8]} << 1) + {2'b0,rgb_b2[7:0]};
    wire [7:0] y_in = luma_sum[9:2];
    wire signed [9:0] avg_delta = $signed({2'b00,y_in}) - $signed({2'b00,avg_y});
    // The small EMA step never gets stuck at +/-15 because of truncation.
    wire signed [9:0] ema_step = (avg_delta > 0) ?
        ((avg_delta >>> 4) > 0 ? (avg_delta >>> 4) : 10'sd1) :
        ((avg_delta < 0) ? ((avg_delta >>> 4) < 0 ? (avg_delta >>> 4) : -10'sd1) : 10'sd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_div <= 0;
            avg_y <= 8'd128;
            frame_avg <= 8'd128;
            exposure_step <= 0;
            valid_samples<=0;clipped_samples<=0;clipped_previous<=0;
        end else begin
            if (user_in) begin
                frame_avg<=avg_y;
                clipped_previous<=clipped_samples;
                // SOF sample belongs to the NEW frame; old totals still drive exposure.
                valid_samples<=(de_in && sample_div==0)?14'd1:14'd0;
                clipped_samples<=(de_in && sample_div==0 && is_clipped)?14'd1:14'd0;
                // Overexposed sampled channels have priority over mean luminance.
                // Trigger if > 1/32 valid samples have any channel >=248.
                // One LSB per frame, with bounded offset and no DSP/divider.
                if ((valid_samples>=14'd64 && clipped_samples>(valid_samples>>5)) ||
                    avg_y>8'd180) begin
                    if(exposure_step> -7'sd32) exposure_step<=exposure_step-7'sd1;
                end else if (avg_y<8'd77) begin
                    if(exposure_step<7'sd8) exposure_step<=exposure_step+7'sd1;
                end else if (avg_y>=8'd105 && avg_y<=8'd165) begin
                    if(exposure_step>0)exposure_step<=exposure_step-7'sd1;
                    else if(exposure_step<0)exposure_step<=exposure_step+7'sd1;
                end
            end
            if (de_in) begin
                sample_div <= sample_div + 7'd1;
                if (sample_div == 7'd0) begin
                    avg_y <= avg_y + ema_step;
                    if(!user_in && valid_samples<14'd16383)valid_samples<=valid_samples+1'b1;
                    if(!user_in && is_clipped && clipped_samples<14'd16383)
                        clipped_samples<=clipped_samples+1'b1;
                end // 8-bit modulo safe: EMA stays [0,255]
            end
        end
    end

    // A bounded weighted blend. B2 is weakened for highlight-heavy images:
    // bright -> 1/4 B2; other -> 3/4 B2. No 3-channel multiplier or divide.
    wire bright_scene = (frame_avg > 8'd159) || (y_in > 8'd210);
    function [7:0] weighted;
        input [7:0] a,b;
        input hi;
        reg [9:0] s;
        begin
            if (hi) s = {2'b0,a} + ({2'b0,a} << 1) + {2'b0,b};
            else    s = {2'b0,a} + {2'b0,b} + ({2'b0,b} << 1);
            weighted = s[9:2];
        end
    endfunction
    // Shoulder compresses highlights from 208..255 into 208..231, without
    // raising the highlights. It cannot recover already clipped sensor input. Lost sensor clipping cannot be reconstructed.
    function [7:0] protect;
        input [7:0] v;
        input signed [6:0] offset;
        reg signed [10:0] t;
        reg [7:0] c;
        begin
            t = $signed({3'b000,v}) + offset;
            if (t < 0) c = 8'd0;
            else if (t > 255) c = 8'd255;
            else c = t[7:0];
            protect = (c > 8'd208) ? (8'd208 + ((c-8'd208) >> 1)) : c;
        end
    endfunction
    wire [7:0] br = weighted(rgb_base[23:16],rgb_b2[23:16],bright_scene);
    wire [7:0] bg = weighted(rgb_base[15:8], rgb_b2[15:8], bright_scene);
    wire [7:0] bb = weighted(rgb_base[7:0],  rgb_b2[7:0],  bright_scene);
    wire [23:0] protected_rgb = {protect(br,exposure_step),
                                  protect(bg,exposure_step),
                                  protect(bb,exposure_step)};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0;de_out<=0;hs_out<=0;vs_out<=0;user_out<=0;last_out<=0;
        end else begin
            rgb_out <= (tone_enable && ENABLE_TONE != 0) ? protected_rgb : rgb_b2;
            de_out<=de_in;hs_out<=hs_in;vs_out<=vs_in;user_out<=user_in;last_out<=last_in;
        end
    end
endmodule
