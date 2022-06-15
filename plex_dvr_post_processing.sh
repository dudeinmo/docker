#!/bin/bash

#
# Post-processing script for Plex DVR.
#
# This script is used to convert the video file produced by the DVR to a smaller
# version.  The conversion is performed by a separate Docker container.
#
# For example, the HandBrake docker container is capable of automatically
# converting files put in a specific folder, called the "watch" folder.  The
# converted video is put in an "output" folder.
#
# When the "watch" and the "output" folders are accessible by both Plex and
# HandBrake, the following workflow is possible:
# 
#   - When a recording is terminated, Plex calls this script.
#   - This script copies the video file to the "watch" folder.
#   - HandBrake automatically starts to convert the video file.
#   - This script periodically checks the presence of the converted video file
#     in the "output" folder.
#   - Once the video file conversion is done, this scripts move the video from
#     the "output" folder back into the original folder.
#   - This script removes the original video file.
#   - This script exits and Plex moves the video file to its final destination.
#

################################################################################
# Configurable variables
################################################################################

# Path to the log file used by this script.
LOGFILE="/config/Library/Application Support/Plex Media Server/Logs/Plex DVR Post Processing.log"

# Maximum time (in seconds) to wait for the video to be converted.
CONVERSION_TIMEOUT=7200

# Directory where the video will be copied to in order to be converted.
VIDEO_CONVERTER_WATCH_DIR="/hb_watch"

# Directory where the converted video will be located.
VIDEO_CONVERTER_OUTPUT_DIR="/hb_output"

# Extension the converted video file will have.
CONVERTED_VIDEO_EXT="mp4"

################################################################################

set -u # Treat unset variables as an error.

log() {
    echo "[$(date)] $*" | tee -a "$LOGFILE"
}

die() {
    log "ERROR: $*"
    log "Post-processing terminated with error."
    exit 1
}

get_file_hash() {
    stat -c '%n %s %Y' "$1" | md5sum | cut -d' ' -f1
}

# Get the path of the video to be processed.
SOURCE_PATH="${1:-UNSET}"
if [ "$SOURCE_PATH" = "UNSET" ]; then
    die "Missing source file argument."
fi

SOURCE_FILENAME="$(basename "$SOURCE_PATH")"
SOURCE_DIRNAME="$(dirname "$SOURCE_PATH")"
CONVERTED_VIDEO_FILENAME="${SOURCE_FILENAME%.*}.${CONVERTED_VIDEO_EXT}"
CONVERTED_VIDEO_PATH="$VIDEO_CONVERTER_OUTPUT_DIR/$CONVERTED_VIDEO_FILENAME"

log "Starting post-processing of recording '$SOURCE_PATH'..."

# Copy the video to the folder where it will be converted.
log "Copying recording '$SOURCE_PATH' to video converter's watch folder '$VIDEO_CONVERTER_WATCH_DIR'..."
cp -av "$SOURCE_PATH" "$VIDEO_CONVERTER_WATCH_DIR"
if [ $? -ne 0 ]; then
    die "Failed to copy recording '$SOURCE_PATH' to '$VIDEO_CONVERTER_WATCH_DIR'."
fi

# Wait for the video to be converted.
TIMEOUT="$CONVERSION_TIMEOUT"
while [ "$TIMEOUT" -gt 0 ]
do
    if [ -f "$CONVERTED_VIDEO_PATH" ]; then
        hash="$(get_file_hash "$CONVERTED_VIDEO_PATH")"
        sleep 10
        if [ "$hash" == "$(get_file_hash "$CONVERTED_VIDEO_PATH")" ]; then
            log "Converted video detected at '$CONVERTED_VIDEO_PATH' with hash of '$hash'."
            break;
        fi
    fi

    log "Waiting for recording to be converted..."
    sleep 30
    TIMEOUT="$(expr "$TIMEOUT" - 30)"
done

# Exit if conversion timeout occurred.
if [ "$TIMEOUT" -le 0 ]; then
    die "Recording still not converted after $CONVERSION_TIMEOUT seconds (expected location: '$CONVERTED_VIDEO_PATH')."
fi

log "Video successfully converted.."

# Move converted video back to the original directory.
log "Moving converted recording '$CONVERTED_VIDEO_PATH' to '$SOURCE_DIRNAME'..."
mv -v "$CONVERTED_VIDEO_PATH" "$SOURCE_DIRNAME"
if [ $? -ne 0 ]; then
    die "Failed to move converted recording '$CONVERTED_VIDEO_PATH' to '$SOURCE_DIRNAME'."
fi

# Remove the source file.
log "Removing original recording '$SOURCE_PATH'..."
rm "$SOURCE_PATH"

log "Post-processing terminated with success."
