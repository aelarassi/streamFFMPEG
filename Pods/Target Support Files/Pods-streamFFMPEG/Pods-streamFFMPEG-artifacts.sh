#!/bin/sh
set -e
set -u
set -o pipefail

function on_error {
  echo "$(realpath -mq "${0}"):$1: error: Unexpected failure"
}
trap 'on_error $LINENO' ERR

if [ -z ${FRAMEWORKS_FOLDER_PATH+x} ]; then
  # If FRAMEWORKS_FOLDER_PATH is not set, then there's nowhere for us to copy
  # frameworks to, so exit 0 (signalling the script phase was successful).
  exit 0
fi

# This protects against multiple targets copying the same framework dependency at the same time. The solution
# was originally proposed here: https://lists.samba.org/archive/rsync/2008-February/020158.html
RSYNC_PROTECT_TMP_FILES=(--filter "P .*.??????")

ARTIFACT_LIST_FILE="${BUILT_PRODUCTS_DIR}/cocoapods-artifacts-${CONFIGURATION}.txt"
cat > $ARTIFACT_LIST_FILE

BCSYMBOLMAP_DIR="BCSymbolMaps"

record_artifact()
{
  echo "$1" >> $ARTIFACT_LIST_FILE
}

install_artifact()
{
  local source="$1"
  local destination="$2"
  local record=${3:-false}

  # Use filter instead of exclude so missing patterns don't throw errors.
  echo "rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter \"- CVS/\" --filter \"- .svn/\" --filter \"- .git/\" --filter \"- .hg/\" \"${source}\" \"${destination}\""
  rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" "${source}" "${destination}"

  if [[ "$record" == "true" ]]; then
    artifact="${destination}/$(basename "$source")"
    record_artifact "$artifact"
  fi
}

# Copies a framework to derived data for use in later build phases
install_framework()
{
  if [ -r "${BUILT_PRODUCTS_DIR}/$1" ]; then
    local source="${BUILT_PRODUCTS_DIR}/$1"
  elif [ -r "${BUILT_PRODUCTS_DIR}/$(basename "$1")" ]; then
    local source="${BUILT_PRODUCTS_DIR}/$(basename "$1")"
  elif [ -r "$1" ]; then
    local source="$1"
  fi

  local record_artifact=${2:-true}
  local destination="${CONFIGURATION_BUILD_DIR}"

  if [ -L "${source}" ]; then
    echo "Symlinked..."
    source="$(readlink "${source}")"
  fi

  install_artifact "$source" "$destination" "$record_artifact"

  if [ -d "${source}/${BCSYMBOLMAP_DIR}" ]; then
    # Locate and install any .bcsymbolmaps if present
    find "${source}/${BCSYMBOLMAP_DIR}/" -name "*.bcsymbolmap"|while read f; do
      install_artifact "$f" "$destination" "true"
    done
  fi
}

