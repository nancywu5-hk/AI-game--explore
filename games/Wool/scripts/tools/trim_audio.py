import os
import sys
from pydub import AudioSegment


def trim_audio(input_file, start_sec, end_sec, output_file=None):
    if not os.path.exists(input_file):
        print(f"Error: File '{input_file}' not found.")
        return

    try:
        # Load audio file
        audio = AudioSegment.from_file(input_file)

        # Pydub works in milliseconds
        start_ms = start_sec * 1000
        end_ms = end_sec * 1000

        # Trim
        trimmed_audio = audio[start_ms:end_ms]

        # Output filename
        if not output_file:
            base, ext = os.path.splitext(input_file)
            output_file = f"{base}_trimmed{ext}"

        # Export
        # Determine format from extension
        out_format = os.path.splitext(output_file)[1][1:]
        if not out_format:
            out_format = "mp3" # Default

        trimmed_audio.export(output_file, format=out_format)
        print(f"Successfully trimmed '{input_file}' to '{output_file}'")

    except Exception as e:
        print(f"Error trimming audio: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python trim_audio.py <input_file> [start_sec] [end_sec] [output_file]")
        print("Example: python trim_audio.py song.mp3 2 4")
        sys.exit(1)

    input_video = sys.argv[1]
    start = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
    end = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0
    output = sys.argv[4] if len(sys.argv) > 4 else None

    trim_audio(input_video, start, end, output)
