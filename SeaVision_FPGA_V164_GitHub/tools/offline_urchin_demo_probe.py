from pathlib import Path
import cv2, hashlib, json, csv
import numpy as np

NAMES = '''d30282d5ad4acb182917c57800004482.jpg
7d6a3ae2856d898bb2009d10dfd474d9.jpg
1358591d8943177b15ee2b3a3c0b0e3b.jpg
3a4d6aa9b146aefe2b7bfa962951a76b.jpg
8a4b123af033e00227fd25fc5021fd91.jpg
326b816cb2f6fd6929a604433cab2301.jpg
501b6e46096572b98049dda51b160779.jpg
bcfabc2e93d37aa0e3ed17f4dcd86fce.jpg
bffe3eedcf22c682e861c0ba8b257c71.png
dfb880ef656acdd91bf3fdcb4b36b05e.png
9a1e7d5f08b2c5f5b53e82513d9af917.png
3fc57824498c4c4ab067192109332aaa.png
345fbc1709b4f91b0bd26f024ec2dc01.jpg
ac6f73a6ab1a6b9718ad675a6fac019a.jpg
caa100b337e20464ddb89adac08d7048.jpg
8b22aacc6ad0ccce9bf6ee88629482c2.jpg
259f84fde78bad89c41a1cc4ee0a888a.jpg
1ce7f102bfbb91ea233024fbdad6cfdc.jpg
dbfc52e467ece9cbe3dc77750bc45d43.jpg
636cc93d29c3f4d3cf5ed2126916f594.jpg
ea1c532215201c18755984b3045e2b16.jpg
cc70e4120d71d76486014c323a0f5ecc.jpg
dcbd3a77b2261d97ed86d294c685f34e.jpg'''.splitlines()

# PC recreation of key RTL rules, not a bit-exact iverilog simulation.
def analyze(fname, mode='stretch'):
    a=cv2.imdecode(np.fromfile(str(fname),dtype=np.uint8),cv2.IMREAD_COLOR)
    if a is None: raise ValueError(fname)
    rgb=cv2.cvtColor(a,cv2.COLOR_BGR2RGB)
    if mode=='stretch':
        px=cv2.resize(rgb,(320,180),interpolation=cv2.INTER_AREA)
    else:
        # 4:3 image inside 16:9 video frame with black side bars.
        scale=min(320/rgb.shape[1],180/rgb.shape[0]);w,h=int(round(rgb.shape[1]*scale)),int(round(rgb.shape[0]*scale))
        px=np.zeros((180,320,3),np.uint8);x0=(320-w)//2;y0=(180-h)//2
        px[y0:y0+h,x0:x0+w]=cv2.resize(rgb,(w,h),interpolation=cv2.INTER_AREA)
    avg=40960;prev=[];blobs=[]; overflow=0
    for y in range(180):
        curr=[];run_x0=None;run_x1=None;run_pixels=0;run_strong=False;gap=0
        def close_run():
            nonlocal run_x0,run_x1,run_pixels,run_strong,overflow
            if run_x0 is None or run_pixels<3 or not run_strong:return
            for l,r,bid in prev:
                if run_x0<=r+3 and l<=run_x1+3:
                    break
            else:bid=None
            if bid is None:
                if len(blobs)>=20:
                    overflow+=1;return
                bid=len(blobs);blobs.append(dict(pixels=0,rough=0,x0=run_x0,x1=run_x1,y0=y,y1=y))
                l=r=0
            b=blobs[bid]
            if b['pixels']>0:
                b['rough']+=abs(run_x0-l)+abs(run_x1-r)
            b['pixels']+=run_pixels
            b['x0']=min(b['x0'],run_x0);b['x1']=max(b['x1'],run_x1)
            b['y0']=min(b['y0'],y);b['y1']=max(b['y1'],y)
            if len(curr)<10:curr.append((run_x0,run_x1,bid))
            else:overflow+=1
        for x in range(320):
            r,g,b=map(int,px[y,x]);lum=(r>>2)+(g>>1)+(b>>2)
            mean=avg>>8
            th=max(28,min(125, (mean>>1)+(mean>>4)))
            dark=78<=x<=242 and 31<=y<=149 and lum<th and max(r,g,b)-min(r,g,b)<118
            strong=lum<max(0,th-8)
            delta=(lum*256-avg)>>9
            avg=(avg+delta)&0xffff
            if dark:
                if run_x0 is None:
                    run_x0=x;run_x1=x;run_pixels=1;run_strong=strong;gap=0
                else:
                    run_x1=x;run_pixels+=1;run_strong|=strong;gap=0
            elif run_x0 is not None:
                if gap==2:
                    close_run();run_x0=None;run_x1=None;run_pixels=0;run_strong=False;gap=0
                else:gap+=1
        if run_x0 is not None:close_run()
        prev=curr
    good=[]
    for b in blobs:
        w=b['x1']-b['x0']+1;h=b['y1']-b['y0']+1;area=w*h
        span=w+h;asym=abs(w-h)
        score=19*b['rough']+13*span-189*asym+2*b['pixels']-1121
        valid=(b['x0']>=82 and b['x1']<=238 and b['y0']>=35 and b['y1']<=145 and b['pixels']>=50 and 
               b['pixels']*4<=area*3 and w<=320/3 and h<=180/2 and b['rough']>=span//4 and
               score>=0 and b['pixels']>=22 and w>=26 and h>=17 and w<=160 and h<=120 and
               w<=2*h and h<=2*w and b['pixels']*16>=area*5 and b['pixels']*16<=area*14)
        b.update(score=int(score),passed=bool(valid),w=w,h=h)
        if valid:good.append(b)
    return {'detected':bool(good),'n_accepted':len(good),'n_proposals':len(blobs),'overflow':overflow,
            'max_margin': max((b['score'] for b in good),default=None),'top_candidate': (max(blobs,key=lambda z:z['score']) if blobs else None)}

def main():
    unique={}; rows=[]
    for n in NAMES:
        f=Path('/mnt/data')/n
        if not f.is_file():print('MISSING',f);continue
        hs=hashlib.sha256(f.read_bytes()).hexdigest();
        unique.setdefault(hs,[]).append(n)
        if n!=unique[hs][0]:continue
        res=analyze(f,'stretch')
        res['name']=n;res['duplicates']=len(unique[hs]);rows.append(res)
        print(n,'passed',res['detected'],'proposals',res['n_proposals'],'score',res['max_margin'],'overflow',res['overflow'])
    print('Total uploaded',sum(map(len,unique.values())),'Unique',len(unique),'PC-stretch passed',sum(x['detected'] for x in rows))
    out=Path('/mnt/data/demo_offline_probe');out.mkdir(exist_ok=True)
    with (out/'per_unique_image.json').open('w',encoding='utf8') as g:json.dump(rows,g,indent=2,ensure_ascii=False)
    with (out/'SUMMARY.txt').open('w',encoding='utf8') as g:g.write(f'Uploaded {sum(map(len,unique.values()))}, distinct {len(unique)}; PC RTL-inspired 320x180 full-frame stretch pass {sum(x["detected"] for x in rows)}/{len(rows)}\nNot bit-exact nor same as viewing phone image through SC520. Not full system accuracy. Many frames are near-identical. This is not SVM training or class probability.\n')
if __name__=='__main__':main()
