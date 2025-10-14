#!/usr/bin/env nu

def parse_audio_device_listing [] {
	lines |
		skip 1 |
		chunks 3 |
		each {|c|
			$c |
			str join " " |
			parse -r 'card\s+(?<card>[0-9]+):\s*(?<name>[^,]+), device\s+(?<device>[0-9]+):(?:.|\n)+Subdevice\s+#(?<subdevice>[0-9]+)'
		} |
		flatten |
		str trim
}

let input = arecord -l | parse_audio_device_listing | where name =~ "USB PnP" | first
let output = aplay -l | parse_audio_device_listing  | where name =~ "iStore Audio"| first

print {input: $input, output: $output}

amixer -c $output.card set PCM 100%
amixer -c $input.card set Mic 100%
ecasound  -B:rtlowlatency -b:512 -f:s16_le,2,48000 $"-i:alsahw,($input.card),($input.device),($input.subdevice)" -f:s16_le,2,48000 -o:alsa,plug:dmix
