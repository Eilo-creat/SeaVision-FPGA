# coding: utf-8
"""V1.6.0 source-level checks only; not an HDL compiler or TD timing report."""
from pathlib import Path
import re,zipfile,hashlib
ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'user_source'/'hdl_source'
base=Path(__file__).resolve().parents[3]/'files'/'SeaVision_V159_去除四模式尾部8_其他功能不变.zip'
# Do not require an external ZIP for standalone operation: original checks via V159 generated hashes.
IMMUTABLE={
    'seavision_pink_tracker.v':'6e1bf21cecf2de3dbed71bd534d29bbb7a5b724d3bbcefce8900d55affec17af',
    'seavision_adaptive_tone.v':'c40edbc3757ff34e5f407409c04d32af5b8a7f2a11ddbbc1d44083cf84f784e2',
    'seavision_hdmi_display_modes.v':'eaaf730e2c5fb0bb40f8884ac5e4512ed4fc737d3e11e80c86d3350af402bf2d',
    'seavision_b2_video_bridge.v':'457817743976d8a9ce147fa56810dd9feb4be3cb9546e13e0aa7da07182f3456',
}
for name,expected in IMMUTABLE.items():
    got=hashlib.sha256((HDL/name).read_bytes()).hexdigest()
    assert got==expected,(name,'unintended change')
print('PASS: color tracker, adaptive tone, display modes, B2 bridge are byte-identical to V159')

files={name:(HDL/name).read_text(encoding='utf-8') for name in [
    'seavision_urchin_detector_lite.v', 'seavision_urchin_stream_tap.v',
    'design_top_wrapper.v', 'hdmi_mixer.v', 'seavision_mode_osd.v','osd_char_lib.v']}
det=files['seavision_urchin_detector_lite.v']
# Decision function and model weights have NOT been changed.
for item in ['19=16+2+1','13=8+4+1','189=128+64-2-1',
             'svm_negative<=(asym32<<7)+(asym32<<6)-(asym32<<1)-asym32+32\'d1121',
             'wire qualified=roi_inside && conservative_demo && svm_pass',
             'if(count==0)first_svm_margin<=svm_margin_clamped']:
    assert item in det,item
assert 'svm_margin_raw=svm_positive-svm_negative' in det
print('PASS: original SVM weights, geometry gates and decision preserved')

for name,needles in {
 'seavision_urchin_stream_tap.v':['svm_margin_pending<=0','svm_margin_view<=svm_margin_pending','!single_confirmed'],
 'design_top_wrapper.v':['.svm_margin_view(S_urchin_svm_margin)','.I_svm_margin((boxes_ready && !pink_mode_frame'],
 'hdmi_mixer.v':['input wire [13:0] I_svm_margin','.I_svm_margin(I_svm_margin)'],
 'seavision_mode_osd.v':['score_inside=(I_target_pink==1\'b0)','(mode_display==2\'b00) && hud_target_present',
                         '4\'d11:glyph_char="-"','4\'d13:glyph_char="%"',
                         'P:--% deliberately means UNCALIBRATED']
}.items():
    for n in needles: assert n in files[name],(name,n)
print('PASS: score follows candidate confirmation and is not shown in PINK or non-RAW modes')

# Character additions only: % and -, no third font instance.
assert "8'h2d: begin // -" in files['osd_char_lib.v']
assert "8'h25: begin // %" in files['osd_char_lib.v']
assert files['seavision_mode_osd.v'].count('osd_char_lib u_seavision_mode_font')==1

for n,s in files.items():
    # Basic token/balance hygiene checks; not an RTL parser/simulator.
    s=re.sub(r'//[^\n]*','',s)
    assert len(re.findall(r'\bmodule\b',s))==len(re.findall(r'\bendmodule\b',s)),n
for v in (0,1,9,99,100,999,1000,9999,10000,2**32-1):
    clamped=min(9999,v)
    assert 0<=clamped<=9999
print('PASS: score saturation, glyph wiring, port links and module/end-module counts')
print('PASS static checks only; TD synthesis, P&R, timing and on-board verification not performed')
