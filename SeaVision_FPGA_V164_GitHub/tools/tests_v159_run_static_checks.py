# coding: utf-8
"""Only STATIC checks and Python behavioral models; no RTL simulator invoked."""
from pathlib import Path
import hashlib,re
R=Path(__file__).resolve().parents[1]
H=R/'user_source/hdl_source'
EXPECTED={'seavision_urchin_detector_lite.v': '229660cb0689c96cfc2c7943053cc4674f1e0b72955f5b76d606c1cd66a6e03c', 'seavision_urchin_stream_tap.v': 'e2401deec31400523c3328b77b76ae3de26bc7f60c018acd06d3c1687a8a442d', 'seavision_pink_tracker.v': '6e1bf21cecf2de3dbed71bd534d29bbb7a5b724d3bbcefce8900d55affec17af', 'seavision_adaptive_tone.v': 'c40edbc3757ff34e5f407409c04d32af5b8a7f2a11ddbbc1d44083cf84f784e2', 'seavision_hdmi_display_modes.v': 'eaaf730e2c5fb0bb40f8884ac5e4512ed4fc737d3e11e80c86d3350af402bf2d', 'seavision_b2_video_bridge.v': '457817743976d8a9ce147fa56810dd9feb4be3cb9546e13e0aa7da07182f3456', 'osd_char_lib.v': 'afbf003fff419b4f8f41da4aba05bbb66df4bd93de602fbab9197ebca2ec523b'}
for name,sha in EXPECTED.items():
    assert hashlib.sha256((H/name).read_bytes()).hexdigest()==sha, name+' CHANGED'
print('PASS core immutable source hashes:',len(EXPECTED))
for x in ['seavision_frame_latency.v','seavision_sevenseg_latency.v']:
    assert x in (R/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8-sig')
for st in ('syn_1','phy_1'):
    project=(R/f'build_config/{st}/camera_to_dsi_display.prj').read_text()
    for x in ['seavision_frame_latency.v','seavision_sevenseg_latency.v']:
        assert x in project,(st,x)
print('PASS TD GUI and syn/phy batch project references')
def double_dabble(value):
    digits=[0,0,0,0]
    for shift in range(13,-1,-1):
        for i in range(4):
            if digits[i]>=5: digits[i]+=3
        carry=(value>>shift)&1
        for i in range(3,-1,-1):
            q=(digits[i]<<1)|carry
            digits[i]=q&15;carry=(q>>4)&1
    return sum(x*10**(3-i) for i,x in enumerate(digits))
for value in [0,1,9,10,17,99,127,523,999,1000,9999]:
    assert double_dabble(value)==value
print('PASS BCD decimal model')
assert (200-65500)&65535==236
assert (11001-1000)&65535>9999
print('PASS latency counter rollover/timeout model')
def roi(seq):
    hit=False;miss=0;states=[]
    for found in seq:
        if found:hit=True;miss=0
        elif miss<3:miss+=1
        else:hit=False
        states.append(hit)
    return states
assert roi([1,0,0,0,0,0])==[True,True,True,True,False,False]
assert roi([1,0,1])==[True,True,True]
print('PASS ROI missed-frame hold model')
s=(H/'design_top_wrapper.v').read_text()
assert '.CLK_HZ(75000000)' in s
assert '.latency_tenths_ms(lat_pipeline_tenths)' in s
s=(H/'hdmi_mixer.v').read_text()
assert "24'hff3030" in s and 'S_urchin_roi_found' in s
print('PASS ROI/7seg wiring check')
print('STATIC VALIDATION COMPLETED; RTL, TD SYNTHESIS AND ON-BOARD TESTS NOT RUN')
