// SeaVision 1.3.4: passive, resource-bounded candidate detector tap.
// Does not modify RGB pixels or sync, does not add video cycles.
// Detector coordinates 320x180, display metadata 1280x720 after 4x scaling.
// Only simple dark blob candidates, not trained recognition or sea cucumber.
module seavision_urchin_stream_tap #(
    parameter integer IMG_W=1280, IMG_H=720, STRIDE=4, TARGETS=4,
    parameter integer REQUIRE_SINGLE_REPEAT=1
)(
    input wire clk, rst_n,
    input wire [23:0] rgb,
    input wire de, user_sof,
    input wire [1:0] display_mode,
    output reg [5:0] count_view,
    output reg [TARGETS*12-1:0] box_x0_view,box_y0_view,box_x1_view,box_y1_view,
    output wire detector_busy, detector_overflow,
    output reg [31:0] capture_cycles_view,
    output reg [15:0] svm_margin_view
);
    reg [11:0] px,py;
    // Count active pixels; avoid depending on LAST, which may be delayed past DE.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin px<=0;py<=0;end
        else if(user_sof)begin px<=de?12'd1:12'd0;py<=0;end
        else if(de)begin
            if(px==IMG_W-1)begin px<=0;py<=py==IMG_H-1 ? 12'd0:py+12'd1;end
            else px<=px+12'd1;
        end
    end
    // display_mode retained as a compatibility input; source sampling never stalls.
    wire raw_mode=(display_mode==2'b00);
    wire sample_here=de && px[1:0]==2'b00 && py[1:0]==2'b00;
    // SOF is generated at the first active pixel by the supplied uivtc.
    // Use SOF itself to start a capture; relying on a second independent
    // coordinate condition may be fragile if there is any phase mismatch.
    wire ready,cap,busy,done,over;
    reg capturing_this_frame;
    wire begin_capture=user_sof && de && ready; // never pause acquisition on switch changes
    // Forward the SOF pixel even if the counter's old value is not (0,0).
    // The target detector needs simultaneous in_valid and in_sof.
    wire sample_valid=(sample_here || begin_capture) &&
                      (capturing_this_frame || begin_capture);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)capturing_this_frame<=0;
        else begin
            if(user_sof)capturing_this_frame<=0;
            if(begin_capture)capturing_this_frame<=1;
            // The last downsampled pixel is at x=1276, y=716.
            if(sample_valid && px==IMG_W-STRIDE && py==IMG_H-STRIDE)
                capturing_this_frame<=0;
        end
    end
    wire [5:0] count_raw;
    wire [TARGETS*12-1:0] b0x,b0y,b1x,b1y,cx,cy;
    wire [31:0] cycles_raw;
    wire [15:0] svm_margin_raw;
    reg [15:0] svm_margin_pending;
    reg [31:0] cycles_pending;
    wire [7:0] th0_unused,th1_unused,th2_unused;
    seavision_urchin_detector_lite #(
      .W(IMG_W/STRIDE),.H(IMG_H/STRIDE),.TARGETS(TARGETS),
      .MAX_RUNS(10),.MAX_BLOBS(20),.MIN_PIXELS(22),.MAX_CHROMA(118)
    ) detector (
      .clk(clk),.rst_n(rst_n),.in_valid(sample_valid),
      .in_sof(begin_capture),.in_rgb(rgb),.ready(ready),
      .capturing(cap),.busy(busy),.done(done),.overflow(over),
      .count(count_raw),.center_x(cx),.center_y(cy),
      .box_x0(b0x),.box_y0(b0y),.box_x1(b1x),.box_y1(b1y),
      .processing_cycles(cycles_raw),
      .first_svm_margin(svm_margin_raw),
      .threshold0(th0_unused),.threshold1(th1_unused),.threshold2(th2_unused)
    );
    assign detector_busy=busy|cap;
    assign detector_overflow=over;
    // Optional two-frame persistence for a SINGLE candidate.  Removes
    // one-frame black specks without changing the underlying classifier.
    // Persistent black rocks are not solved by temporal confirmation.
    reg last_one;
    reg [11:0] last_cx,last_cy;
    wire [11:0] now_cx=cx[11:0], now_cy=cy[11:0];
    wire close_x=(now_cx+12'd12>=last_cx && last_cx+12'd12>=now_cx);
    wire close_y=(now_cy+12'd12>=last_cy && last_cy+12'd12>=now_cy);
    wire single_confirmed=last_one && close_x && close_y;
    reg pending_valid;
    reg [5:0] pending_count;
    reg [TARGETS*12-1:0] p0x,p0y,p1x,p1y;
    // Metadata latched on next frame, so rectangles never move mid-frame.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            pending_valid<=0;pending_count<=0;count_view<=0;
            last_one<=0;last_cx<=0;last_cy<=0;
            cycles_pending<=0;capture_cycles_view<=0;
            svm_margin_pending<=0;svm_margin_view<=0;
            p0x<=0;p0y<=0;p1x<=0;p1y<=0;
            box_x0_view<=0;box_y0_view<=0;box_x1_view<=0;box_y1_view<=0;
        end else begin
            // Publish the previous result first. A simultaneous completion
            // must retain the NEW pending result for the following frame.
            if(user_sof && pending_valid)begin
                pending_valid<=0;
                count_view<=pending_count;
                capture_cycles_view<=cycles_pending;
                svm_margin_view<=svm_margin_pending;
                box_x0_view<=p0x;box_y0_view<=p0y;
                box_x1_view<=p1x;box_y1_view<=p1y;
            end
            if(done)begin
                pending_valid<=1;
                if(REQUIRE_SINGLE_REPEAT!=0 && count_raw==6'd1 && !single_confirmed)
                    pending_count<=0;
                else pending_count<=count_raw;
                last_one<=(count_raw==6'd1);
                if(count_raw==6'd1)begin last_cx<=now_cx;last_cy<=now_cy;end
                cycles_pending<=cycles_raw;
                // Align with pending_count and two-frame single-target filter.
                if(REQUIRE_SINGLE_REPEAT!=0 && count_raw==6'd1 && !single_confirmed)
                    svm_margin_pending<=0;
                else if(count_raw!=0)svm_margin_pending<=svm_margin_raw;
                else svm_margin_pending<=0;
                p0x<=b0x;p0y<=b0y;p1x<=b1x;p1y<=b1y;
            end

        end
    end
endmodule
