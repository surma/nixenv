# This script records an area of the screen to ~/Videos.
# It records until it gets SIGINT or SIGTERM, for example from
# `systemctl stop`. The --audio flag adds the system sound.

audio_args=()
if [[ "${1:-}" == "--audio" ]]; then
  # The monitor source of the default sink carries the system sound.
  audio_args=(--audio "--audio-device=$(pactl get-default-sink).monitor")
fi

# slurp fails when the user cancels the selection with Escape.
if ! region="$(slurp)"; then
  exit 0
fi
# The software encoder needs an even width and height.
read -r position size <<< "$region"
width="${size%x*}"
height="${size#*x}"
region="$position $(( width / 2 * 2 ))x$(( height / 2 * 2 ))"

# Use the GPU encoder only if the VA-API driver can encode H.264. grep reads
# all of the output, so that vainfo cannot fail with SIGPIPE.
encoder_args=(--no-hw)
if vainfo --display drm --device /dev/dri/renderD128 2>/dev/null | grep 'VAProfileH264.*VAEntrypointEncSlice' >/dev/null; then
  encoder_args=()
fi

mkdir -p "$HOME/Videos"
file="$HOME/Videos/recording-$(date +%Y-%m-%dT%H-%M-%S).mp4"

# The screen must not turn off, because then the capture stops.
systemd-inhibit --what=idle --who=record-screen --why="Screen recording" sleep infinity &
inhibitor=$!

# A stop signal goes to every process of the systemd unit. wl-screenrec then
# finishes the file. The trap lets this script continue after that.
trap : INT TERM
status=0
# Without --max-fps, wl-screenrec copies frames as fast as SXWM sends them.
wl-screenrec --geometry="$region" --filename="$file" --codec=avc --max-fps=60 \
  "${encoder_args[@]}" "${audio_args[@]}" || status=$?
kill "$inhibitor" 2>/dev/null || true

if [[ ! -s "$file" ]]; then
  notify-send --urgency=critical "Screen recording failed" "wl-screenrec exited with status $status."
  exit 1
fi

# The unit stops all of its processes when this script ends. Thus wl-copy
# serves the clipboard from a unit of its own.
systemd-run --user --quiet --collect "$(command -v wl-copy)" --foreground --type text/uri-list "file://$file"
notify-send "Screen recording" "Saved $file. The clipboard has the file."
