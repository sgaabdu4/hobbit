import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

rate = 48000
duration = 3.0
output = Path(__file__).resolve().parents[1] / 'Sources/Habitaker/Resources/hobbit-ring.caf'
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'ring.wav'
    samples = []
    for index in range(int(rate * duration)):
        time = index / rate
        pulse = time if time < 0.4 else time - 0.6
        active = 0 <= time < 0.4 or 0.6 <= time < 1.0
        envelope = min(1, pulse / 0.015, (0.4 - pulse) / 0.025) if active else 0
        value = 0.18 * envelope * (math.sin(2 * math.pi * 400 * time) + math.sin(2 * math.pi * 450 * time))
        samples.append(struct.pack('<h', round(value * 32767)))
    with wave.open(str(source), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(b''.join(samples))
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', str(source), str(output)], check=True)
print(output)
