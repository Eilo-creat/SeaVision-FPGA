create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# V152: bounded bundled-data CDC, not a clock-group-wide exception.
# held_command and request_toggle change together; held_command is frozen until
# the returning acknowledge crosses two pixel-clock synchronizer stages.
# Destination captures payload only after req_meta -> req_sync -> req_seen:
# earliest capture is two complete 42 ns ctrl periods after first sampling.
# Bound forward routing to 25 ns (<42 ns), leaving >=59 ns payload settling.
# request/ack first stages are synchronizers: do not require the incidental
# 0.674 ns edge spacing between these two derived clock frequencies.
# Subsequent synchronizer stages and every same-clock path remain timed normally.
set ae_forward_nets [get_nets -hier -regexp {^u_exposure_meter/(held_command\[[01]\]|request_toggle)$}]
set ae_return_net [get_nets -hier -regexp {^u_exposure_meter/ack_toggle$}]
if {[llength $ae_forward_nets] != 3} {error "Exposure CDC: expected 3 forward nets"}
if {[llength $ae_return_net] != 1} {error "Exposure CDC: expected 1 acknowledge net"}
set_max_delay -datapath_only -from [get_clocks HDMI_PIXEL_CLK] -through $ae_forward_nets -to [get_clocks pll_clk_24m] 25.000
set_max_delay -datapath_only -from [get_clocks pll_clk_24m] -through $ae_return_net -to [get_clocks HDMI_PIXEL_CLK] 10.000

# V156: frame-held profile selection and acknowledged ready flag cross through
# two explicit synchronizer stages. Bound only the first-stage CDC paths;
# same-clock pixel logic and second-stage synchronizers remain fully timed.
set profile_forward [get_nets -hier -regexp {^pink_mode_frame$}]
set profile_return [get_nets -hier -regexp {^u_ae_set/O_profile_ready$}]
if {[llength $profile_forward] != 1} {error "Profile CDC: expected one mode net"}
if {[llength $profile_return] != 1} {error "Profile CDC: expected one ready net"}
set_max_delay -datapath_only -from [get_clocks HDMI_PIXEL_CLK] -through $profile_forward -to [get_clocks pll_clk_24m] 25.000
set_max_delay -datapath_only -from [get_clocks pll_clk_24m] -through $profile_return -to [get_clocks HDMI_PIXEL_CLK] 10.000
