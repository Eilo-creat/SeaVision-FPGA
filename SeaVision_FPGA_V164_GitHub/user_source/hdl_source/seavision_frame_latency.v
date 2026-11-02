// SeaVision V158 - video data-path latency (not optical end-to-end latency).
// Input: first accepted ISP frame into DDR writer, timestamped in DDR clock domain.
// Output: first active HDMI pixel of the bank chosen by DDR reader, synchronized
// to DDR clock. Matching by 4-buffer bank ID is necessary: naive SOF subtraction
// can pair unrelated camera/HDMI frames.
// No RGB pixels, DDR transactions, FSM transitions, SVM, or video timing are changed.
// Units: 0.1 ms; converter uses only one constant-modulus prescaler (no divider).
// Clock check: verify DDR_HZ against generated TD DDR/PLL settings before quoting ms.
module seavision_frame_latency #(
    parameter integer DDR_HZ=133333333
)(
    input wire ddr_clk, rst_n,
    input wire wr_sof, input wire [1:0] wr_bank,
    input wire rd_sof, input wire [1:0] rd_bank,
    input wire hdmi_clk, hdmi_rst_n, hdmi_sof,
    output reg [15:0] latency_tenth_ms_hdmi,
    output reg latency_valid_hdmi
);
    localparam integer PRESCALE = (DDR_HZ + 5000)/10000;
    localparam integer PRESCALE_W = $clog2(PRESCALE + 1);
    reg [PRESCALE_W-1:0] prescaler;
    reg [15:0] time_tenths;
    reg [15:0] bank_start [0:3];
    reg [3:0] bank_has_stamp;
    reg [15:0] selected_start;
    reg selected_valid;
    reg published_valid;

    // HDMI event toggle crossing into faster DDR clock without lost 1-cycle pulses.
    reg output_toggle;
    always @(posedge hdmi_clk or negedge hdmi_rst_n) begin
        if(!hdmi_rst_n) output_toggle<=1'b0;
        else if(hdmi_sof) output_toggle<=~output_toggle;
    end
    (* async_reg = "true" *) reg out_meta, out_sync;
    reg out_seen;
    reg [15:0] published_tenths;
    reg request_toggle;
    (* async_reg = "true" *) reg ack_meta, ack_sync;
    reg ack_toggle;
    integer i;
    always @(posedge ddr_clk or negedge rst_n) begin
        if(!rst_n)begin
            prescaler<=0;time_tenths<=0;
            bank_has_stamp<=0; selected_start<=0;selected_valid<=0;published_valid<=0;
            out_meta<=0;out_sync<=0;out_seen<=0;
            published_tenths<=0;request_toggle<=0;
            ack_meta<=0;ack_sync<=0;
            for(i=0;i<4;i=i+1)bank_start[i]<=0;
        end else begin
            if(prescaler==PRESCALE-1)begin
                prescaler<=0;time_tenths<=time_tenths+16'd1;
            end else prescaler<=prescaler+1'b1;
            // Snapshot the same bank that the DDR writer is actually targeting.
            if(wr_sof)begin
                bank_start[wr_bank]<=time_tenths;
                bank_has_stamp[wr_bank]<=1'b1;
            end
            // Read pointer captured at real DDR frame-read-start, not sampled later.
            if(rd_sof)begin
                // Capture source timestamp at buffer-selection time; never
                // re-read a potentially overwritten bank at HDMI SOF.
                selected_start<=bank_start[rd_bank];
                selected_valid<=bank_has_stamp[rd_bank];
            end
            out_meta<=output_toggle;
            out_sync<=out_meta;
            ack_meta<=ack_toggle;
            ack_sync<=ack_meta;
            if(out_sync != out_seen)begin
                out_seen<=out_sync;
                if(request_toggle==ack_sync)begin
                    // Reject a buffer without a known source stamp or with an
                    // implausibly old (>999.9 ms) timestamp. Preserve wrap
                    // arithmetic for the 16-bit 0.1ms free-running counter.
                    published_tenths<=time_tenths-selected_start;
                    published_valid<=selected_valid &&
                        ((time_tenths-selected_start)<=16'd9999);
                    request_toggle<=~request_toggle;
                end
            end
        end
    end
    (* async_reg = "true" *) reg req_meta, req_sync;
    reg req_seen;
    // Handshake: data is stable for two HDMI clock cycles before req_sync
    // changes; DDR cannot overwrite it until acknowledgement comes back.
    always @(posedge hdmi_clk or negedge hdmi_rst_n) begin
        if(!hdmi_rst_n)begin
            req_meta<=0;req_sync<=0;req_seen<=0;ack_toggle<=0;
            latency_tenth_ms_hdmi<=0;latency_valid_hdmi<=0;
        end else begin
            req_meta<=request_toggle;
            req_sync<=req_meta;
            if(req_sync!=req_seen)begin
                req_seen<=req_sync;
                latency_tenth_ms_hdmi<=published_tenths;
                latency_valid_hdmi<=published_valid;
                ack_toggle<=req_sync;
            end
        end
    end
endmodule
