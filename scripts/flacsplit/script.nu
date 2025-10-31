#!/usr/bin/env nu

def main [
	cuefile: string
	flacfile: string
] {
	cuebreakpoints $cuefile | shnsplit -o flac $flacfile
}
