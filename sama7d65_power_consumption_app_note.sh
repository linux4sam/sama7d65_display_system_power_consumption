#!/bin/bash

set -o pipefail

readonly GOVERNOR_PATH="/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"

die() {
    echo "Error: $*" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    command -v "$command_name" >/dev/null 2>&1 || \
        die "Required command not found: $command_name"
}

require_command systemctl
require_command egt_video_perf

# Stop egtdemo before running tests, if it is running
if systemctl is-active --quiet egtdemo; then
    if ! systemctl stop egtdemo; then
        die "egtdemo is running but could not be stopped."
    fi
fi

# Enable EGT performance overlays
export EGT_SHOW_FPS=1
export EGT_SHOW_CPU=1
export EGT_SHOW_CPU_FREQ=1
export EGT_SHOW_POWER=1
export EGT_SHOW_TEMP=1

read_current_governor() {
    if ! IFS= read -r CURRENT_GOVERNOR < "$GOVERNOR_PATH"; then
        die "Failed to read CPU governor from $GOVERNOR_PATH"
    fi
}

set_governor() {
    local governor="$1"

    if [ ! -e "$GOVERNOR_PATH" ]; then
        die "CPU governor file not found: $GOVERNOR_PATH"
    fi

    if [ ! -w "$GOVERNOR_PATH" ]; then
        die "CPU governor file is not writable: $GOVERNOR_PATH"
    fi

    if ! echo "$governor" > "$GOVERNOR_PATH"; then
        die "Failed to set CPU governor to: $governor"
    fi

    read_current_governor
    if [ "$CURRENT_GOVERNOR" != "$governor" ]; then
        die "CPU governor is '$CURRENT_GOVERNOR' instead of '$governor'"
    fi

    echo "CPU governor set to: $governor"
}

format_perf_output() {
    sed -E \
        -e 's/([0-9.]+)W/\1 W/g' \
        -e 's/([0-9.]+)°C/\1 °C/g'
}

run_video() {
    local video_file="$1"
    local sync_mode="$2"

    if [ "$SCALING_MODE" = "with_scaling" ]; then
        if ! egt_video_perf --width 800 --height 480 --pipeline \
            "uridecodebin uri=file://$video_file caps=video/x-raw(ANY) name=source ! videoconvert ! videoscale ! capsfilter name=vcaps caps=video/x-raw,width=800,height=480,format=I420 ! appsink name=appsink sync=$sync_mode" \
            2>&1 | format_perf_output; then
            die "Video test failed: $video_file"
        fi
    else
        if ! egt_video_perf --width 800 --height 480 --pipeline \
            "uridecodebin uri=file://$video_file caps=video/x-raw(ANY) name=source ! videoconvert ! capsfilter name=vcaps caps=video/x-raw,format=I420 ! appsink name=appsink sync=$sync_mode" \
            2>&1 | format_perf_output; then
            die "Video test failed: $video_file"
        fi
    fi
}

validate_video_file() {
    local video_file="$1"

    if [ ! -f "$video_file" ]; then
        die "Video file not found: $video_file"
    fi

    if [ ! -r "$video_file" ]; then
        die "Video file is not readable: $video_file"
    fi
}

read_or_exit() {
    if ! IFS= read -r "$@"; then
        echo
        echo "Input closed. Exiting."
        exit 0
    fi
}

