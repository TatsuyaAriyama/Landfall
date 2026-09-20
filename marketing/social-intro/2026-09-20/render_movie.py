#!/usr/bin/env python3
"""Edit newly recorded Simulator footage into the requested 40-second film.
Requires Pillow and ffmpeg (or imageio-ffmpeg). Does not generate app UI.
"""
from pathlib import Path
import argparse, json, os, shutil, subprocess
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
FFMPEG=os.environ.get('FFMPEG') or shutil.which('ffmpeg')
if not FFMPEG:
    import imageio_ffmpeg
    FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
FONT='/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc'
FONT_EN='/System/Library/Fonts/Avenir Next.ttc'
# All coordinates refer to actual 1206x2622 Simulator video frames.
SHOTS=[
    dict(name='home',source='departure-final.mov',start=23.0,source_duration=3.0,duration=3.0,caption='学ぶことを、選んで。'),
    dict(name='select',source='departure-final.mov',start=27.0,source_duration=6.0,duration=3.0,caption='学ぶことを、選んで。'),
    dict(name='departure',source='departure-final.mov',start=33.0,source_duration=10.0,duration=8.0,caption='さあ、出航。'),
    dict(name='voyage',source='voyage-take.mov',start=14.0,source_duration=6.0,duration=6.0,caption='学ぶ時間が、航海になる。'),
    dict(name='complete',source='voyage-take.mov',start=58.0,source_duration=5.0,duration=5.0,caption=''),
    dict(name='return',source='voyage-take.mov',start=68.0,source_duration=7.0,duration=7.0,caption='今日の学びを、持ち帰ろう。'),
    dict(name='bench',source='bench-final.mov',start=60.0,source_duration=8.0,duration=8.0,caption='おつかれさま。'),
]

def run(args):
    subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y',*args],check=True)

def overlay(shot,h,path):
    im=Image.new('RGBA',(1080,h))
    d=ImageDraw.Draw(im)
    txt=shot['caption']
    if txt:
        fs=46 if h==1920 else 40
        f=ImageFont.truetype(FONT,fs)
        y=1530 if h==1920 else 1055
        if shot['name']=='bench': y=1640 if h==1920 else 1100
        box=d.textbbox((0,0),txt,font=f)
        tw=box[2]-box[0]
        x=(1080-tw)//2
        d.rounded_rectangle((x-28,y-16,x+tw+28,y+fs+26),radius=20,fill=(13,55,51,212))
        d.text((x,y-box[1]+3),txt,font=f,fill=(251,247,231,255))
    if shot['name']=='bench':
        f=ImageFont.truetype(FONT_EN,54 if h==1920 else 46)
        txt='KeelMira'; box=d.textbbox((0,0),txt,font=f); tw=box[2]-box[0]
        y=145 if h==1920 else 95
        d.text(((1080-tw)/2,y),txt,font=f,fill=(16,65,59,255))
    im.save(path)

def render(fmt, reuse=False):
    h=1920 if fmt=='tiktok' else 1350
    work=HERE/'work'/fmt;work.mkdir(parents=True,exist_ok=True)
    parts=[]
    for i,s in enumerate(SHOTS):
        dst=work/f'{i:02d}-{s["name"]}.mp4'
        png=work/f'{i:02d}-caption.png'
        previous=png.read_bytes() if png.exists() else None
        overlay(s,h,png)
        stamp=work/f'{i:02d}-shot.json'
        serialized=json.dumps(s,sort_keys=True)
        if reuse and dst.exists() and previous==png.read_bytes() and stamp.exists() and stamp.read_text()==serialized:
            parts.append(dst)
            continue
        rate=s['duration']/s['source_duration']
        base=f'[0:v]setpts={rate:.9f}*(PTS-STARTPTS),fps=30'
        if s['name']=='bench':
            crop='crop=806:1432:200:530' if h==1920 else 'crop=1080:1350:64:580'
            vf=base+f',{crop},scale=1080:{h}:flags=lanczos,setsar=1[scene];'
        else:
            bh=240 if h==1920 else 168
            vf=base+',crop=1206:2342:0:200,split=2[main][blur];'
            vf+=f'[main]scale=-2:{h}:flags=lanczos,setsar=1[fg];'
            vf+=f'[blur]scale=136:{bh}:force_original_aspect_ratio=increase,crop=136:{bh},boxblur=8:1,scale=1080:{h},eq=brightness=-0.05:saturation=0.75[bg];'
            vf+='[bg][fg]overlay=(W-w)/2:0:shortest=1,setsar=1[scene];'
        vf+='[scene][1:v]overlay=0:0:shortest=1,format=yuv420p[out]'
        run(['-ss',str(s['start']),'-t',str(s['source_duration']),'-i',str(HERE/'raw'/s['source']),
             '-loop','1','-framerate','30','-i',str(png),'-filter_complex_threads','2','-filter_complex',vf,
             '-map','[out]','-t',str(s['duration']),'-an','-c:v','libx264','-preset','veryfast','-crf','19',
             '-threads','4','-r','30','-video_track_timescale','30000',str(dst)])
        stamp.write_text(serialized)
        parts.append(dst)
        print(fmt,s['name'],'done',flush=True)
    concat=work/'parts.txt'
    concat.write_text(''.join("file '"+str(p)+"'\n" for p in parts))
    silent=work/'picture.mp4'
    run(['-f','concat','-safe','0','-i',str(concat),'-c','copy',str(silent)])
    target=HERE/f'KeelMira-{fmt}-40s.mp4'
    music=REPO/'Landfall/Resources/harbor_minuet_main_theme.m4a'
    run(['-i',str(silent),'-i',str(music),'-map','0:v:0','-map','1:a:0','-c:v','copy',
         '-af','volume=0.85,afade=t=in:st=0:d=0.8,afade=t=out:st=37.5:d=2.5',
         '-c:a','aac','-b:a','192k','-t','40','-movflags','+faststart',str(target)])
    print('DONE',target,flush=True)
    run(['-ss','33.5','-i',str(target),'-frames:v','1',str(HERE/f'poster-{fmt}.jpg')])
    return target

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--format',choices=['tiktok','x','both'],default='both');p.add_argument('--reuse',action='store_true',help='Reuse previously encoded clips only when video filters and source files are unchanged');args=p.parse_args()
    (HERE/'edit.json').write_text(json.dumps(SHOTS,ensure_ascii=False,indent=2)+'\n')
    for fmt in (['tiktok','x'] if args.format=='both' else [args.format]): render(fmt,args.reuse)
