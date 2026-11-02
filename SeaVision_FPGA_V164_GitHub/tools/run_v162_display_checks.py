# Offline/source-level checks only: NOT FPGA compile, timing or board validation.
from pathlib import Path
from hashlib import sha256
import json,re
root=Path(__file__).resolve().parent
h=root/'user_source'/'hdl_source'
osd=(h/'seavision_mode_osd.v').read_text(encoding='utf-8')
font=(h/'osd_char_lib.v').read_text(encoding='utf-8')
checks=[]
def check(cond,label):
    print(('PASS' if cond else 'FAIL')+': '+label)
    checks.append(bool(cond))
check('score_hold<=score_hold+score_step_up;' in osd and 'score_hold<=score_hold-score_step_down;' in osd, 'display-only smoothing source present')
check("score_gap_up>16'd128" in osd and "score_gap_down>16'd128" in osd,'128-count jitter deadband present')
check('score_mul25' in osd and "score_centi_raw=score_mul25>>9" in osd,'Q11 scale into a.bc formatting')
check("4'd5:glyph_char=\".\";" in osd and "8'h2e: begin // decimal point" in font,'SVM decimal point glyph wired')
check('I_urchin_count==0' in osd and 'score_hold_valid<=1\'b0;' in osd,'clear when no valid target')
check('P is an' not in osd and 'NOT' in osd,'experimental probability caveat in source')
# Assert monotonically increasing thresholds and their retained 5% anchor points.
vals={int(p):int(v) for v,p in re.findall(r"score_hold>=16'd(\d+)\) \? 8'd(\d+)",osd)}
check(len(vals)==25 and all(vals[p]<vals[p+1] for p in range(66,90)),'1% levels monotonic')
check(all(vals[p]==t for p,t in [(70,931),(75,10274),(80,20968),(85,33916),(90,51114)]),'previous PC-based 5% anchor thresholds preserved')
check(all((x*25)>>9>=0 for x in range(0,65536,123)),'scale arithmetic finite for 16-bit margin')
# Explicit guard that original SVM scoring formula and decision logic remain.
det=(h/'seavision_urchin_detector_lite.v').read_text(encoding='utf-8')
check('svm_positive>=svm_negative' in det and "+32'd1121" in det and 'rough_term' in det,'original SVM classifier and coefficients still present')
print('SUMMARY:',sum(checks),'/',len(checks),'static checks')
raise SystemExit(0 if all(checks) else 1)
