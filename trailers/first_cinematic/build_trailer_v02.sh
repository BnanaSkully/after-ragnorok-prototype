#!/usr/bin/env bash
# After Ragnarok - teaser v02 build script. Needs ffmpeg. Run from this folder.
# Sources are copies of the HeyOz/Seedance clips in src/ (originals untouched).
set -e
W=1920; H=1080; FPS=24; XF=0.7
TITLEFONT="${TITLEFONT:-/usr/share/fonts/truetype/google-fonts/Lora-Variable.ttf}"
TAGFONT="${TAGFONT:-/usr/share/fonts/truetype/google-fonts/Lora-Italic-Variable.ttf}"
mkdir -p work
wide() { # 16:9 source -> 1080p, lanczos, slight cool grade
  ffmpeg -v error -y -ss ${3:-0} -t $2 -i "$1" -an -vf "scale=$W:$H:flags=lanczos:force_original_aspect_ratio=increase,crop=$W:$H,fps=$FPS,eq=saturation=0.92,format=yuv420p" -c:v libx264 -crf 16 -preset veryfast "$4"; }
square() { # square source -> centred 1080x1080 over a blurred, darkened extension of itself
  ffmpeg -v error -y -ss ${3:-0} -t $2 -i "$1" -an -filter_complex "[0:v]split[a][b];[a]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,gblur=sigma=40,eq=brightness=-0.32:saturation=0.45[bg];[b]scale=$H:$H:flags=lanczos[fg];[bg][fg]overlay=(W-w)/2:0,fps=$FPS,format=yuv420p" -c:v libx264 -crf 16 -preset veryfast "$4"; }
wide   src/s1_midgard.mp4 5.0 0 work/1.mp4
wide   src/s4_skoll.mp4   5.0 0 work/4.mp4
wide   src/s5_sunna.mp4   5.0 0 work/5.mp4
# title card: black, title fades in, then the tagline
ffmpeg -v error -y -f lavfi -i "color=c=0x05070a:s=${W}x${H}:r=$FPS:d=6" -vf "drawtext=fontfile=$TITLEFONT:text='A F T E R   R A G N A R O K':fontsize=92:fontcolor=0xE8D9B0:x=(w-text_w)/2:y=(h-text_h)/2-40:alpha='if(lt(t,0.9),0,min(1,(t-0.9)/1.4))',drawtext=fontfile=$TAGFONT:text='The world ended. The struggle did not.':fontsize=44:fontcolor=0xA9B3BD:x=(w-text_w)/2:y=(h/2)+70:alpha='if(lt(t,2.6),0,min(1,(t-2.6)/1.2))',fade=t=out:st=5.4:d=0.6,format=yuv420p" -c:v libx264 -crf 16 -preset veryfast work/6.mp4
# chain: Midgard -> Skoll -> Sunna -> title
ffmpeg -v error -y -i work/1.mp4 -i work/4.mp4 -i work/5.mp4 -i work/6.mp4 -filter_complex "\
[0:v]fade=t=in:st=0:d=1.0[v0];\
[v0][1:v]xfade=transition=fadeblack:duration=1.0:offset=4.2[a];\
[a][2:v]xfade=transition=fade:duration=1.0:offset=8.2[b];\
[b][3:v]xfade=transition=fadeblack:duration=0.8:offset=12.4,format=yuv420p[v]" -map "[v]" -c:v libx264 -crf 17 -preset medium -r $FPS work/picture.mp4
# --- synthesized sound design (generated here, no third-party audio) ---
SR=48000
ffmpeg -v error -y \
 -f lavfi -i "anoisesrc=c=brown:a=0.5:d=19:r=$SR" \
 -f lavfi -i "aevalsrc='0.7*sin(2*PI*(28+3.5*t)*t)':d=19:s=$SR" \
 -f lavfi -i "aevalsrc='(0.16*sin(2*PI*220*t)+0.10*sin(2*PI*329.6*t)*gte(t,1.2)+0.09*sin(2*PI*440*t)*gte(t,2.4)+0.07*sin(2*PI*523.3*t)*gte(t,3.4))*(1+0.15*sin(2*PI*5*t))':d=6:s=$SR" \
 -f lavfi -i "aevalsrc='0.9*sin(2*PI*44*t)*exp(-1.6*t)+0.5*sin(2*PI*66*t)*exp(-2.2*t)':d=6:s=$SR" \
 -filter_complex "\
[0:a]asplit=2[n1][n2];\
[n1]lowpass=f=900,highpass=f=150,volume='0.55*(0.6+0.4*sin(2*PI*0.21*t))':eval=frame,afade=t=in:d=2,afade=t=out:st=4.3:d=1.5,atrim=0:6[wind];\
[1:a]atrim=0:5.4,lowpass=f=120,afade=t=in:st=0:d=3.5,afade=t=out:st=4.4:d=1,volume=0.9,adelay=4200|4200[swell];\
[n2]atrim=0:5.4,asetpts=PTS-STARTPTS,lowpass=f=260,volume='0.9*(0.5+0.5*sin(2*PI*17*t))':eval=frame,afade=t=in:st=1.5:d=2.2,afade=t=out:st=4.4:d=1,adelay=4200|4200[growl];\
[2:a]afade=t=in:d=1.0,afade=t=out:st=4.6:d=1.4,aecho=0.8:0.8:240|480:0.4|0.3,lowpass=f=3000,volume=0.8,adelay=8200|8200[sunna];\
[3:a]lowpass=f=200,volume=1.0,adelay=13300|13300[impact];\
[wind][swell][growl][sunna][impact]amix=inputs=5:normalize=0,afade=t=out:st=17:d=1.4,alimiter=limit=0.85,atrim=0:18.4[aout]" \
 -map "[aout]" -c:a pcm_s16le work/sound.wav
ffmpeg -v error -y -i work/picture.mp4 -i work/sound.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart After_Ragnarok_Teaser_v02.mp4
echo done
