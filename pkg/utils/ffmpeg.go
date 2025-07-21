package utils

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/go-audio/wav"
)

func ffmpegCommand(args []string) (string, error) {
	cmd := exec.Command("ffmpeg", args...) // Constrain this to ffmpeg to permit security scanner to see that the command is safe.
	cmd.Env = []string{}
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// AudioToWav converts audio to wav for transcribe.
// TODO: use https://github.com/mccoyst/ogg?
func AudioToWav(src, dst string) error {
	if strings.HasSuffix(src, ".wav") {
		f, err := os.Open(src)
		if err != nil {
			return fmt.Errorf("open: %w", err)
		}

		dec := wav.NewDecoder(f)
		dec.ReadInfo()
		f.Close()

		if dec.BitDepth == 16 && dec.NumChans == 1 && dec.SampleRate == 16000 {
			os.Rename(src, dst)
			return nil
		}
	}
	commandArgs := []string{"-i", src, "-format", "s16le", "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le", dst}
	out, err := ffmpegCommand(commandArgs)
	if err != nil {
		return fmt.Errorf("error: %w out: %s", err, out)
	}
	return nil
}

// AudioConvert converts generated wav file from tts to other output formats.
// TODO: handle pcm to have 100% parity of supported format from OpenAI
func AudioConvert(src string, format string) (string, error) {
	extension := ""
	// compute file extension from format, default to wav
	switch format {
	case "opus":
		extension = ".ogg"
	case "mp3", "aac", "flac":
		extension = fmt.Sprintf(".%s", format)
	default:
		extension = ".wav"
	}

	// if .wav, do nothing
	if extension == ".wav" {
		return src, nil
	}

	// naive conversion based on default values and target extension of file
	dst := strings.Replace(src, ".wav", extension, -1)
	commandArgs := []string{"-y", "-i", src, "-vn", dst}
	out, err := ffmpegCommand(commandArgs)
	if err != nil {
		return "", fmt.Errorf("error: %w out: %s", err, out)
	}
	return dst, nil
}
