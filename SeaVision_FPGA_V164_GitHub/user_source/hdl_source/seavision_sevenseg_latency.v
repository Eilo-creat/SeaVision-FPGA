// SeaVision V159: 8-digit latency readout, HDMI clock domain.
// Example 52.3 ms => "L 052.3 " (decimal point on digit 4).
// Invalid => "L ---.-- " (dashes; no measured value). Does NOT represent optical exposure/display latency.
// Uses a 14-cycle double-dabble for 0.1 ms units (0..9999 = 0..999.9 ms),
// saturates above 999.9 ms; no runtime divider, DSP or video-path modification.
module seavision_sevenseg_latency #(
    parameter integer CLK_HZ=75000000,
    parameter integer DIGIT_HZ=1000,
    parameter integer DIGIT_ACTIVE_LOW=1
)(
    input wire clk, rst_n, frame_start,
    input wire [15:0] latency_tenths_ms,
    input wire latency_valid,
    output reg [7:0] seg_n,
    output reg [7:0] digit_en
);
    localparam integer SCAN_DIV_RAW=CLK_HZ/(DIGIT_HZ*8);
    localparam integer SCAN_DIV=(SCAN_DIV_RAW<2) ? 2 : SCAN_DIV_RAW;
    localparam integer SCAN_BITS=$clog2(SCAN_DIV+1);
    localparam integer BLANK=(SCAN_DIV>16)?8:1;
    reg [SCAN_BITS-1:0] scan_count;
    reg [2:0] scan_index;
    wire [13:0] clamped=(latency_tenths_ms>16'd9999) ? 14'd9999 : latency_tenths_ms[13:0];
    reg [13:0] bin_shift;
    reg [15:0] bcd_work,bcd_display;
    reg [3:0] remaining;
    reg busy,display_valid,pending_valid;
    function [15:0] add3;
      input [15:0] v;
      reg [15:0] t;
      integer i;
      begin
        t=v;
        for(i=0;i<4;i=i+1)
          if(t[4*i+:4]>=4'd5) t[4*i+:4]=t[4*i+:4]+4'd3;
        add3=t;
      end
    endfunction
    wire [15:0] adjusted=add3(bcd_work);
    wire [15:0] bcd_next={adjusted[14:0],bin_shift[13]};
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin
        scan_count<=0;scan_index<=0;
        bin_shift<=0;bcd_work<=0;bcd_display<=0;
        remaining<=0;busy<=0;display_valid<=0;pending_valid<=0;
      end else begin
        if(frame_start && !busy)begin
          bin_shift<=clamped;
          bcd_work<=0;
          remaining<=4'd14;
          busy<=1'b1;
          pending_valid<=latency_valid; // commit together with BCD at 14th step
        end else if(busy)begin
          bin_shift<={bin_shift[12:0],1'b0};
          bcd_work<=bcd_next;
          remaining<=remaining-1'b1;
          if(remaining==4'd1)begin
            bcd_display<=bcd_next;
            display_valid<=pending_valid;
            busy<=0;
          end
        end
        if(scan_count==SCAN_DIV-1)begin
          scan_count<=0;scan_index<=scan_index+1'b1;
        end else scan_count<=scan_count+1'b1;
      end
    end
    // Slots 0..7: L, blank, 0,5,2(dot),3,blank,blank.
    reg [3:0] current; // 0..9 numeric, A=L, B=dash, C=blank
    reg [7:0] lit;
    always @(*) begin
      case(scan_index)
        3'd0:current=4'ha;
        3'd1:current=4'hc;
        3'd2:current=display_valid?bcd_display[15:12]:4'hb;
        3'd3:current=display_valid?bcd_display[11:8] :4'hb;
        3'd4:current=display_valid?bcd_display[7:4]  :4'hb;
        3'd5:current=display_valid?bcd_display[3:0] :4'hb;
        3'd6:current=4'hc;
        default:current=4'hc;
      endcase
      case(current)
        4'd0:lit=8'h3f;4'd1:lit=8'h06;4'd2:lit=8'h5b;
        4'd3:lit=8'h4f;4'd4:lit=8'h66;4'd5:lit=8'h6d;
        4'd6:lit=8'h7d;4'd7:lit=8'h07;4'd8:lit=8'h7f;
        4'd9:lit=8'h6f;4'ha:lit=8'h38; // capital L
        4'hb:lit=8'h40; // dash
        default:lit=8'h00;
      endcase
      if(scan_index==3'd4) lit[7]=1'b1; // 052.3: dot after the 2 digit
    end
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin seg_n<=8'hff;digit_en<=DIGIT_ACTIVE_LOW?8'hff:8'h00;end
      else if(scan_count==0)begin
        digit_en<=DIGIT_ACTIVE_LOW?8'hff:8'h00;
        seg_n<=8'hff;
      end else if(scan_count==BLANK)seg_n<=~lit;
      else if(scan_count==BLANK+1)
        digit_en<=DIGIT_ACTIVE_LOW?~(8'b1<<scan_index):(8'b1<<scan_index);
    end
endmodule
