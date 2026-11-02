from pathlib import Path
import json, re, math, hashlib
r=Path(__file__).resolve().parent
s=(r/'user_source/hdl_source/seavision_mode_osd.v').read_text(encoding='utf-8')
entries=re.findall(r"8'h([0-9A-F]{2}): prob_bcd=12'h([0-9]{3});",s)
assert len(entries)==256, len(entries)
for i,(key,p) in enumerate(entries):
    assert int(key,16)==i
    pct=int(p)/10
    raw=(i<<8)+128
    sigmoid=1/(1+math.exp(-(0.8222570626423183+0.000026900141250656862*raw)))
    assert abs(pct-(100*sigmoid))<.051
    if i: assert int(entries[i-1][1])<=int(p)
assert "4'd13:glyph_char=" + chr(34) + "." + chr(34) + ";" in s
assert "4'd14:glyph_char=8'd48+p_tenth;" in s
assert "4'd15:glyph_char=" + chr(34) + "%" + chr(34) + ";" in s
assert "wire [4:0] score_char_idx" in s
assert "wire [15:0] score_gap_up" in s
assert "wire [3:0] p_tens=prob_bcd[11:8];" in s
assert "(I_target_pink==1'b0)" in s and "hud_target_present" in s
assert "16'd128" in s
D=(r/'user_source/hdl_source/seavision_urchin_detector_lite.v').read_text(encoding='utf-8')
assert 'svm_positive>=svm_negative' in D and "+32'd1121" in D
print('PASS: 256 monotonic calibrated lookup entries')
print('PASS: 0.1% decimal formatting, no display when absent/pink')
print('PASS: original SVM logic still present')
print('NOTE: LUT quality poor on old held-out data; static check NOT TD synthesis')
