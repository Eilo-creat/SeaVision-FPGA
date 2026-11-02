// SeaVision: current processing mode indicator in HDMI pixel domain.
// Show an always-visible color-coded mode HUD near the logo for bring-up.
// Background color proves the currently programmed bitstream contains this module.
module seavision_mode_osd (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_frame_start,
    input wire [1:0] I_mode_sw,
    input wire I_wb_sw,
    input wire I_target_pink,
    input wire [5:0] I_urchin_count,
    input wire [15:0] I_svm_margin,
    input wire [31:0] I_capture_cycles,
    input wire [15:0] I_pipeline_tenths,
    input wire I_pipeline_valid,
    input wire [47:0] I_urchin_x0, I_urchin_y0, I_urchin_x1, I_urchin_y1,
    input wire [11:0] I_x,
    input wire [11:0] I_y,
    output reg O_hit,
    output reg [23:0] O_color,
    output wire O_urchin_roi_found
);
  // Two flip-flop synchronizer. During bring-up, update mode live.
  // This avoids relying on a frame-start pulse in the HDMI domain.
  // Switch transitions can affect one frame; frame-boundary switching is a later refinement.
  reg [1:0] mode_meta, mode_sync, mode_display;
  reg wb_meta, wb_sync;
  always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
      mode_meta <= 2'd0;
      mode_sync <= 2'd0;
      mode_display <= 2'd0;
      wb_meta <= 1'b0; wb_sync <= 1'b0;
    end else begin
      mode_meta <= I_mode_sw;
      mode_sync <= mode_meta;
      mode_display <= mode_sync;
      wb_meta <= I_wb_sw; wb_sync <= wb_meta;
    end
  end
  // 7 characters, with 2x enlarged 16x16 glyphs.
  localparam [11:0] X0 = 12'd200;
  localparam [11:0] Y0 = 12'd18;
  localparam [11:0] W = 12'd224;
  localparam [11:0] H = 12'd40;
  wire inside = (I_x >= X0 && I_x < X0+W && I_y >= Y0 && I_y < Y0+H);
  // SeaVision V1.3.7: COUNT uses EXACT same row/clock/font as working RAW WB.
  // At x=436..596, only 12 px after the mode bar x=200..424.
  // The physical LCD size (6 inch) does not alter the HDMI 1280x720 raster.
  localparam [11:0] CX0=12'd436, CW=12'd160;
  wire count_inside = I_x>=CX0 && I_x<(CX0+CW) && I_y>=Y0 && I_y<(Y0+H);
  // Name and center of the FIRST positive candidate; NO TARGET otherwise.
  // V1.4.3: the full 15-character name/X/Y needs 480 pixels.
  // Place it in a SECOND row, above the existing Anlogic frame counter at y=120.
  // This avoids the physical LCD's right overscan and previous Y-digit clipping.
  localparam [11:0] NX0=12'd180, NY0=12'd66, NW=12'd576;
  wire name_inside = I_x>=NX0 && I_x<(NX0+NW) &&
                     I_y>=NY0 && I_y<(NY0+H);
  wire [11:0] name_rx=I_x-NX0;
  wire [4:0] name_char_idx=(name_rx-12'd3)>>5;
  wire name_char_ok=(name_rx>=12'd3 && name_rx<12'd547);
  // Separate same-font, second-row ROI status badge; no extra pixel clock.
  localparam [11:0] ZX0=12'd772, ZW=12'd320; // nine large glyphs for "海胆 IN ROI"
  wire zone_inside = I_x>=ZX0 && I_x<ZX0+ZW &&
                     I_y>=NY0 && I_y<NY0+H;
  wire [11:0] zone_rx=I_x-ZX0;
  wire [4:0] zone_char_idx=(zone_rx-12'd3)>>5;
  reg zone_hit;
  assign O_urchin_roi_found = !I_target_pink && zone_hit;
  reg [2:0] zone_missed_frames; // limit flicker on intermittent missed detections
  // Actual HDMI pipeline data-path latency (ISP/DDR -> HDMI stream), in tenths ms.
  localparam [11:0] PX0=12'd912,PY0=12'd18,PW=12'd204; // beside CAP, not across green ROI
  wire pipe_inside=I_x>=PX0 && I_x<PX0+PW && I_y>=PY0 && I_y<PY0+H;
  wire [11:0] pipe_rx=I_x-PX0;
  wire [3:0] pipe_char_idx=(pipe_rx-12'd3)>>5;
  reg [13:0] pipe_shift;
  reg [15:0] pipe_bcd_work,pipe_bcd_show;
  reg [3:0] pipe_step;
  wire [15:0] pipe_bcd_adjust=bcd_add3(pipe_bcd_work);
  wire [15:0] pipe_bcd_next={pipe_bcd_adjust[14:0],pipe_shift[13]};
  wire [13:0] pipe_clamped=(I_pipeline_tenths>16'd9999) ? 14'd9999 : I_pipeline_tenths[13:0];
  // Four BCD digits: first three are integer milliseconds, last is 0.1 ms.

  // V1.4.6: CAPTURE DIAGNOSTIC in the TOP row just right of U:00.
  // CAP:xxxxK reports detector acquisition+evaluation in units of 1024
  // HDMI pixel clocks, NOT camera-to-HDMI transport latency.
  // Mode bar ends at X=424; U count ends at X=596; CAP starts X=608.
  // 9 glyphs * 32px with 3px padding => 300px wide, ends at X=908.
  localparam [11:0] LX0=12'd608, LY0=12'd18, LW=12'd300;
  wire lat_inside=I_x>=LX0 && I_x<(LX0+LW) && I_y>=LY0 && I_y<LY0+H;
  wire [11:0] lat_rx=I_x-LX0;
  wire [3:0] lat_char_idx=(lat_rx-12'd3)>>5;
  reg [13:0] cap_shift;
  reg [15:0] cap_bcd_work,cap_bcd_show;
  reg [3:0] cap_step;
  wire [15:0] cap_bcd_adjust=bcd_add3(cap_bcd_work);
  wire [15:0] cap_bcd_next={cap_bcd_adjust[14:0],cap_shift[13]};
  // At 74.25 MHz, a typical 720p capture lasts about 900K pixel clocks.
  // Keep a bounded 4-digit decimal counter to avoid big dividers/multipliers.
  wire [21:0] cap_k_all=I_capture_cycles[31:10];
  wire [13:0] cap_k=(cap_k_all>22'd9999)?14'd9999:cap_k_all[13:0];
  // V160: single-candidate diagnostics, at bottom left (no collision with
  // top P:xxxM pipeline latency, CAP, ROI or target coordinates).
  // SVM:dddd uses real (clamped) integer decision margin from current RTL.
  // V163: P uses current SVM margin and an offline candidate-level sigmoid
  // calibration table.  It is an experimental estimate, NOT accuracy.
  // V164: keep this HUD visible in the existing sea-urchin RAW mode.
  // Absent/unconfirmed boxes show zero; pink/other modes stay unchanged.
  localparam [11:0] SX0=12'd20,SY0=12'd640,SW=12'd526;
  wire score_inside=(I_target_pink==1'b0) &&
       (mode_display==2'b00) &&
       (I_x>=SX0 && I_x<SX0+SW && I_y>=SY0 && I_y<SY0+H);
  wire [11:0] score_rx=I_x-SX0;
  wire [4:0] score_char_idx=(score_rx-12'd3)>>5;
  // V162: display-only smoothing of the REAL positive SVM integer margin.
  // The detector, its coefficients and the qualification signal stay untouched.
  // Margin is sampled ONLY at HDMI frame boundary, and a new target starts
  // a new smoothing run. Suppress micro-jitter within 128 raw count units.
  reg [15:0] score_hold;
  reg score_hold_valid;
  wire [15:0] score_gap_up=I_svm_margin-score_hold;
  wire [15:0] score_gap_down=score_hold-I_svm_margin;
  wire [15:0] score_step_up=(score_gap_up>>3)==0 ? 16'd1 : score_gap_up>>3;
  wire [15:0] score_step_down=(score_gap_down>>3)==0 ? 16'd1 : score_gap_down>>3;
  always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
      score_hold<=0;
      score_hold_valid<=1'b0;
    end else if(I_frame_start) begin
      if(I_target_pink || I_urchin_count==0) begin
        score_hold<=0;
        score_hold_valid<=1'b0;
      end else if(!score_hold_valid) begin
        score_hold<=I_svm_margin;
        score_hold_valid<=1'b1;
      end else if(I_svm_margin>=score_hold) begin
        if(score_gap_up>16'd128) score_hold<=score_hold+score_step_up;
      end else begin
        if(score_gap_down>16'd128) score_hold<=score_hold-score_step_down;
      end
    end
  end
  // V163: camera-frame-dependent P estimate, not a hand-set target accuracy.
  // Derived from the ORIGINAL, unchanged 4D RTL score (score_hold).  The
  // 1-D sigmoid was fitted on 92 historical 638-image candidate VALIDATION
  // samples, 65 positive / 27 negative (the 20 demo images were NOT used
  // to fit this mapping).  On held-out candidates AUC was ~0.473, so this is
  // a LOW-RELIABILITY experimental estimate, not verified confidence.
  // PERCENT IS NOT dataset accuracy; NEVER force a 75/80/90% minimum.
  // 256 x 12-bit ROM for 0.1% presentation precision, quantized every 256
  // original margin counts.  No online sigmoid, divider, or new DSP required.
  // Formula behind the static lookup: sigmoid(0.8222570626423183 +
  // 0.000026900141250656862 * margin).  Negative scores are not displayed:
  // only previously accepted, actually confirmed positive detector boxes
  // use this lookup; absent boxes display zero through the output mask.
  // No changes to detector/weight/threshold/ROI.
  reg [11:0] prob_bcd;
  always @(*) begin
    case(score_hold[15:8])
      8'h00: prob_bcd=12'h695;
      8'h01: prob_bcd=12'h697;
      8'h02: prob_bcd=12'h698;
      8'h03: prob_bcd=12'h700;
      8'h04: prob_bcd=12'h701;
      8'h05: prob_bcd=12'h703;
      8'h06: prob_bcd=12'h704;
      8'h07: prob_bcd=12'h706;
      8'h08: prob_bcd=12'h707;
      8'h09: prob_bcd=12'h708;
      8'h0A: prob_bcd=12'h710;
      8'h0B: prob_bcd=12'h711;
      8'h0C: prob_bcd=12'h713;
      8'h0D: prob_bcd=12'h714;
      8'h0E: prob_bcd=12'h715;
      8'h0F: prob_bcd=12'h717;
      8'h10: prob_bcd=12'h718;
      8'h11: prob_bcd=12'h720;
      8'h12: prob_bcd=12'h721;
      8'h13: prob_bcd=12'h722;
      8'h14: prob_bcd=12'h724;
      8'h15: prob_bcd=12'h725;
      8'h16: prob_bcd=12'h727;
      8'h17: prob_bcd=12'h728;
      8'h18: prob_bcd=12'h729;
      8'h19: prob_bcd=12'h731;
      8'h1A: prob_bcd=12'h732;
      8'h1B: prob_bcd=12'h733;
      8'h1C: prob_bcd=12'h735;
      8'h1D: prob_bcd=12'h736;
      8'h1E: prob_bcd=12'h737;
      8'h1F: prob_bcd=12'h739;
      8'h20: prob_bcd=12'h740;
      8'h21: prob_bcd=12'h741;
      8'h22: prob_bcd=12'h743;
      8'h23: prob_bcd=12'h744;
      8'h24: prob_bcd=12'h745;
      8'h25: prob_bcd=12'h747;
      8'h26: prob_bcd=12'h748;
      8'h27: prob_bcd=12'h749;
      8'h28: prob_bcd=12'h750;
      8'h29: prob_bcd=12'h752;
      8'h2A: prob_bcd=12'h753;
      8'h2B: prob_bcd=12'h754;
      8'h2C: prob_bcd=12'h756;
      8'h2D: prob_bcd=12'h757;
      8'h2E: prob_bcd=12'h758;
      8'h2F: prob_bcd=12'h759;
      8'h30: prob_bcd=12'h761;
      8'h31: prob_bcd=12'h762;
      8'h32: prob_bcd=12'h763;
      8'h33: prob_bcd=12'h764;
      8'h34: prob_bcd=12'h766;
      8'h35: prob_bcd=12'h767;
      8'h36: prob_bcd=12'h768;
      8'h37: prob_bcd=12'h769;
      8'h38: prob_bcd=12'h771;
      8'h39: prob_bcd=12'h772;
      8'h3A: prob_bcd=12'h773;
      8'h3B: prob_bcd=12'h774;
      8'h3C: prob_bcd=12'h775;
      8'h3D: prob_bcd=12'h777;
      8'h3E: prob_bcd=12'h778;
      8'h3F: prob_bcd=12'h779;
      8'h40: prob_bcd=12'h780;
      8'h41: prob_bcd=12'h781;
      8'h42: prob_bcd=12'h782;
      8'h43: prob_bcd=12'h784;
      8'h44: prob_bcd=12'h785;
      8'h45: prob_bcd=12'h786;
      8'h46: prob_bcd=12'h787;
      8'h47: prob_bcd=12'h788;
      8'h48: prob_bcd=12'h789;
      8'h49: prob_bcd=12'h791;
      8'h4A: prob_bcd=12'h792;
      8'h4B: prob_bcd=12'h793;
      8'h4C: prob_bcd=12'h794;
      8'h4D: prob_bcd=12'h795;
      8'h4E: prob_bcd=12'h796;
      8'h4F: prob_bcd=12'h797;
      8'h50: prob_bcd=12'h798;
      8'h51: prob_bcd=12'h800;
      8'h52: prob_bcd=12'h801;
      8'h53: prob_bcd=12'h802;
      8'h54: prob_bcd=12'h803;
      8'h55: prob_bcd=12'h804;
      8'h56: prob_bcd=12'h805;
      8'h57: prob_bcd=12'h806;
      8'h58: prob_bcd=12'h807;
      8'h59: prob_bcd=12'h808;
      8'h5A: prob_bcd=12'h809;
      8'h5B: prob_bcd=12'h810;
      8'h5C: prob_bcd=12'h811;
      8'h5D: prob_bcd=12'h812;
      8'h5E: prob_bcd=12'h814;
      8'h5F: prob_bcd=12'h815;
      8'h60: prob_bcd=12'h816;
      8'h61: prob_bcd=12'h817;
      8'h62: prob_bcd=12'h818;
      8'h63: prob_bcd=12'h819;
      8'h64: prob_bcd=12'h820;
      8'h65: prob_bcd=12'h821;
      8'h66: prob_bcd=12'h822;
      8'h67: prob_bcd=12'h823;
      8'h68: prob_bcd=12'h824;
      8'h69: prob_bcd=12'h825;
      8'h6A: prob_bcd=12'h826;
      8'h6B: prob_bcd=12'h827;
      8'h6C: prob_bcd=12'h828;
      8'h6D: prob_bcd=12'h829;
      8'h6E: prob_bcd=12'h830;
      8'h6F: prob_bcd=12'h831;
      8'h70: prob_bcd=12'h832;
      8'h71: prob_bcd=12'h833;
      8'h72: prob_bcd=12'h834;
      8'h73: prob_bcd=12'h834;
      8'h74: prob_bcd=12'h835;
      8'h75: prob_bcd=12'h836;
      8'h76: prob_bcd=12'h837;
      8'h77: prob_bcd=12'h838;
      8'h78: prob_bcd=12'h839;
      8'h79: prob_bcd=12'h840;
      8'h7A: prob_bcd=12'h841;
      8'h7B: prob_bcd=12'h842;
      8'h7C: prob_bcd=12'h843;
      8'h7D: prob_bcd=12'h844;
      8'h7E: prob_bcd=12'h845;
      8'h7F: prob_bcd=12'h846;
      8'h80: prob_bcd=12'h846;
      8'h81: prob_bcd=12'h847;
      8'h82: prob_bcd=12'h848;
      8'h83: prob_bcd=12'h849;
      8'h84: prob_bcd=12'h850;
      8'h85: prob_bcd=12'h851;
      8'h86: prob_bcd=12'h852;
      8'h87: prob_bcd=12'h853;
      8'h88: prob_bcd=12'h853;
      8'h89: prob_bcd=12'h854;
      8'h8A: prob_bcd=12'h855;
      8'h8B: prob_bcd=12'h856;
      8'h8C: prob_bcd=12'h857;
      8'h8D: prob_bcd=12'h858;
      8'h8E: prob_bcd=12'h859;
      8'h8F: prob_bcd=12'h859;
      8'h90: prob_bcd=12'h860;
      8'h91: prob_bcd=12'h861;
      8'h92: prob_bcd=12'h862;
      8'h93: prob_bcd=12'h863;
      8'h94: prob_bcd=12'h864;
      8'h95: prob_bcd=12'h864;
      8'h96: prob_bcd=12'h865;
      8'h97: prob_bcd=12'h866;
      8'h98: prob_bcd=12'h867;
      8'h99: prob_bcd=12'h868;
      8'h9A: prob_bcd=12'h868;
      8'h9B: prob_bcd=12'h869;
      8'h9C: prob_bcd=12'h870;
      8'h9D: prob_bcd=12'h871;
      8'h9E: prob_bcd=12'h871;
      8'h9F: prob_bcd=12'h872;
      8'hA0: prob_bcd=12'h873;
      8'hA1: prob_bcd=12'h874;
      8'hA2: prob_bcd=12'h874;
      8'hA3: prob_bcd=12'h875;
      8'hA4: prob_bcd=12'h876;
      8'hA5: prob_bcd=12'h877;
      8'hA6: prob_bcd=12'h877;
      8'hA7: prob_bcd=12'h878;
      8'hA8: prob_bcd=12'h879;
      8'hA9: prob_bcd=12'h880;
      8'hAA: prob_bcd=12'h880;
      8'hAB: prob_bcd=12'h881;
      8'hAC: prob_bcd=12'h882;
      8'hAD: prob_bcd=12'h883;
      8'hAE: prob_bcd=12'h883;
      8'hAF: prob_bcd=12'h884;
      8'hB0: prob_bcd=12'h885;
      8'hB1: prob_bcd=12'h885;
      8'hB2: prob_bcd=12'h886;
      8'hB3: prob_bcd=12'h887;
      8'hB4: prob_bcd=12'h887;
      8'hB5: prob_bcd=12'h888;
      8'hB6: prob_bcd=12'h889;
      8'hB7: prob_bcd=12'h890;
      8'hB8: prob_bcd=12'h890;
      8'hB9: prob_bcd=12'h891;
      8'hBA: prob_bcd=12'h892;
      8'hBB: prob_bcd=12'h892;
      8'hBC: prob_bcd=12'h893;
      8'hBD: prob_bcd=12'h894;
      8'hBE: prob_bcd=12'h894;
      8'hBF: prob_bcd=12'h895;
      8'hC0: prob_bcd=12'h895;
      8'hC1: prob_bcd=12'h896;
      8'hC2: prob_bcd=12'h897;
      8'hC3: prob_bcd=12'h897;
      8'hC4: prob_bcd=12'h898;
      8'hC5: prob_bcd=12'h899;
      8'hC6: prob_bcd=12'h899;
      8'hC7: prob_bcd=12'h900;
      8'hC8: prob_bcd=12'h901;
      8'hC9: prob_bcd=12'h901;
      8'hCA: prob_bcd=12'h902;
      8'hCB: prob_bcd=12'h902;
      8'hCC: prob_bcd=12'h903;
      8'hCD: prob_bcd=12'h904;
      8'hCE: prob_bcd=12'h904;
      8'hCF: prob_bcd=12'h905;
      8'hD0: prob_bcd=12'h905;
      8'hD1: prob_bcd=12'h906;
      8'hD2: prob_bcd=12'h907;
      8'hD3: prob_bcd=12'h907;
      8'hD4: prob_bcd=12'h908;
      8'hD5: prob_bcd=12'h908;
      8'hD6: prob_bcd=12'h909;
      8'hD7: prob_bcd=12'h909;
      8'hD8: prob_bcd=12'h910;
      8'hD9: prob_bcd=12'h911;
      8'hDA: prob_bcd=12'h911;
      8'hDB: prob_bcd=12'h912;
      8'hDC: prob_bcd=12'h912;
      8'hDD: prob_bcd=12'h913;
      8'hDE: prob_bcd=12'h913;
      8'hDF: prob_bcd=12'h914;
      8'hE0: prob_bcd=12'h914;
      8'hE1: prob_bcd=12'h915;
      8'hE2: prob_bcd=12'h915;
      8'hE3: prob_bcd=12'h916;
      8'hE4: prob_bcd=12'h917;
      8'hE5: prob_bcd=12'h917;
      8'hE6: prob_bcd=12'h918;
      8'hE7: prob_bcd=12'h918;
      8'hE8: prob_bcd=12'h919;
      8'hE9: prob_bcd=12'h919;
      8'hEA: prob_bcd=12'h920;
      8'hEB: prob_bcd=12'h920;
      8'hEC: prob_bcd=12'h921;
      8'hED: prob_bcd=12'h921;
      8'hEE: prob_bcd=12'h922;
      8'hEF: prob_bcd=12'h922;
      8'hF0: prob_bcd=12'h923;
      8'hF1: prob_bcd=12'h923;
      8'hF2: prob_bcd=12'h924;
      8'hF3: prob_bcd=12'h924;
      8'hF4: prob_bcd=12'h925;
      8'hF5: prob_bcd=12'h925;
      8'hF6: prob_bcd=12'h926;
      8'hF7: prob_bcd=12'h926;
      8'hF8: prob_bcd=12'h926;
      8'hF9: prob_bcd=12'h927;
      8'hFA: prob_bcd=12'h927;
      8'hFB: prob_bcd=12'h928;
      8'hFC: prob_bcd=12'h928;
      8'hFD: prob_bcd=12'h929;
      8'hFE: prob_bcd=12'h929;
      8'hFF: prob_bcd=12'h930;
      default: prob_bcd=12'h695;
    endcase
  end
  // Use the box count as well as frame-latched validity so a vanished
  // box cannot leave stale digits visible (BCD conversion is pipelined).
  // Zero is an absence indicator, not the sigmoid value at margin zero.
  wire score_target_valid=!I_target_pink && (I_urchin_count!=0) &&
                          hud_target_present && score_hold_valid;
  wire [11:0] prob_bcd_display=score_target_valid ? prob_bcd : 12'h000;
  wire [15:0] score_bcd_display=score_target_valid ? score_bcd_show : 16'h0000;
  wire [3:0] p_tens=prob_bcd_display[11:8];
  wire [3:0] p_ones=prob_bcd_display[7:4];
  wire [3:0] p_tenth=prob_bcd_display[3:0];
  // Human-readable *scaled margin*, SVMraw / 2048, two decimals.
  // It is NOT the learned w[] weights and NOT probability.
  // Constant 25 shift-add gives hundredths approx: raw*25/512.
  // Large positive margins saturate at 9.99 only for the HUD.
  wire [20:0] score_mul25 = ({5'd0,score_hold}<<4) +
                    ({5'd0,score_hold}<<3) + {5'd0,score_hold};
  wire [11:0] score_centi_raw=score_mul25>>9;
  wire [13:0] score_clamped=(score_mul25[20:9]>12'd999) ?
               14'd999 : {2'd0,score_centi_raw};
  reg [13:0] score_shift;
  reg [15:0] score_bcd_work,score_bcd_show;
  reg [3:0] score_step;
  wire [15:0] score_bcd_adjust=bcd_add3(score_bcd_work);
  wire [15:0] score_bcd_next={score_bcd_adjust[14:0],score_shift[13]};
  // Box coordinates in 320x180 detector units, convert to 1280x720 HDMI.
  // (x0+x1)*2 gives center pixel in display space, avoiding dividers.
  wire [11:0] new_x_center=(I_urchin_x0[11:0]+I_urchin_x1[11:0])<<1;
  wire [11:0] new_y_center=(I_urchin_y0[11:0]+I_urchin_y1[11:0])<<1;
  // Any one of up to four detected sea urchins may qualify.
  // Reuse the green ROI geometry from hdmi_mixer (display pixels 320..960,130..590).
  reg any_urchin_in_zone;
  integer zi;
  reg [11:0] zx0,zx1,zy0,zy1;
  always @(*)begin
    any_urchin_in_zone=1'b0;
    zx0=0;zx1=0;zy0=0;zy1=0;
    for(zi=0;zi<4;zi=zi+1)begin
      zx0=I_urchin_x0[zi*12+:12];zx1=I_urchin_x1[zi*12+:12];
      zy0=I_urchin_y0[zi*12+:12];zy1=I_urchin_y1[zi*12+:12];
      // Candidate must overlap ROI; coordinates are 320x180 detector units.
      if(zi<I_urchin_count && zx1>=12'd80 && zx0<=12'd240 &&
         zy1>=12'd33 && zy0<=12'd147)
           any_urchin_in_zone=1'b1;
    end
  end
  reg hud_target_present;
  reg [11:0] x_shift,y_shift;
  reg [15:0] bcd_x_work,bcd_y_work,bcd_x_display,bcd_y_display;
  reg [3:0] bcd_step;
  function [15:0] bcd_add3;
    input [15:0] d;
    reg [15:0] a;
    integer k;
    begin
      a=d;
      for(k=0;k<4;k=k+1)
        if(a[k*4+:4]>=4'd5) a[k*4+:4]=a[k*4+:4]+4'd3;
      bcd_add3=a;
    end
  endfunction
  wire [15:0] bx_adjust=bcd_add3(bcd_x_work);
  wire [15:0] by_adjust=bcd_add3(bcd_y_work);
  wire [15:0] bx_next={bx_adjust[14:0],x_shift[10]};
  wire [15:0] by_next={by_adjust[14:0],y_shift[10]};
  // 11 small steps once per HDMI frame; no large combinatorial divider.
  always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
      hud_target_present<=1'b0; zone_hit<=1'b0;
      zone_missed_frames<=0;
      pipe_shift<=0;pipe_bcd_work<=0;pipe_bcd_show<=0;pipe_step<=0;
      x_shift<=0; y_shift<=0; bcd_x_work<=0; bcd_y_work<=0;
      bcd_x_display<=0; bcd_y_display<=0; bcd_step<=0;
      cap_shift<=0;cap_bcd_work<=0;cap_step<=0;
      score_shift<=0;score_bcd_work<=0;score_bcd_show<=0;score_step<=0;
    end else begin
      if(pipe_step != 0) begin
        pipe_shift<={pipe_shift[12:0],1'b0};
        pipe_bcd_work<=pipe_bcd_next;
        pipe_step<=pipe_step-1'b1;
        if(pipe_step==4'd1)pipe_bcd_show<=pipe_bcd_next;
      end
      if(score_step != 0) begin
        score_shift<={score_shift[12:0],1'b0};
        score_bcd_work<=score_bcd_next;
        score_step<=score_step-1'b1;
        if(score_step==4'd1)score_bcd_show<=score_bcd_next;
      end
      if(cap_step != 0) begin
        cap_shift<={cap_shift[12:0],1'b0};
        cap_bcd_work<=cap_bcd_next;
        cap_step<=cap_step-1'b1;
      end
      if(I_frame_start) begin
      hud_target_present<= (I_urchin_count != 0);
      // Preserve the pink profile's existing ROI status logic unchanged.
      // Sea-urchin mode: informative entry display with short dropout hold.
      if(I_target_pink) begin
        zone_hit<= (I_urchin_count != 0) &&
                   new_x_center>=12'd320 && new_x_center<=12'd960 &&
                   new_y_center>=12'd130 && new_y_center<=12'd590;
        zone_missed_frames<=0;
      end else if(any_urchin_in_zone)begin
        zone_hit<=1'b1;
        zone_missed_frames<=0;
      end else if(zone_missed_frames<3'd3)begin
        zone_missed_frames<=zone_missed_frames+1'b1;
      end else begin
        zone_hit<=1'b0;
      end
      x_shift<=new_x_center; y_shift<=new_y_center;
      bcd_x_work<=0; bcd_y_work<=0; bcd_step<=4'd11;
      cap_shift<=cap_k;cap_bcd_work<=0;cap_step<=4'd14;
      score_shift<=score_clamped;score_bcd_work<=0;score_step<=4'd14;
      pipe_shift<=pipe_clamped;pipe_bcd_work<=0;pipe_step<=4'd14;
      end else if(bcd_step!=0) begin
      x_shift<={x_shift[9:0],1'b0};
      y_shift<={y_shift[9:0],1'b0};
      bcd_x_work<=bx_next; bcd_y_work<=by_next;
      bcd_step<=bcd_step-1'b1;
      if(bcd_step==4'd1) begin
        bcd_x_display<=bx_next; bcd_y_display<=by_next;
      end
    end
    end
  end
  always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
      cap_bcd_show<=0;
    end else if(cap_step==4'd1) begin
      cap_bcd_show<=cap_bcd_next;
    end
  end
  wire [11:0] rel_x = I_x - X0;
  wire [11:0] rel_y = I_y - Y0;
  // glyphs start at offset 2, 4:1 of coordinates selects 16 pixels.
  wire [11:0] active_rel_x = score_inside ? score_rx : (pipe_inside ? pipe_rx :
       (lat_inside ? lat_rx : (zone_inside ? zone_rx :
       (name_inside ? name_rx : (count_inside ? I_x-CX0 : rel_x)))));
  wire [11:0] active_rel_y = score_inside ? I_y-SY0 : (pipe_inside ? I_y-PY0 :
      (lat_inside ? I_y-LY0 : ((name_inside || zone_inside) ? I_y-NY0 : rel_y)));
  wire [11:0] text_x = active_rel_x - 12'd3;
  wire [11:0] text_y = active_rel_y - 12'd4;
  wire glyph_y_ok = (active_rel_y >= 12'd4 && active_rel_y < 12'd36);
  wire glyph_x_ok = (active_rel_x >= 12'd3 &&
      (score_inside ? (score_rx < 12'd515) : (pipe_inside ? (pipe_rx < 12'd195) : (lat_inside ? (lat_rx < 12'd291) :
      (zone_inside ? (zone_rx < 12'd291) : (name_inside ? name_char_ok :
      (count_inside ? (active_rel_x < 12'd131) : (active_rel_x < 12'd227))))))));
  wire [2:0] char_idx = text_x[7:5];
  wire [3:0] glyph_col = text_x[4:1];
  wire [3:0] glyph_row = text_y[4:1];
  reg [7:0] glyph_char;
  wire [15:0] glyph_row_bits;
  osd_char_lib u_seavision_mode_font (
      .I_char(glyph_char),
      .I_row(glyph_row),
      .O_row_bits(glyph_row_bits)
  );
  always @(*) begin
    glyph_char = 8'h20;
    // "RAW", "EDGE", "GRAY", "BINARY" labels.
    case(mode_display)
      2'b00: case(char_idx)
        3'd0: glyph_char="R"; 3'd1: glyph_char="A";
        3'd2: glyph_char="W";
        3'd4: glyph_char=wb_sync ? "W" : 8'h20;
        3'd5: glyph_char=wb_sync ? "B" : 8'h20;
        default: glyph_char=8'h20;
      endcase
      2'b01: case(char_idx)
        3'd0: glyph_char="E"; 3'd1: glyph_char="D";
        3'd2: glyph_char="G"; 3'd3: glyph_char="E";
        default: glyph_char=8'h20;
      endcase
      2'b10: case(char_idx)
        3'd0: glyph_char="G"; 3'd1: glyph_char="R";
        3'd2: glyph_char="A"; 3'd3: glyph_char="Y";
        default: glyph_char=8'h20;
      endcase
      default: case(char_idx)
        3'd0: glyph_char="B"; 3'd1: glyph_char="I";
        3'd2: glyph_char="N"; 3'd3: glyph_char="A";
        3'd4: glyph_char="R"; 3'd5: glyph_char="Y";
        default: glyph_char=8'h20;
      endcase
    endcase
    // Character cell 6 remains blank; mode name ends at RAW WB / EDGE / GRAY / BINARY.
    if(count_inside) begin
      case(char_idx)
        3'd0: glyph_char=I_target_pink ? "P" : "U";
        3'd1: glyph_char=":";
        3'd2: glyph_char="0";
        3'd3: glyph_char=(I_urchin_count<=6'd9) ? (8'd48+{2'b00,I_urchin_count}) : "9";
        default: glyph_char=8'h20;
      endcase
    end
    // Position legend: "海胆 X:dddd Y:ddd" for an active candidate,
    // otherwise "NO TARGET". XY is the FIRST candidate.
    // Our common 16x16/2x font comes from the same osd_char_lib instance.
    if(name_inside) begin
      if(!hud_target_present) begin
        // No positive candidate: visible diagnostic rather than false 'urchin'.
        case(name_char_idx)
          5'd0: glyph_char="N";
          5'd1: glyph_char="O";
          5'd2: glyph_char=8'h20;
          5'd3: glyph_char="T";
          5'd4: glyph_char="A";
          5'd5: glyph_char="R";
          5'd6: glyph_char="G";
          5'd7: glyph_char="E";
          5'd8: glyph_char="T";
          default: glyph_char=8'h20;
        endcase
      end else if(I_target_pink) begin
        case(name_char_idx)
          5'd0:glyph_char="P"; 5'd1:glyph_char="I";
          5'd2:glyph_char="N"; 5'd3:glyph_char="K";
          5'd4:glyph_char=8'h20;
          5'd5:glyph_char="X"; 5'd6:glyph_char=":";
          5'd7:glyph_char=8'd48+bcd_x_display[15:12];
          5'd8:glyph_char=8'd48+bcd_x_display[11:8];
          5'd9:glyph_char=8'd48+bcd_x_display[7:4];
          5'd10:glyph_char=8'd48+bcd_x_display[3:0];
          5'd11:glyph_char=8'h20;
          5'd12:glyph_char="Y"; 5'd13:glyph_char=":";
          5'd14:glyph_char=8'd48+bcd_y_display[11:8];
          5'd15:glyph_char=8'd48+bcd_y_display[7:4];
          5'd16:glyph_char=8'd48+bcd_y_display[3:0];
          default:glyph_char=8'h20;
        endcase
      end else begin
        case(name_char_idx)
          5'd0: glyph_char=8'h82; // 海
          5'd1: glyph_char=8'h83; // 胆
          5'd2: glyph_char=8'h20;
          5'd3: glyph_char="X";
          5'd4: glyph_char=":";
          5'd5: glyph_char=8'd48+bcd_x_display[15:12];
          5'd6: glyph_char=8'd48+bcd_x_display[11:8];
          5'd7: glyph_char=8'd48+bcd_x_display[7:4];
          5'd8: glyph_char=8'd48+bcd_x_display[3:0];
          5'd9: glyph_char=8'h20;
          5'd10: glyph_char="Y";
          5'd11: glyph_char=":";
          5'd12: glyph_char=8'd48+bcd_y_display[11:8];
          5'd13: glyph_char=8'd48+bcd_y_display[7:4];
          5'd14: glyph_char=8'd48+bcd_y_display[3:0];
          default: glyph_char=8'h20;
        endcase
      end
    end
    // Independent status uses the same font mux as RAW and U-count.
    if(zone_inside)begin
      if(I_target_pink)begin
        case(zone_char_idx)
          5'd0:glyph_char="R"; 5'd1:glyph_char="O";
          5'd2:glyph_char="I"; 5'd3:glyph_char=":";
          5'd5:glyph_char=zone_hit ? "I" : "-";
          5'd6:glyph_char=zone_hit ? "N" : "-";
          default:glyph_char=8'h20;
        endcase
      end else begin
        // Sea-urchin informational prompt, not a hazard alarm.
        // Existing font ROM already has the two Chinese glyphs. Using English
        // FOUND/WAIT avoids a costly extra Chinese glyph ROM.
        // Characters: 海 胆 [space] F O U N D / W A I T.
        case(zone_char_idx)
          5'd0:glyph_char=8'h82; 5'd1:glyph_char=8'h83;
          5'd3:glyph_char=zone_hit ? "F" : "W";
          5'd4:glyph_char=zone_hit ? "O" : "A";
          5'd5:glyph_char=zone_hit ? "U" : "I";
          5'd6:glyph_char=zone_hit ? "N" : "T";
          5'd7:glyph_char=zone_hit ? "D" : 8'h20;
          default:glyph_char=8'h20;
        endcase
      end
    end
    if(lat_inside) begin
      case(lat_char_idx)
        4'd0:glyph_char="C"; 4'd1:glyph_char="A";
        4'd2:glyph_char="P"; 4'd3:glyph_char=":";
        4'd4:glyph_char=8'd48+cap_bcd_show[15:12];
        4'd5:glyph_char=8'd48+cap_bcd_show[11:8];
        4'd6:glyph_char=8'd48+cap_bcd_show[7:4];
        4'd7:glyph_char=8'd48+cap_bcd_show[3:0];
        4'd8:glyph_char="K";
        default:glyph_char=8'h20;
      endcase
    end
    // P:dddM = video pipeline frame delay in whole milliseconds (0..999).
    // CAP remains the detector's independent processing-window measurement.
    if(pipe_inside)begin
      case(pipe_char_idx)
        4'd0:glyph_char="P";
        4'd1:glyph_char=":";
        4'd2:glyph_char=I_pipeline_valid ? (8'd48+pipe_bcd_show[15:12]) : "-";
        4'd3:glyph_char=I_pipeline_valid ? (8'd48+pipe_bcd_show[11:8]) : "-";
        4'd4:glyph_char=I_pipeline_valid ? (8'd48+pipe_bcd_show[7:4]) : "-";
        4'd5:glyph_char="M"; // milliseconds; trailing tenths digit not shown
        default:glyph_char=8'h20;
      endcase
    end
    // HUD uses a stable scaled score (real raw margin / 2048), not weights.
    // P is a 0.1%-quantized empirical score->probability estimate; validation
  // AUC was poor, so this value must not be presented as detection accuracy.
    if(score_inside)begin
      case(score_char_idx)
        4'd0:glyph_char="S"; 4'd1:glyph_char="V";
        4'd2:glyph_char="M"; 4'd3:glyph_char=":";
        4'd4:glyph_char=8'd48+score_bcd_display[11:8];
        4'd5:glyph_char=".";
        4'd6:glyph_char=8'd48+score_bcd_display[7:4];
        4'd7:glyph_char=8'd48+score_bcd_display[3:0];
        4'd9:glyph_char="P"; 4'd10:glyph_char=":";
        4'd11:glyph_char=8'd48+p_tens;
        4'd12:glyph_char=8'd48+p_ones;
        4'd13:glyph_char=".";
        4'd14:glyph_char=8'd48+p_tenth;
        4'd15:glyph_char="%";
        default:glyph_char=8'h20;
      endcase
    end
    O_hit = inside || count_inside || name_inside || zone_inside || lat_inside || pipe_inside || score_inside;
    // Four high-contrast opaque HUD backgrounds. The box itself is a
    // verification signature and remains visible even when font pixels are off.
    case(mode_display)
      2'b00: O_color = wb_sync ? 24'h006d77 : 24'h850079; // RAW WB: teal, RAW: violet
      2'b01: O_color = 24'h0637b5; // EDGE: blue
      2'b10: O_color = 24'h985000; // GRAY: orange
      default: O_color = 24'h006c2d; // BINARY: green
    endcase
    if(count_inside) O_color = 24'h123542;
    if(name_inside) O_color = 24'h123542;
    if(zone_inside) O_color = zone_hit ?
        (!I_target_pink ? 24'h8c1722 : 24'h075636) : 24'h123542;
    if(lat_inside) O_color = 24'h123542;
    if(pipe_inside) O_color = I_pipeline_valid ? 24'h0c4561 : 24'h123542;
    if(score_inside) O_color=24'h123542;
    if ((inside && (rel_x <= 12'd2 || rel_x >= W-12'd3 ||
                    rel_y <= 12'd1 || rel_y >= H-12'd2)) ||
        (count_inside && (active_rel_x <= 12'd2 || active_rel_x >= CW-12'd3 ||
                    rel_y <= 12'd1 || rel_y >= H-12'd2)) ||
        (name_inside && (name_rx <= 12'd2 || name_rx >= NW-12'd3 ||
                    active_rel_y <= 12'd1 || active_rel_y >= H-12'd2)) ||
        (zone_inside && (zone_rx <= 12'd2 || zone_rx >= ZW-12'd3 ||
                    active_rel_y <= 12'd1 || active_rel_y >= H-12'd2)) ||
        (lat_inside && (lat_rx <= 12'd2 || lat_rx >= LW-12'd3 ||
                    active_rel_y <= 12'd1 || active_rel_y >= H-12'd2)) ||
        (pipe_inside && (pipe_rx<=12'd2 || pipe_rx>=PW-12'd3 ||
                    active_rel_y<=12'd1 || active_rel_y>=H-12'd2)) ||
        (score_inside && (score_rx<=12'd2 || score_rx>=SW-12'd3 ||
                    active_rel_y<=12'd1 || active_rel_y>=H-12'd2)))
      O_color = 24'hffffff;
    else if ((inside || count_inside || name_inside || zone_inside || lat_inside || pipe_inside || score_inside) && glyph_x_ok && glyph_y_ok && glyph_row_bits[15-glyph_col]) begin
      if(zone_inside && zone_hit && !I_target_pink) O_color=24'hffffff;
      else case(mode_display)
        2'b00: O_color=24'h00efff;
        2'b01: O_color=24'hffff00;
        2'b10: O_color=24'hffffff;
        default: O_color=24'h60ff80;
      endcase
    end
  end
endmodule
