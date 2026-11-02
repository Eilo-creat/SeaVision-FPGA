// SeaVision FPGA v1.1 - DDR RGB-to-HDMI pixel bridge with selectable B2 white balance.
// The DDR read request is intentionally NOT generated here. It must stay
// connected directly to the original undelayed VTC DE in design_top_wrapper.
// Pipeline depth 7 matches b2_white_balance.sv (RGB and DE/HS/VS).
module seavision_b2_video_bridge #(
    parameter integer USE_FULL_B2 = 1
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire [23:0] I_rgb,
    input wire I_de,
    input wire I_hs,
    input wire I_vs,
    input wire I_user,
    input wire I_last,
    input wire [1:0] I_video_mode,
    input wire I_wb_enable_sw,
    input wire I_pink_mode,output wire O_pink_mode,
    output wire [23:0] O_rgb,
    output wire O_de,
    output wire O_hs,
    output wire O_vs,
    output wire O_user,
    output wire O_last
);
    // Asynchronous mechanical switches are synchronized to HDMI pixel clk.
    reg [2:0] mode_meta, mode_sync;
    reg frame_wb_enabled;
    reg [6:0] wb_en_shift;
    reg [6:0] profile_shift;
    reg [6:0] de_shift, hs_shift, vs_shift, user_shift, last_shift;
    reg [23:0] rgb_shift[0:6];
    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mode_meta <= 3'b000;
            mode_sync <= 3'b000;
            frame_wb_enabled <= 1'b0;
            wb_en_shift <= 7'd0;profile_shift<=0;
            de_shift <= 7'd0;
            hs_shift <= 7'd0;
            vs_shift <= 7'd0;
            user_shift <= 7'd0;
            last_shift <= 7'd0;
            for(i=0;i<7;i=i+1) rgb_shift[i] <= 24'd0;
        end else begin
            mode_meta <= {I_wb_enable_sw,I_video_mode};
            mode_sync <= mode_meta;
            // Switches are sampled only at frame start; no mid-frame color flip.
            // The first frame after changing SW3 may still use old setting.
            if(I_user)
                frame_wb_enabled <= mode_sync[2] && (mode_sync[1:0] == 2'b00);
            wb_en_shift <= {wb_en_shift[5:0],frame_wb_enabled};
            profile_shift<={profile_shift[5:0],I_pink_mode};
            de_shift <= {de_shift[5:0],I_de};
            hs_shift <= {hs_shift[5:0],I_hs};
            vs_shift <= {vs_shift[5:0],I_vs};
            user_shift <= {user_shift[5:0],I_user};
            last_shift <= {last_shift[5:0],I_last};
            rgb_shift[0] <= I_rgb;
            for(i=1;i<7;i=i+1) rgb_shift[i] <= rgb_shift[i-1];
        end
    end
    // All outputs pass through the one-cycle adaptive tone stage; the input
    // DDR request remains connected to the original timing in the top module.
    wire [23:0] selected_rgb = wb_en_shift[6] ? enhanced_rgb : rgb_shift[6];
    wire selected_valid = de_shift[6];
    seavision_adaptive_tone #(.ENABLE_TONE(1)) u_tone (
        .clk(I_clk), .rst_n(I_rst_n),
        .rgb_base(rgb_shift[6]), .rgb_b2(selected_rgb),
        .de_in(de_shift[6]), .hs_in(hs_shift[6]), .vs_in(vs_shift[6]),
        .user_in(user_shift[6]), .last_in(last_shift[6]),
        .tone_enable(wb_en_shift[6]),.pink_mode(profile_shift[6]),.pink_mode_out(O_pink_mode),
        .rgb_out(O_rgb), .de_out(O_de), .hs_out(O_hs),
        .vs_out(O_vs), .user_out(O_user), .last_out(O_last)
    );

    wire [23:0] enhanced_rgb;
    generate if(USE_FULL_B2 != 0) begin: g_full_b2
        // Original B2 from user-supplied algorithm package, used unmodified.
        wire ready, late;
        b2_white_balance #(
            .WIDTH(1280), .HEIGHT(720), .VS_ACTIVE_HIGH(1'b1)
        ) u_b2_white_balance (
            .clk(I_clk), .rst_n(I_rst_n),
            .rgb_in(I_rgb), .de_in(I_de), .hs_in(I_hs), .vs_in(I_vs),
            .rgb_out(enhanced_rgb), .de_out(), .hs_out(), .vs_out(),
            .init_done(ready), .stats_late(late)
        );
    end else begin: g_simple_fallback
        // FALLBACK ONLY: fixed-gain RGB correction (NOT automatic white balance).
        // Low resource use when full B2 exceeds FPGA resources/timing.
        reg [23:0] gain_rgb;
        reg [8:0] red_boost;
        reg [7:0] blue_reduce;
        reg [23:0] gain_shift[0:6];
        integer j;
        always @(*) begin
            red_boost = {1'b0,I_rgb[23:16]} + {1'b0,(I_rgb[23:16] >> 1)};
            blue_reduce = I_rgb[7:0] - (I_rgb[7:0] >> 2);
            gain_rgb = {(red_boost > 9'd255) ? 8'hff : red_boost[7:0],
                        I_rgb[15:8],blue_reduce};
        end
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n)
                for(j=0;j<7;j=j+1) gain_shift[j] <= 24'd0;
            else begin
                gain_shift[0] <= gain_rgb;
                for(j=1;j<7;j=j+1) gain_shift[j] <= gain_shift[j-1];
            end
        end
        assign enhanced_rgb = gain_shift[6];
    end endgenerate

endmodule