choose_governor() {
    local gov_choice=""

    while true; do
        echo "======================================"
        echo "         Choose CPU Governor          "
        echo "======================================"
        echo "1) powersave"
        echo "2) performance"
        echo "3) ondemand"
        echo "0) Exit"
        echo "======================================"
        read_or_exit -p "Choose governor: " gov_choice
        case "$gov_choice" in
            1)
                GOVERNOR="powersave"
                set_governor "$GOVERNOR"
                return
                ;;
            2)
                GOVERNOR="performance"
                set_governor "$GOVERNOR"
                return
                ;;
            3)
                GOVERNOR="ondemand"
                set_governor "$GOVERNOR"
                return
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}
choose_sync() {
    local sync_choice=""

    while true; do
        echo "======================================"
        echo "           Choose Sync Mode           "
        echo "======================================"
        echo "1) sync=true"
        echo "2) sync=false"
        echo "0) Exit"
        echo "======================================"
        read_or_exit -p "Choose sync mode: " sync_choice
        case "$sync_choice" in
            1)
                SYNC_MODE="true"
                return
                ;;
            2)
                SYNC_MODE="false"
                return
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}
choose_scaling() {
    local scaling_choice=""

    while true; do
        echo "======================================"
        echo "          Choose Scaling Mode         "
        echo "======================================"
        echo "1) with scaling"
        echo "2) without scaling"
        echo "0) Exit"
        echo "======================================"
        read_or_exit -p "Choose scaling mode: " scaling_choice
        case "$scaling_choice" in
            1)
                SCALING_MODE="with_scaling"
                return
                ;;
            2)
                SCALING_MODE="without_scaling"
                return
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}
choose_video() {
    local choice=""
    local custom_file=""

    while true; do
        echo "======================================"
        echo "      EGT Video Performance Menu      "
        echo "======================================"
        echo "1) Run 320x192 15fps video"
        echo "2) Run 640x360 15fps video"
        echo "3) Run 800x480 15fps video"
        echo "4) Enter custom video file path"
        echo "0) Exit"
        echo "======================================"
        read_or_exit -p "Choose an option: " choice
        case "$choice" in
            1)
                VIDEO_FILE="/usr/share/app_note/sama7d65_power_consumption/video_display_320x192_15fps.mp4"
                return
                ;;
            2)
                VIDEO_FILE="/usr/share/app_note/sama7d65_power_consumption/video_display_640x360_15fps.mp4"
                return
                ;;
            3)
                VIDEO_FILE="/usr/share/app_note/sama7d65_power_consumption/video_display_800x480_15fps.mp4"
                return
                ;;
            4)
                read_or_exit -p "Enter full file path (example: /root/video.mp4): " custom_file
                if [ -f "$custom_file" ]; then
                    VIDEO_FILE="$custom_file"
                    return
                else
                    echo "File not found: $custom_file"
                fi
                ;;
            0)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}
choose_repeat_count() {
    while true; do
        echo "======================================"
        echo "         Choose Repeat Count          "
        echo "======================================"
        read_or_exit -p "Enter number of times to run the test: " REPEAT_COUNT
        if [[ "$REPEAT_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            return
        else
            echo "Invalid number. Please enter a positive integer."
        fi
    done
}
run_repeated_tests() {
    local i

    for ((i=1; i<=REPEAT_COUNT; i++)); do
        read_current_governor
        echo "======================================"
        echo "Starting run $i / $REPEAT_COUNT"
        echo "Video     : $VIDEO_FILE"
        echo "Sync      : $SYNC_MODE"
        echo "Scaling   : $SCALING_MODE"
        echo "Governor  : $CURRENT_GOVERNOR"
        echo "Resolution: 800x480"
        echo "======================================"
        run_video "$VIDEO_FILE" "$SYNC_MODE"
        echo "======================================"
        echo "Completed run $i / $REPEAT_COUNT"
        echo "======================================"
        echo
    done
}
while true; do
    choose_governor
    choose_sync
    choose_scaling
    choose_video
    validate_video_file "$VIDEO_FILE"
    choose_repeat_count
    read_current_governor
    echo "======================================"
    echo "Test configuration:"
    echo "Video     : $VIDEO_FILE"
    echo "Sync      : $SYNC_MODE"
    echo "Scaling   : $SCALING_MODE"
    echo "Governor  : $CURRENT_GOVERNOR"
    echo "Repeat    : $REPEAT_COUNT"
    echo "Resolution: 800x480"
    echo "======================================"
    run_repeated_tests
    echo
    read_or_exit -p "Press Enter to return to the menu..."
done
