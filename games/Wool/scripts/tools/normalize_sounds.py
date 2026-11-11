import os
import sys
from pydub import AudioSegment
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def normalize_audio(directory, target_dBFS=-10.0):
    print(f"Scanning directory: {directory}")

    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith((".wav", ".mp3", ".ogg")):
                file_path = os.path.join(root, file)
                try:
                    sound = AudioSegment.from_file(file_path)

                    change_in_dBFS = target_dBFS - sound.dBFS
                    if abs(change_in_dBFS) < 0.5:
                        print(f"Skipping {file}: Already normalized.")
                        continue

                    normalized_sound = sound.apply_gain(change_in_dBFS)

                    fmt = file.split('.')[-1]
                    normalized_sound.export(file_path, format=fmt)
                    print(f"Normalized {file}: {sound.dBFS:.2f} -> {normalized_sound.dBFS:.2f} dBFS")

                except Exception as e:
                    print(f"Error processing {file}: {e}")

if __name__ == "__main__":
    target_dir = SCRIPT_DIR / ".." / ".." / "assets" / "sound"
    if not os.path.exists(target_dir):
        print(f"Directory {target_dir} does not exist.")
        sys.exit(1)

    normalize_audio(target_dir)
    print("Normalization complete.")