install_xcframework() {
  local basepath="$1"
  local dsym_folder="$2"
  local embed="$3"
  shift
  local paths=("$@")

  # Locate the correct slice of the .xcframework for the current architectures
  local target_path=""
  local target_arch="$ARCHS"

  # Replace spaces in compound architectures with _ to match slice format
  target_arch=${target_arch// /_}

  local target_variant=""
  if [[ "$PLATFORM_NAME" == *"simulator" ]]; then
    target_variant="simulator"
  fi
  if [[ ! -z ${EFFECTIVE_PLATFORM_NAME+x} && "$EFFECTIVE_PLATFORM_NAME" == *"maccatalyst" ]]; then
    target_variant="maccatalyst"
  fi
  for i in ${!paths[@]}; do
    if [[ "${paths[$i]}" == *"$target_arch"* ]] && [[ "${paths[$i]}" == *"$target_variant"* ]]; then
      # Found a matching slice
      echo "Selected xcframework slice ${paths[$i]}"
      target_path=${paths[$i]}
      break;
    fi
  done

  if [[ -z "$target_path" ]]; then
    echo "warning: [CP] Unable to find matching .xcframework slice in '${paths[@]}' for the current build architectures ($ARCHS)."
    return
  fi

  install_framework "$basepath/$target_path" "$embed"

  if [[ -z "$dsym_folder" || ! -d "$dsym_folder" ]]; then
    return
  fi

  dsyms=($(ls "$dsym_folder"))

  local target_dsym=""
  for i in ${!dsyms[@]}; do
    install_artifact "$dsym_folder/${dsyms[$i]}" "$CONFIGURATION_BUILD_DIR" "true"
  done
}


if [[ "$CONFIGURATION" == "Debug" ]]; then
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/mobileffmpeg.xcframework" "" "false" "ios-x86_64-maccatalyst/mobileffmpeg.framework" "ios-arm64/mobileffmpeg.framework" "ios-x86_64-simulator/mobileffmpeg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavcodec.xcframework" "" "false" "ios-x86_64-simulator/libavcodec.framework" "ios-arm64/libavcodec.framework" "ios-x86_64-maccatalyst/libavcodec.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavdevice.xcframework" "" "false" "ios-x86_64-maccatalyst/libavdevice.framework" "ios-x86_64-simulator/libavdevice.framework" "ios-arm64/libavdevice.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavfilter.xcframework" "" "false" "ios-x86_64-simulator/libavfilter.framework" "ios-arm64/libavfilter.framework" "ios-x86_64-maccatalyst/libavfilter.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavformat.xcframework" "" "false" "ios-arm64/libavformat.framework" "ios-x86_64-maccatalyst/libavformat.framework" "ios-x86_64-simulator/libavformat.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavutil.xcframework" "" "false" "ios-arm64/libavutil.framework" "ios-x86_64-maccatalyst/libavutil.framework" "ios-x86_64-simulator/libavutil.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libswresample.xcframework" "" "false" "ios-x86_64-simulator/libswresample.framework" "ios-x86_64-maccatalyst/libswresample.framework" "ios-arm64/libswresample.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libswscale.xcframework" "" "false" "ios-arm64/libswscale.framework" "ios-x86_64-maccatalyst/libswscale.framework" "ios-x86_64-simulator/libswscale.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/expat.xcframework" "" "false" "ios-x86_64-maccatalyst/expat.framework" "ios-arm64/expat.framework" "ios-x86_64-simulator/expat.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/fontconfig.xcframework" "" "false" "ios-arm64/fontconfig.framework" "ios-x86_64-simulator/fontconfig.framework" "ios-x86_64-maccatalyst/fontconfig.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/freetype.xcframework" "" "false" "ios-x86_64-simulator/freetype.framework" "ios-x86_64-maccatalyst/freetype.framework" "ios-arm64/freetype.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/fribidi.xcframework" "" "false" "ios-x86_64-maccatalyst/fribidi.framework" "ios-arm64/fribidi.framework" "ios-x86_64-simulator/fribidi.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/giflib.xcframework" "" "false" "ios-x86_64-maccatalyst/giflib.framework" "ios-arm64/giflib.framework" "ios-x86_64-simulator/giflib.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/gmp.xcframework" "" "false" "ios-x86_64-simulator/gmp.framework" "ios-x86_64-maccatalyst/gmp.framework" "ios-arm64/gmp.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/gnutls.xcframework" "" "false" "ios-x86_64-maccatalyst/gnutls.framework" "ios-x86_64-simulator/gnutls.framework" "ios-arm64/gnutls.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/jpeg.xcframework" "" "false" "ios-x86_64-simulator/jpeg.framework" "ios-x86_64-maccatalyst/jpeg.framework" "ios-arm64/jpeg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/kvazaar.xcframework" "" "false" "ios-arm64/kvazaar.framework" "ios-x86_64-simulator/kvazaar.framework" "ios-x86_64-maccatalyst/kvazaar.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/lame.xcframework" "" "false" "ios-x86_64-simulator/lame.framework" "ios-x86_64-maccatalyst/lame.framework" "ios-arm64/lame.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libaom.xcframework" "" "false" "ios-x86_64-simulator/libaom.framework" "ios-x86_64-maccatalyst/libaom.framework" "ios-arm64/libaom.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libass.xcframework" "" "false" "ios-arm64/libass.framework" "ios-x86_64-maccatalyst/libass.framework" "ios-x86_64-simulator/libass.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libhogweed.xcframework" "" "false" "ios-x86_64-simulator/libhogweed.framework" "ios-arm64/libhogweed.framework" "ios-x86_64-maccatalyst/libhogweed.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libilbc.xcframework" "" "false" "ios-arm64/libilbc.framework" "ios-x86_64-simulator/libilbc.framework" "ios-x86_64-maccatalyst/libilbc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libnettle.xcframework" "" "false" "ios-x86_64-simulator/libnettle.framework" "ios-x86_64-maccatalyst/libnettle.framework" "ios-arm64/libnettle.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libogg.xcframework" "" "false" "ios-arm64/libogg.framework" "ios-x86_64-maccatalyst/libogg.framework" "ios-x86_64-simulator/libogg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libopencore-amrnb.xcframework" "" "false" "ios-arm64/libopencore-amrnb.framework" "ios-x86_64-simulator/libopencore-amrnb.framework" "ios-x86_64-maccatalyst/libopencore-amrnb.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libpng.xcframework" "" "false" "ios-x86_64-simulator/libpng.framework" "ios-arm64/libpng.framework" "ios-x86_64-maccatalyst/libpng.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libsndfile.xcframework" "" "false" "ios-arm64/libsndfile.framework" "ios-x86_64-simulator/libsndfile.framework" "ios-x86_64-maccatalyst/libsndfile.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheora.xcframework" "" "false" "ios-arm64/libtheora.framework" "ios-x86_64-simulator/libtheora.framework" "ios-x86_64-maccatalyst/libtheora.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheoradec.xcframework" "" "false" "ios-x86_64-maccatalyst/libtheoradec.framework" "ios-arm64/libtheoradec.framework" "ios-x86_64-simulator/libtheoradec.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheoraenc.xcframework" "" "false" "ios-arm64/libtheoraenc.framework" "ios-x86_64-simulator/libtheoraenc.framework" "ios-x86_64-maccatalyst/libtheoraenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbis.xcframework" "" "false" "ios-arm64/libvorbis.framework" "ios-x86_64-simulator/libvorbis.framework" "ios-x86_64-maccatalyst/libvorbis.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbisenc.xcframework" "" "false" "ios-arm64/libvorbisenc.framework" "ios-x86_64-simulator/libvorbisenc.framework" "ios-x86_64-maccatalyst/libvorbisenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbisfile.xcframework" "" "false" "ios-x86_64-simulator/libvorbisfile.framework" "ios-x86_64-maccatalyst/libvorbisfile.framework" "ios-arm64/libvorbisfile.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvpx.xcframework" "" "false" "ios-x86_64-simulator/libvpx.framework" "ios-x86_64-maccatalyst/libvpx.framework" "ios-arm64/libvpx.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebp.xcframework" "" "false" "ios-x86_64-simulator/libwebp.framework" "ios-arm64/libwebp.framework" "ios-x86_64-maccatalyst/libwebp.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebpmux.xcframework" "" "false" "ios-arm64/libwebpmux.framework" "ios-x86_64-simulator/libwebpmux.framework" "ios-x86_64-maccatalyst/libwebpmux.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebpdemux.xcframework" "" "false" "ios-arm64/libwebpdemux.framework" "ios-x86_64-simulator/libwebpdemux.framework" "ios-x86_64-maccatalyst/libwebpdemux.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libxml2.xcframework" "" "false" "ios-x86_64-maccatalyst/libxml2.framework" "ios-x86_64-simulator/libxml2.framework" "ios-arm64/libxml2.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/opus.xcframework" "" "false" "ios-arm64/opus.framework" "ios-x86_64-maccatalyst/opus.framework" "ios-x86_64-simulator/opus.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/shine.xcframework" "" "false" "ios-arm64/shine.framework" "ios-x86_64-maccatalyst/shine.framework" "ios-x86_64-simulator/shine.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/snappy.xcframework" "" "false" "ios-arm64/snappy.framework" "ios-x86_64-maccatalyst/snappy.framework" "ios-x86_64-simulator/snappy.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/soxr.xcframework" "" "false" "ios-x86_64-maccatalyst/soxr.framework" "ios-arm64/soxr.framework" "ios-x86_64-simulator/soxr.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/speex.xcframework" "" "false" "ios-arm64/speex.framework" "ios-x86_64-simulator/speex.framework" "ios-x86_64-maccatalyst/speex.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/tiff.xcframework" "" "false" "ios-x86_64-maccatalyst/tiff.framework" "ios-arm64/tiff.framework" "ios-x86_64-simulator/tiff.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/twolame.xcframework" "" "false" "ios-arm64/twolame.framework" "ios-x86_64-simulator/twolame.framework" "ios-x86_64-maccatalyst/twolame.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/vo-amrwbenc.xcframework" "" "false" "ios-arm64/vo-amrwbenc.framework" "ios-x86_64-simulator/vo-amrwbenc.framework" "ios-x86_64-maccatalyst/vo-amrwbenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/wavpack.xcframework" "" "false" "ios-arm64/wavpack.framework" "ios-x86_64-simulator/wavpack.framework" "ios-x86_64-maccatalyst/wavpack.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvidstab.xcframework" "" "false" "ios-arm64/libvidstab.framework" "ios-x86_64-maccatalyst/libvidstab.framework" "ios-x86_64-simulator/libvidstab.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/x264.xcframework" "" "false" "ios-x86_64-maccatalyst/x264.framework" "ios-arm64/x264.framework" "ios-x86_64-simulator/x264.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/x265.xcframework" "" "false" "ios-x86_64-maccatalyst/x265.framework" "ios-arm64/x265.framework" "ios-x86_64-simulator/x265.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/xvidcore.xcframework" "" "false" "ios-arm64/xvidcore.framework" "ios-x86_64-maccatalyst/xvidcore.framework" "ios-x86_64-simulator/xvidcore.framework"
fi
if [[ "$CONFIGURATION" == "Release" ]]; then
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/mobileffmpeg.xcframework" "" "false" "ios-x86_64-maccatalyst/mobileffmpeg.framework" "ios-arm64/mobileffmpeg.framework" "ios-x86_64-simulator/mobileffmpeg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavcodec.xcframework" "" "false" "ios-x86_64-simulator/libavcodec.framework" "ios-arm64/libavcodec.framework" "ios-x86_64-maccatalyst/libavcodec.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavdevice.xcframework" "" "false" "ios-x86_64-maccatalyst/libavdevice.framework" "ios-x86_64-simulator/libavdevice.framework" "ios-arm64/libavdevice.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavfilter.xcframework" "" "false" "ios-x86_64-simulator/libavfilter.framework" "ios-arm64/libavfilter.framework" "ios-x86_64-maccatalyst/libavfilter.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavformat.xcframework" "" "false" "ios-arm64/libavformat.framework" "ios-x86_64-maccatalyst/libavformat.framework" "ios-x86_64-simulator/libavformat.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libavutil.xcframework" "" "false" "ios-arm64/libavutil.framework" "ios-x86_64-maccatalyst/libavutil.framework" "ios-x86_64-simulator/libavutil.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libswresample.xcframework" "" "false" "ios-x86_64-simulator/libswresample.framework" "ios-x86_64-maccatalyst/libswresample.framework" "ios-arm64/libswresample.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libswscale.xcframework" "" "false" "ios-arm64/libswscale.framework" "ios-x86_64-maccatalyst/libswscale.framework" "ios-x86_64-simulator/libswscale.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/expat.xcframework" "" "false" "ios-x86_64-maccatalyst/expat.framework" "ios-arm64/expat.framework" "ios-x86_64-simulator/expat.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/fontconfig.xcframework" "" "false" "ios-arm64/fontconfig.framework" "ios-x86_64-simulator/fontconfig.framework" "ios-x86_64-maccatalyst/fontconfig.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/freetype.xcframework" "" "false" "ios-x86_64-simulator/freetype.framework" "ios-x86_64-maccatalyst/freetype.framework" "ios-arm64/freetype.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/fribidi.xcframework" "" "false" "ios-x86_64-maccatalyst/fribidi.framework" "ios-arm64/fribidi.framework" "ios-x86_64-simulator/fribidi.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/giflib.xcframework" "" "false" "ios-x86_64-maccatalyst/giflib.framework" "ios-arm64/giflib.framework" "ios-x86_64-simulator/giflib.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/gmp.xcframework" "" "false" "ios-x86_64-simulator/gmp.framework" "ios-x86_64-maccatalyst/gmp.framework" "ios-arm64/gmp.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/gnutls.xcframework" "" "false" "ios-x86_64-maccatalyst/gnutls.framework" "ios-x86_64-simulator/gnutls.framework" "ios-arm64/gnutls.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/jpeg.xcframework" "" "false" "ios-x86_64-simulator/jpeg.framework" "ios-x86_64-maccatalyst/jpeg.framework" "ios-arm64/jpeg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/kvazaar.xcframework" "" "false" "ios-arm64/kvazaar.framework" "ios-x86_64-simulator/kvazaar.framework" "ios-x86_64-maccatalyst/kvazaar.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/lame.xcframework" "" "false" "ios-x86_64-simulator/lame.framework" "ios-x86_64-maccatalyst/lame.framework" "ios-arm64/lame.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libaom.xcframework" "" "false" "ios-x86_64-simulator/libaom.framework" "ios-x86_64-maccatalyst/libaom.framework" "ios-arm64/libaom.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libass.xcframework" "" "false" "ios-arm64/libass.framework" "ios-x86_64-maccatalyst/libass.framework" "ios-x86_64-simulator/libass.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libhogweed.xcframework" "" "false" "ios-x86_64-simulator/libhogweed.framework" "ios-arm64/libhogweed.framework" "ios-x86_64-maccatalyst/libhogweed.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libilbc.xcframework" "" "false" "ios-arm64/libilbc.framework" "ios-x86_64-simulator/libilbc.framework" "ios-x86_64-maccatalyst/libilbc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libnettle.xcframework" "" "false" "ios-x86_64-simulator/libnettle.framework" "ios-x86_64-maccatalyst/libnettle.framework" "ios-arm64/libnettle.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libogg.xcframework" "" "false" "ios-arm64/libogg.framework" "ios-x86_64-maccatalyst/libogg.framework" "ios-x86_64-simulator/libogg.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libopencore-amrnb.xcframework" "" "false" "ios-arm64/libopencore-amrnb.framework" "ios-x86_64-simulator/libopencore-amrnb.framework" "ios-x86_64-maccatalyst/libopencore-amrnb.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libpng.xcframework" "" "false" "ios-x86_64-simulator/libpng.framework" "ios-arm64/libpng.framework" "ios-x86_64-maccatalyst/libpng.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libsndfile.xcframework" "" "false" "ios-arm64/libsndfile.framework" "ios-x86_64-simulator/libsndfile.framework" "ios-x86_64-maccatalyst/libsndfile.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheora.xcframework" "" "false" "ios-arm64/libtheora.framework" "ios-x86_64-simulator/libtheora.framework" "ios-x86_64-maccatalyst/libtheora.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheoradec.xcframework" "" "false" "ios-x86_64-maccatalyst/libtheoradec.framework" "ios-arm64/libtheoradec.framework" "ios-x86_64-simulator/libtheoradec.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libtheoraenc.xcframework" "" "false" "ios-arm64/libtheoraenc.framework" "ios-x86_64-simulator/libtheoraenc.framework" "ios-x86_64-maccatalyst/libtheoraenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbis.xcframework" "" "false" "ios-arm64/libvorbis.framework" "ios-x86_64-simulator/libvorbis.framework" "ios-x86_64-maccatalyst/libvorbis.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbisenc.xcframework" "" "false" "ios-arm64/libvorbisenc.framework" "ios-x86_64-simulator/libvorbisenc.framework" "ios-x86_64-maccatalyst/libvorbisenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvorbisfile.xcframework" "" "false" "ios-x86_64-simulator/libvorbisfile.framework" "ios-x86_64-maccatalyst/libvorbisfile.framework" "ios-arm64/libvorbisfile.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvpx.xcframework" "" "false" "ios-x86_64-simulator/libvpx.framework" "ios-x86_64-maccatalyst/libvpx.framework" "ios-arm64/libvpx.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebp.xcframework" "" "false" "ios-x86_64-simulator/libwebp.framework" "ios-arm64/libwebp.framework" "ios-x86_64-maccatalyst/libwebp.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebpmux.xcframework" "" "false" "ios-arm64/libwebpmux.framework" "ios-x86_64-simulator/libwebpmux.framework" "ios-x86_64-maccatalyst/libwebpmux.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libwebpdemux.xcframework" "" "false" "ios-arm64/libwebpdemux.framework" "ios-x86_64-simulator/libwebpdemux.framework" "ios-x86_64-maccatalyst/libwebpdemux.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libxml2.xcframework" "" "false" "ios-x86_64-maccatalyst/libxml2.framework" "ios-x86_64-simulator/libxml2.framework" "ios-arm64/libxml2.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/opus.xcframework" "" "false" "ios-arm64/opus.framework" "ios-x86_64-maccatalyst/opus.framework" "ios-x86_64-simulator/opus.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/shine.xcframework" "" "false" "ios-arm64/shine.framework" "ios-x86_64-maccatalyst/shine.framework" "ios-x86_64-simulator/shine.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/snappy.xcframework" "" "false" "ios-arm64/snappy.framework" "ios-x86_64-maccatalyst/snappy.framework" "ios-x86_64-simulator/snappy.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/soxr.xcframework" "" "false" "ios-x86_64-maccatalyst/soxr.framework" "ios-arm64/soxr.framework" "ios-x86_64-simulator/soxr.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/speex.xcframework" "" "false" "ios-arm64/speex.framework" "ios-x86_64-simulator/speex.framework" "ios-x86_64-maccatalyst/speex.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/tiff.xcframework" "" "false" "ios-x86_64-maccatalyst/tiff.framework" "ios-arm64/tiff.framework" "ios-x86_64-simulator/tiff.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/twolame.xcframework" "" "false" "ios-arm64/twolame.framework" "ios-x86_64-simulator/twolame.framework" "ios-x86_64-maccatalyst/twolame.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/vo-amrwbenc.xcframework" "" "false" "ios-arm64/vo-amrwbenc.framework" "ios-x86_64-simulator/vo-amrwbenc.framework" "ios-x86_64-maccatalyst/vo-amrwbenc.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/wavpack.xcframework" "" "false" "ios-arm64/wavpack.framework" "ios-x86_64-simulator/wavpack.framework" "ios-x86_64-maccatalyst/wavpack.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/libvidstab.xcframework" "" "false" "ios-arm64/libvidstab.framework" "ios-x86_64-maccatalyst/libvidstab.framework" "ios-x86_64-simulator/libvidstab.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/x264.xcframework" "" "false" "ios-x86_64-maccatalyst/x264.framework" "ios-arm64/x264.framework" "ios-x86_64-simulator/x264.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/x265.xcframework" "" "false" "ios-x86_64-maccatalyst/x265.framework" "ios-arm64/x265.framework" "ios-x86_64-simulator/x265.framework"
  install_xcframework "${PODS_ROOT}/mobile-ffmpeg-full-gpl/xvidcore.xcframework" "" "false" "ios-arm64/xvidcore.framework" "ios-x86_64-maccatalyst/xvidcore.framework" "ios-x86_64-simulator/xvidcore.framework"
fi

echo "Artifact list stored at $ARTIFACT_LIST_FILE"

cat "$ARTIFACT_LIST_FILE"
