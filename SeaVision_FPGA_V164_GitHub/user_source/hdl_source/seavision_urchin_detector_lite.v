// SeaVision V1.3.2 - resource-bounded adjacent-line RLE urchin CANDIDATE detector.
// Based on the threshold, morphology and connected-region concepts of the
// user-supplied underwater_fpga_v1_8 (NOT a literal copy of its huge engine).
// One pixel per in_valid; in_sof marks first (0,0) sample in a W*H raster.
// No full-frame image RAM, variable division, union-find ROM, or dynamic
// 2-D pixel arrays. The approximate RLE linker cannot resolve every split,
// join or complicated background. This IS NOT a marine species classifier.
//
// Unlike V1.3.1's 4 giant vertical stripes, separate runs/objects can be
// tracked inside the same stripe. Adjacent-row overlap links run segments.
// 2-pixel horizontal gaps are bridged (small 1-D closing); runs shorter
// than 3 dark pixels or without a strong dark seed are rejected.
module seavision_urchin_detector_lite #(
    parameter integer W=320,
    parameter integer H=180,
    parameter integer TARGETS=4,
    parameter integer MAX_RUNS=12,
    parameter integer MAX_BLOBS=24,
    parameter integer MIN_PIXELS=100,
    parameter integer MAX_CHROMA=105,
    parameter integer ENABLE_TINY_SVM=1, parameter integer STRICT_DEMO_FILTER=1
)(
    input wire clk,rst_n,
    input wire in_valid,in_sof,input wire [23:0] in_rgb,
    output wire ready,capturing,
    output reg busy,done,overflow,
    output reg [5:0] count,
    output reg [TARGETS*12-1:0] center_x,center_y,
    output reg [TARGETS*12-1:0] box_x0,box_y0,box_x1,box_y1,
    output reg [31:0] processing_cycles,
    // First confirmed candidate's positive SVM margin, clamped to 9999.
    // Margin is NOT a calibrated probability or classification accuracy.
    output reg [15:0] first_svm_margin,
    output wire [7:0] threshold0,threshold1,threshold2
);
    localparam integer BIW=$clog2(MAX_BLOBS+1);
    localparam integer RIW=$clog2(MAX_RUNS+1);
    localparam [2:0] ST_WAIT=0,ST_FRAME=1,ST_FLUSH=2,
                     ST_SWAP=3,ST_EVAL=4,ST_DONE=5;
    reg [2:0] state;
    reg [9:0] pix_x,pix_y;
    reg [BIW-1:0] next_blob;
    reg [BIW-1:0] eval_idx;
    reg [RIW-1:0] prev_n,curr_n;
    reg [9:0] prev_x0[0:MAX_RUNS-1],prev_x1[0:MAX_RUNS-1];
    reg [BIW-1:0] prev_id[0:MAX_RUNS-1];
    reg [9:0] curr_x0[0:MAX_RUNS-1],curr_x1[0:MAX_RUNS-1];
    reg [BIW-1:0] curr_id[0:MAX_RUNS-1];
    reg [15:0] blob_pixels[0:MAX_BLOBS-1];
    // Spike-like contour roughness: sum of left/right RLE boundary changes
    // between adjacent rows of the same blob. One accumulator per blob.
    reg [15:0] blob_rough[0:MAX_BLOBS-1];
    reg [9:0] blob_x0[0:MAX_BLOBS-1],blob_x1[0:MAX_BLOBS-1];
    reg [9:0] blob_y0[0:MAX_BLOBS-1],blob_y1[0:MAX_BLOBS-1];
    reg run_open;
    reg [9:0] run_x0,run_x1;
    reg [9:0] run_pixels;
    reg [1:0] gap;
    reg run_strong;
    reg [31:0] run_cycles;
    integer i,j;

    assign ready=(state==ST_WAIT);
    assign capturing=(state==ST_FRAME || state==ST_FLUSH || state==ST_SWAP);
    wire [7:0] red=in_rgb[23:16],green=in_rgb[15:8],blue=in_rgb[7:0];
    // Cheap 8-bit luminance and on-line mean tracking, no multipliers.
    wire [7:0] lum=(red>>2)+(green>>1)+(blue>>2);
    reg [15:0] avg_q8;
    wire signed [17:0] mean_delta=$signed({2'b00,lum,8'b0})-
                                   $signed({2'b00,avg_q8});
    wire [7:0] avg_lum=avg_q8[15:8];
    // Threshold about 0.56*mean, to reject large gray seabed regions.
    // The previous ~0.69*mean threshold tended to merge background into blobs.
    wire [8:0] th_unclamped={1'b0,(avg_lum>>1)}+
                              {1'b0,(avg_lum>>4)};
    wire [7:0] adaptive_th=th_unclamped<9'd28 ? 8'd28 :
                            th_unclamped>9'd125 ? 8'd125 : th_unclamped[7:0];
    assign threshold1=adaptive_th;
    assign threshold0=adaptive_th>8'd8 ? adaptive_th-8'd8:8'd0;
    assign threshold2=adaptive_th<8'd237 ? adaptive_th+8'd18:8'd255;
    wire [7:0] rg_hi=(red>green)?red:green;
    wire [7:0] rg_lo=(red<green)?red:green;
    wire [7:0] hi=(rg_hi>blue)?rg_hi:blue;
    wire [7:0] lo=(rg_lo<blue)?rg_lo:blue;
    wire dark=(pix_x>=78 && pix_x<=242 && pix_y>=31 && pix_y<=149 &&
               lum<adaptive_th && ({1'b0,hi}-{1'b0,lo})<MAX_CHROMA);
    wire strong=lum<threshold0;

    // Only finish one run at a time. Incoming sample clock is 4x subsampled;
    // a full horizontal line boundary is followed by ample non-sample cycles.
    wire close_on_gap=(state==ST_FRAME && in_valid && !dark &&
                       run_open && gap==2);
    wire close_on_end=(state==ST_FLUSH && run_open);
    wire finish_run=close_on_gap || close_on_end;
    // Adjacent-line link: associate current run with first overlapping
    // previous-row run. No variable depth searches / parent pointers.
    reg matched;
    reg [BIW-1:0] matched_id;
    reg [9:0] matched_left,matched_right;
    integer k;
    always @* begin
        matched=1'b0;
        matched_id={BIW{1'b0}};
        matched_left=0; matched_right=0;
        for(k=0;k<MAX_RUNS;k=k+1)begin
            if(!matched && k<prev_n &&
               ({1'b0,run_x0}<={1'b0,prev_x1[k]}+11'd3) &&
               ({1'b0,prev_x0[k]}<={1'b0,run_x1}+11'd3))begin
                matched=1'b1;
                matched_id=prev_id[k];
                matched_left=prev_x0[k];
                matched_right=prev_x1[k];
            end
        end
    end
    wire [10:0] dl = (run_x0>=matched_left) ? ({1'b0,run_x0}-{1'b0,matched_left}) : ({1'b0,matched_left}-{1'b0,run_x0});
    wire [10:0] dr = (run_x1>=matched_right) ? ({1'b0,run_x1}-{1'b0,matched_right}) : ({1'b0,matched_right}-{1'b0,run_x1});
    wire [11:0] rough_add = dl+dr;
    wire run_usable=(run_pixels>=10'd3 && run_strong);
    wire [BIW-1:0] use_id=matched?matched_id:next_blob;
    wire new_blob=run_usable && !matched && (next_blob<MAX_BLOBS);
    wire can_link=run_usable && (matched || new_blob);
    // Unallocated entries are never consumed. new_blob initializes every field.
    // Separate reset-free table allows memory inference and removes frame-wide reset fanout.
    wire [BIW-1:0] blob_read_addr = (state==ST_EVAL) ? eval_idx : use_id;
    wire [15:0] blob_pixels_read = blob_pixels[blob_read_addr];
    wire [15:0] blob_rough_read = blob_rough[blob_read_addr];
    wire [9:0] blob_x0_read = blob_x0[blob_read_addr];
    wire [9:0] blob_x1_read = blob_x1[blob_read_addr];
    wire [9:0] blob_y0_read = blob_y0[blob_read_addr];
    wire [9:0] blob_y1_read = blob_y1[blob_read_addr];
    always @(posedge clk) begin
        if(rst_n && finish_run && can_link) begin
                    if(new_blob)begin
                        blob_pixels[use_id]<=run_pixels;
                        blob_rough[use_id]<=0;
                        blob_x0[use_id]<=run_x0;blob_x1[use_id]<=run_x1;
                        blob_y0[use_id]<=pix_y;blob_y1[use_id]<=pix_y;

                    end else begin
                        blob_pixels[use_id]<=blob_pixels_read+run_pixels;
                        blob_rough[use_id]<=blob_rough_read+rough_add;
                        if(run_x0<blob_x0_read)blob_x0[use_id]<=run_x0;
                        if(run_x1>blob_x1_read)blob_x1[use_id]<=run_x1;
                        if(pix_y<blob_y0_read)blob_y0[use_id]<=pix_y;
                        if(pix_y>blob_y1_read)blob_y1[use_id]<=pix_y;
                    end
        end
    end
    // V149: seven-cycle per-blob evaluation. Tables are frozen at frame end.
    // Break table mux -> dimensions -> multiply -> compare -> output path.
    // Numeric widths and all acceptance rules are unchanged from V148.
    reg [2:0] eval_phase;
    reg [15:0] ev_pixels,ev_rough;
    reg [9:0] ev_x0,ev_x1,ev_y0,ev_y1;
    reg qualified_q;
    // Shared multiplier is used only for GEOMETRY evaluation, not for pixels.
    reg [10:0] bw;
    reg [10:0] bh;
    reg [21:0] bbox_area;
    wire [18:0] occupancy={3'b0,ev_pixels}<<2;
    // Low-cost multi-feature rule: area, bounding size, aspect and solidity.
    // Old rule accepted tiny black marks and fully black rectangles; this update rejects those while preserving ratios up to 2:1 observed on the user sample photos.
    // Dark rectangles (near 100% filled) are now rejected. These are only
    // heuristic SEA-URCHIN CANDIDATES, not species classification.
    wire [22:0] pixels_x16={3'd0,ev_pixels,4'd0};
    wire [22:0] area_x5={1'd0,bbox_area,2'd0}+{1'd0,bbox_area};
    wire [22:0] area_x14={1'd0,bbox_area,3'd0}+{1'd0,bbox_area,2'd0}+
                         {1'd0,bbox_area,1'd0};
    // Offline 8-sample prototype LinearSVC weights (scale~1e4):
    // [rough, span, symmetry_gap, dark_pixels] => [19, 13, -189, 2], b=-1121
    // NOT a validated real-world classifier; for controlled experimental use.
    reg [11:0] span;
    reg [10:0] asym;
    // DSP-conscious EXACT shift/add implementation of the V1.3.9 prototype
    // 19=16+2+1; 13=8+4+1; 189=128+64-2-1.
    // No '*' in the SVM itself; this is NOT the PC 15D model.
    wire [31:0] rough32={16'd0,ev_rough};
    wire [31:0] span32={20'd0,span};
    wire [31:0] asym32={21'd0,asym};
    wire [31:0] pixels32={16'd0,ev_pixels};
    reg [31:0] rough_term,span_term,pixel_term;
    reg [31:0] svm_positive,svm_negative;
    wire svm_pass = (ENABLE_TINY_SVM==0) || (svm_positive>=svm_negative);
    // Read the existing positive/negative integer terms. The weights and
    // decision threshold are unchanged. Only valid candidate #0 is exported.
    wire [31:0] svm_margin_raw=svm_positive-svm_negative;
    // Only exported diagnostic width changes; SVM decision stays untouched.
    wire [15:0] svm_margin_clamped=(svm_margin_raw>32'd65535) ?
                                   16'd65535 : svm_margin_raw[15:0];
    // Optional PC-guided conservative demo gate, not a port of the 15D PC SVM.
    // Avoid dense dark rectangles/tools, small dots, and very large shadow blobs.
    wire [23:0] area_triple={2'd0,bbox_area,1'b0}+{2'd0,bbox_area};
    wire [23:0] pixel_quad={6'd0,ev_pixels,2'b0};
    wire conservative_demo=(STRICT_DEMO_FILTER==0) ||
        ((ev_pixels>=16'd50) &&
         (pixel_quad<=area_triple) && // fill <= 75 percent
         (bw<=W/3) && (bh<=H/2) &&
         (ev_rough>=(span>>2)));
    wire roi_inside=(ev_x0>=82 && ev_x1<=238 && ev_y0>=35 && ev_y1<=145);
    wire qualified=roi_inside && conservative_demo && svm_pass && (ev_pixels>=MIN_PIXELS) &&
          bw>=26 && bh>=17 && bw<=W/2 && bh<=(H*2)/3 &&
          (bw <= (bh<<1)) && (bh <= (bw<<1)) &&
          (pixels_x16>=area_x5) && // occupancy >= 5/16 = 31.25%
          (pixels_x16<=area_x14);  // occupancy <= 14/16 = 87.5%
    wire [11:0] ex0=(ev_x0>=2)?ev_x0-10'd2:12'd0;
    wire [11:0] ey0=(ev_y0>=2)?ev_y0-10'd2:12'd0;
    wire [11:0] ex1=(ev_x1<W-3)?ev_x1+10'd2:W-1;
    wire [11:0] ey1=(ev_y1<H-3)?ev_y1+10'd2:H-1;
    wire [11:0] ecx=({2'd0,ev_x0}+{2'd0,ev_x1})>>1;
    wire [11:0] ecy=({2'd0,ev_y0}+{2'd0,ev_y1})>>1;

    // No reset tree for temporary data: every stage is written before use.
    always @(posedge clk) begin
        if(rst_n && state==ST_EVAL) begin
            case(eval_phase)
                0:begin
                    ev_pixels<=blob_pixels_read;ev_rough<=blob_rough_read;
                    ev_x0<=blob_x0_read;ev_x1<=blob_x1_read;
                    ev_y0<=blob_y0_read;ev_y1<=blob_y1_read;
                end
                1:begin
                    bw<={1'b0,ev_x1}-{1'b0,ev_x0}+11'd1;
                    bh<={1'b0,ev_y1}-{1'b0,ev_y0}+11'd1;
                end
                2:begin
                    bbox_area<=bw*bh;span<=bw+bh;
                    asym<=(bw>bh)?bw-bh:bh-bw;
                end
                3:begin
                    rough_term<=(rough32<<4)+(rough32<<1)+rough32;
                    span_term<=(span32<<3)+(span32<<2)+span32;
                    pixel_term<=pixels32<<1;
                    svm_negative<=(asym32<<7)+(asym32<<6)-(asym32<<1)-asym32+32'd1121;
                end
                4:svm_positive<=rough_term+span_term+pixel_term;
                5:qualified_q<=qualified;
                default:begin end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            eval_phase<=0;state<=ST_WAIT;pix_x<=0;pix_y<=0;next_blob<=0;eval_idx<=0;
            prev_n<=0;curr_n<=0;run_open<=0;run_x0<=0;run_x1<=0;
            run_pixels<=0;gap<=0;run_strong<=0;
            avg_q8<=16'd40960; // init mean 160.0
            run_cycles<=0;processing_cycles<=0;busy<=0;done<=0;overflow<=0;
            count<=0;center_x<=0;center_y<=0;first_svm_margin<=0;
            box_x0<=0;box_y0<=0;box_x1<=0;box_y1<=0;
            for(j=0;j<MAX_RUNS;j=j+1)begin
                prev_x0[j]<=0;prev_x1[j]<=0;prev_id[j]<=0;
                curr_x0[j]<=0;curr_x1[j]<=0;curr_id[j]<=0;
            end
        end else begin
            done<=0;
            if(state!=ST_WAIT && state!=ST_DONE)run_cycles<=run_cycles+1'b1;
            if((state==ST_FRAME && in_valid) || (state==ST_WAIT && in_valid && in_sof))
                avg_q8<=avg_q8 + (mean_delta >>> 9);


            // Single sequential write port for region stats and RLE metadata.
            if(finish_run && run_usable)begin
                if(can_link)begin
                    if(curr_n<MAX_RUNS)begin
                        curr_x0[curr_n]<=run_x0;curr_x1[curr_n]<=run_x1;
                        curr_id[curr_n]<=use_id;curr_n<=curr_n+1'b1;
                    end else overflow<=1'b1;
                    if(new_blob) next_blob<=next_blob+1'b1;
                end else overflow<=1'b1;
            end

            case(state)
                ST_WAIT: if(in_valid && in_sof)begin
                    // First pixel (0,0) lies outside the protected ROI.
                    pix_x<=1;pix_y<=0;prev_n<=0;curr_n<=0;
                    run_open<=0;run_pixels<=0;gap<=0;run_strong<=0;
                    next_blob<=0;eval_idx<=0;run_cycles<=0;
                    busy<=1;overflow<=0;
                    state<=ST_FRAME;
                end
                ST_FRAME: if(in_valid)begin
                    if(dark)begin
                        if(!run_open)begin
                            run_open<=1;run_x0<=pix_x;run_x1<=pix_x;
                            run_pixels<=1;run_strong<=strong;gap<=0;
                        end else begin
                            run_x1<=pix_x;
                            run_pixels<=run_pixels+1'b1;
                            run_strong<=run_strong || strong;
                            gap<=0;
                        end
                    end else if(run_open)begin
                        if(gap==2)begin
                            run_open<=0;run_pixels<=0;run_strong<=0;gap<=0;
                        end else gap<=gap+1'b1;
                    end
                    if(pix_x==W-1)begin pix_x<=0;state<=ST_FLUSH;end
                    else pix_x<=pix_x+1'b1;
                end
                ST_FLUSH:begin
                    // End-of-line closure, then copy the current run table.
                    run_open<=0;run_pixels<=0;run_strong<=0;gap<=0;
                    state<=ST_SWAP;
                end
                ST_SWAP:begin
                    prev_n<=curr_n;curr_n<=0;
                    for(j=0;j<MAX_RUNS;j=j+1)begin
                        prev_x0[j]<=curr_x0[j];prev_x1[j]<=curr_x1[j];
                        prev_id[j]<=curr_id[j];
                    end
                    if(pix_y==H-1)begin
                        eval_idx<=0;eval_phase<=0;count<=0;
                        center_x<=0;center_y<=0;first_svm_margin<=0;
                        box_x0<=0;box_y0<=0;box_x1<=0;box_y1<=0;
                        state<=ST_EVAL;
                    end else begin pix_y<=pix_y+1'b1;state<=ST_FRAME;end
                end
                ST_EVAL:begin
                    if(eval_phase==6)begin
                    eval_phase<=0;
                    if(eval_idx<next_blob && qualified_q)begin
                        if(count<TARGETS)begin
                            if(count==0)first_svm_margin<=svm_margin_clamped;
                            center_x[count*12+:12]<=ecx;
                            center_y[count*12+:12]<=ecy;
                            box_x0[count*12+:12]<=ex0;
                            box_y0[count*12+:12]<=ey0;
                            box_x1[count*12+:12]<=ex1;
                            box_y1[count*12+:12]<=ey1;
                            count<=count+1'b1;
                        end // More good blobs are skipped; do not erase count.
                    end
                    if(eval_idx==MAX_BLOBS-1)state<=ST_DONE;
                    else eval_idx<=eval_idx+1'b1;
                    end else eval_phase<=eval_phase+1'b1;
                end
                ST_DONE:begin
                    processing_cycles<=run_cycles;
                    busy<=0;done<=1;state<=ST_WAIT;
                end
                default:state<=ST_WAIT;
            endcase
        end
    end
endmodule
