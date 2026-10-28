#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/build/Freefield.app/Contents/MacOS/Freefield"
OUT=${OUT:-${TMPDIR:-/tmp}/freefield-sweep}
FF="$ROOT/build/debug-hook"
[[ -x $FF ]] || swiftc -O -o "$FF" "$ROOT/scripts/dev/debug-hook.swift" || exit 1
mkdir -p "$OUT"
TARGETS=(home library favorites characters products styles apps usage settingsview
  tool:create tool:storyboard tool:photoSession tool:edit tool:inpaint tool:drawToEdit tool:editText tool:upscale tool:relight
  tool:colorGrade tool:angles tool:expand tool:background tool:faceSwap tool:characterSwap tool:outfitSwap
  video:createVideo video:animateImage video:cinemaStudio video:drawToVideo video:editVideo video:extendVideo
  video:hookCheck video:joinClips video:motionTransfer video:reframeVideo video:storyboardVideo video:swapVideo
  video:talkingAvatar video:transitions video:upscaleVideo video:videoAd video:videoEffects video:colorGradeVideo
  ad:ugc-photo ad:model-shoot ad:product-shoot ad:unboxing ad:before-after ad:testimonial ad:static-ad ad:hook-frame
  ad:carousel ad:marketplace ad:recreate-ad ad:ad-batch ad:ad-headlines ad:ad-resize ad:ad-translate ad:ad-multiply)
[[ -n $ONLY ]] && TARGETS=(${=ONLY})
snap() { $FF snap "$1"; sleep 1.6; }
for lang in ${=LANGS:-es en}; do
  pkill -x Freefield; sleep 1.5
  "$APP" -AppleLanguages "($lang)" >/dev/null 2>&1 &
  sleep 9
  $FF navigate dismiss; sleep 0.5
  for size in ${=SIZES:-narrow wide}; do
    case $size in
      narrow) $FF navigate winsize:980x944 ;;
      small) $FF navigate winsize:980x640 ;;
      *) $FF navigate winsize:1800x944 ;;
    esac
    sleep 1.2
    for t in $TARGETS; do
      name=${t//:/-}
      $FF navigate $t; sleep 1.6
      snap $OUT/$lang-$size-$name-a.png
      if [[ $size == narrow ]]; then
        $FF navigate scrollpage:0.5; sleep 0.6; snap $OUT/$lang-$size-$name-b.png
        $FF navigate scrollpage:1; sleep 0.6; snap $OUT/$lang-$size-$name-c.png
        $FF navigate scrollpage:0; sleep 0.3
      fi
    done
  done
done
echo DONE
