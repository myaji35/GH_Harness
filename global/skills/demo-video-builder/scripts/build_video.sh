#!/usr/bin/env bash
# 단일 이미지시퀀스 방식 — concat 없이 한 번에 인코딩(경계 검은프레임 버그 회피)
set -e
SCRATCH="/private/tmp/claude-501/-Volumes-E-SSD-02-GitHub-nosync-0035-XimTier-ENG2/e6bbf34e-573b-4f05-aeac-6918ceee1ce1/scratchpad"
SCENES="$(cd "$(dirname "$0")" && pwd)/market_scenes"
NARR="$SCRATCH/mkt_narration"
WORK="$SCRATCH/vid_v2"
rm -rf "$WORK"; mkdir -p "$WORK/seq"

IDS=(intro s0 s1 s2 s3 s4 s5 s6 s7 s8 outro)
FPS=30
frame=0
: > "$WORK/audio_list.txt"

for id in "${IDS[@]}"; do
  aud="$NARR/${id}.mp3"
  img="$SCENES/scene_${id}.png"
  dur=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$aud")
  # 이 씬 프레임 수 = 음성길이 * fps (반올림)
  n=$(python3 -c "import math;print(math.ceil($dur*$FPS))")
  # 이미지를 n장 복제(연속 번호). 1280x720 letterbox는 이미 씬이미지가 맞춰짐
  for ((i=0;i<n;i++)); do
    printf -v out "%06d" "$frame"
    cp "$img" "$WORK/seq/${out}.png"
    frame=$((frame+1))
  done
  echo "file '$aud'" >> "$WORK/audio_list.txt"
  echo "  $id: ${dur}s ($n frames)"
done

# 오디오 이어붙이기(단일)
ffmpeg -y -f concat -safe 0 -i "$WORK/audio_list.txt" -c:a aac -b:a 192k "$WORK/audio.m4a" 2>/dev/null

# 이미지 시퀀스 + 오디오 → 한 번에 인코딩(경계 없음)
OUTFILE="$(cd "$(dirname "$0")" && pwd)/market_selftest.mp4"
# ★ 근본수정: keyframe 매초 강제(-g/-keyint_min/-sc_threshold 0) + main 프로파일 → 재생기 검은화면 방지
ffmpeg -y -framerate $FPS -i "$WORK/seq/%06d.png" -i "$WORK/audio.m4a" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p -g $FPS -keyint_min $FPS -sc_threshold 0 \
  -c:a copy -shortest -movflags +faststart \
  "$OUTFILE" 2>/dev/null

echo "완성: $OUTFILE"
ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$OUTFILE" 2>/dev/null | xargs printf "길이: %.1f초\n"
rm -rf "$WORK/seq"  # 프레임 정리(용량)
