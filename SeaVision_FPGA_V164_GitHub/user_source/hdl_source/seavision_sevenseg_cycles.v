// SeaVision V1.4.6: display full detector cycle count on board 8-digit 7seg.
// HX1P35A board manual: COMMON ANODE; DIG0..7=a..g,dp ACTIVE LOW;
// SEL0..7 drive PNP9012 bases: ACTIVE LOW (board schematic P04_DIG_LED).
// Manual prose disagrees with schematic and supplied seg_led.v. SW6 UP selects 7seg.
// This is only a readout of the existing `capture_cycles` metadata.
// No SVM, image processing, division or multiplication datapath is added.
// One 27-cycle double-dabble conversion per frame; one digit is scanned
// every approximately 1/(8*DIGIT_HZ) second, all 8 digits ~1kHz refresh.
module seavision_sevenseg_cycles #(
    parameter integer CLK_HZ=74250000,
    parameter integer DIGIT_HZ=1000,
    parameter integer DIGIT_ACTIVE_LOW=1
)(
    input wire clk,
    input wire rst_n,
    input wire frame_start,
    input wire [31:0] capture_cycles,
    output reg [7:0] seg_n,
    output reg [7:0] digit_en
);
    // Synthesize a constant refresh divider; never a runtime divider.
    localparam integer SCAN_DIV_RAW=CLK_HZ/(DIGIT_HZ*8);
    localparam integer SCAN_DIV=(SCAN_DIV_RAW<2) ? 2 : SCAN_DIV_RAW;
    // 14 bits handles SCAN_DIV=9281 at 74.25MHz/8kHz.
    localparam integer SCAN_BITS=$clog2(SCAN_DIV);
    localparam integer BLANK=(SCAN_DIV>16)?8:1;
    reg [SCAN_BITS-1:0] scan_tick_count;
    reg [2:0] scan_index;

    // Saturate at 99,999,999 to fit 8 decimal digits without rollover.
    wire [26:0] captured_saturated=(capture_cycles>32'd99999999) ?
                                    27'd99999999 : capture_cycles[26:0];
    reg [26:0] bin_shift;
    reg [31:0] bcd_work, bcd_display;
    reg [4:0] conv_remaining;
    reg conv_busy;

    function [31:0] add3_all;
        input [31:0] val;
        reg [31:0] adjusted;
        integer i;
        begin
            adjusted=val;
            for(i=0;i<8;i=i+1) begin
                if(adjusted[i*4 +: 4]>=4'd5)
                    adjusted[i*4 +: 4]=adjusted[i*4 +: 4]+4'd3;
            end
            add3_all=adjusted;
        end
    endfunction
    wire [31:0] bcd_adjusted=add3_all(bcd_work);
    wire [31:0] bcd_next={bcd_adjusted[30:0],bin_shift[26]};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bin_shift<=27'd0;
            bcd_work<=32'd0;
            bcd_display<=32'd0;
            conv_remaining<=5'd0;
            conv_busy<=1'b0;
            scan_tick_count<=0;
            scan_index<=3'd0;
        end else begin
            // Frame metadata changes only at SOF. Conversion finishes in 27
            // pixel clocks, much shorter than the frame interval.
            if(frame_start && !conv_busy) begin
                bin_shift<=captured_saturated;
                bcd_work<=32'd0;
                conv_remaining<=5'd27;
                conv_busy<=1'b1;
            end else if(conv_busy) begin
                bcd_work<=bcd_next;
                bin_shift<={bin_shift[25:0],1'b0};
                conv_remaining<=conv_remaining-1'b1;
                if(conv_remaining==5'd1) begin
                    bcd_display<=bcd_next; // atomic display update
                    conv_busy<=1'b0;
                end
            end

            if(scan_tick_count==SCAN_DIV-1) begin
                scan_tick_count<=0;
                scan_index<=scan_index+1'b1;
            end else begin
                scan_tick_count<=scan_tick_count+1'b1;
            end
        end
    end

    reg [3:0] current_digit;
    reg [7:0] active_high_pattern;
    always @(*) begin
        // Digit 0 (SEL0) is leftmost, most significant decimal digit.
        case(scan_index)
          3'd0:current_digit=bcd_display[31:28];
          3'd1:current_digit=bcd_display[27:24];
          3'd2:current_digit=bcd_display[23:20];
          3'd3:current_digit=bcd_display[19:16];
          3'd4:current_digit=bcd_display[15:12];
          3'd5:current_digit=bcd_display[11:8];
          3'd6:current_digit=bcd_display[7:4];
          default:current_digit=bcd_display[3:0];
        endcase
        // Pattern bits = {dp,g,f,e,d,c,b,a}, HIGH would illuminate segment.
        case(current_digit)
          4'd0:active_high_pattern=8'h3f;
          4'd1:active_high_pattern=8'h06;
          4'd2:active_high_pattern=8'h5b;
          4'd3:active_high_pattern=8'h4f;
          4'd4:active_high_pattern=8'h66;
          4'd5:active_high_pattern=8'h6d;
          4'd6:active_high_pattern=8'h7d;
          4'd7:active_high_pattern=8'h07;
          4'd8:active_high_pattern=8'h7f;
          4'd9:active_high_pattern=8'h6f;
          default:active_high_pattern=8'h00;
        endcase
        // Registered break-before-make scanning: blank before/after segment change.
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            seg_n<=8'hff;
            digit_en<=DIGIT_ACTIVE_LOW ? 8'hff : 8'h00;
        end else begin
            if(scan_tick_count==0) begin
                digit_en<=DIGIT_ACTIVE_LOW ? 8'hff : 8'h00;
                seg_n<=8'hff;
            end else if(scan_tick_count==BLANK) begin
                seg_n<=~active_high_pattern;
            end else if(scan_tick_count==BLANK+1) begin
                digit_en<=DIGIT_ACTIVE_LOW ? ~(8'b1 << scan_index) : (8'b1 << scan_index);
            end
        end
    end
endmodule
