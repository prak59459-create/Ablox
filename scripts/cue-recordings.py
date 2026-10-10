#!/usr/bin/env python3
"""Writes Engine/CueRecordings.swift: the 30 built-in sounds as recordings.

    scripts/cue-recordings.py WAV_DIR [OUT.swift]

WAV_DIR holds the original SFXMint WAV of each sound below
(https://sfxmint.com/dl/<id>.wav, CC0). Each is checked against the SHA-256
SFXMint lists for it, then:

  1. mixed to one channel;
  2. trimmed: from 2 ms before it first rises above -50 dB of its peak to
     20 ms after it last does, or `seconds` at most, the last 30 ms faded;
  3. low-passed (a 31-tap windowed sinc at 10 kHz) and halved to 22,050
     samples a second;
  4. brought to a peak of 0.9;
  5. stored, base64, as 4-bit IMA ADPCM when that keeps it within 30 dB of
     the original (most sounds), or else as 8-bit G.711 mu-law (bright ones,
     like coins, which ADPCM makes hiss). The first byte says which: 1 for
     mu-law, a byte a sample; 2 for ADPCM, then three bytes of starting
     state (step index, then the first sample, little-endian) and two
     samples a byte, low nibble first.

The app decodes it once, when the sound is first needed (CueRecordings.swift).
Python 3 standard library only.
"""
import array, base64, hashlib, math, os, sys, wave

# cue, the SFXMint sound, and the longest it may last in seconds.
CUES = [
    ("collect", "ready-coin-04", 0.6),
    ("checkpoint", "feedback-checkpoint-11", 1.2),
    ("hurt", "retro-game-hit-54", 0.4),
    ("bounce", "cartoon-boing-12", 0.5),
    ("teleport", "magic-scifi-teleport-44", 0.9),
    ("goal", "feedback-achievement-39", 1.2),
    ("join", "ui-chime-15", 0.5),
    ("leave", "owner-backlog-20260922-decrease-ui-cue", 0.5),
    ("tick", "ui-tick-09", 0.15),
    ("error", "feedback-error-02", 0.5),
    ("shoot", "retro-game-laser-34", 0.45),
    ("hit", "cartoon-bonk-05", 0.3),
    ("reload", "mechanical-reload-15", 0.8),
    ("defeat", "retro-game-enemy-death-10", 1.0),
    ("coin", "retro-game-coin-33", 0.6),
    ("jump", "retro-game-jump-01", 0.4),
    ("powerUp", "retro-game-power-up-42", 1.2),
    ("explosion", "impact-explosion-10", 1.0),
    ("splash", "water-splash-64", 0.9),
    ("door", "door-open-12", 0.6),
    ("click", "ready-click-04", 0.25),
    ("whoosh", "short-video-whoosh-01", 0.6),
    ("win", "feedback-celebration-10", 1.4),
    ("lose", "feedback-fail-19", 0.9),
    ("magic", "magic-scifi-spell-17", 0.9),
    ("pop", "cartoon-pop-03", 0.3),
    ("bell", "instrument-bell-38", 0.8),
    ("laser", "magic-scifi-laser-66", 0.7),
    ("alarm", "ui-alert-08", 0.5),
    ("drum", "acoustic-drum-kit-high-tom-01", 0.4),
]

RATE = 22_050
STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107,
         118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
         1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
         6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
         32767]
INDEX = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]


def read(path):
    w = wave.open(path)
    channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    assert width == 2, f"{path}: {width * 8}-bit"
    raw = array.array("h", w.readframes(frames))
    mono = [sum(raw[i:i + channels]) / channels / 32768 for i in range(0, len(raw), channels)]
    return mono, rate


def trim(samples, rate, seconds):
    peak = max(abs(x) for x in samples)
    threshold = peak * 10 ** (-50 / 20)
    first = next(i for i, x in enumerate(samples) if abs(x) > threshold)
    last = len(samples) - 1 - next(i for i, x in enumerate(reversed(samples)) if abs(x) > threshold)
    start = max(0, first - int(rate * 0.002))
    end = min(len(samples), last + int(rate * 0.02), start + int(rate * seconds))
    out = samples[start:end]
    fade = min(len(out), int(rate * 0.03))
    for k in range(fade):
        out[len(out) - 1 - k] *= k / fade
    return out


def halve(samples, rate):
    """Low-passed at 10 kHz, then every other sample."""
    assert rate == 44_100, f"rate {rate}"
    taps = 31
    cutoff = 10_000 / rate
    middle = taps // 2
    kernel = []
    for n in range(taps):
        k = n - middle
        sinc = 2 * cutoff if k == 0 else math.sin(2 * math.pi * cutoff * k) / (math.pi * k)
        window = 0.42 - 0.5 * math.cos(2 * math.pi * n / (taps - 1)) + 0.08 * math.cos(4 * math.pi * n / (taps - 1))
        kernel.append(sinc * window)
    total = sum(kernel)
    kernel = [k / total for k in kernel]
    padded = [0.0] * middle + samples + [0.0] * middle
    return [sum(kernel[t] * padded[i + t] for t in range(taps)) for i in range(0, len(samples), 2)]


def normalize(samples, peak=0.9):
    loudest = max(abs(x) for x in samples) or 1
    return [x * peak / loudest for x in samples]


def adpcm(samples):
    pcm = [max(-32768, min(32767, int(round(x * 32767)))) for x in samples]
    predictor, index = pcm[0], 0
    # A starting step near the first change, so a loud start is not smeared.
    first_change = abs(pcm[1] - pcm[0]) if len(pcm) > 1 else 0
    while index < 88 and STEPS[index] < first_change:
        index += 1
    header = bytes([index]) + (predictor & 0xFFFF).to_bytes(2, "little")
    nibbles = []
    for sample in pcm[1:]:
        step = STEPS[index]
        diff = sample - predictor
        code = 0
        if diff < 0:
            code = 8
            diff = -diff
        delta = step >> 3
        if diff >= step:
            code |= 4
            diff -= step
            delta += step
        if diff >= step >> 1:
            code |= 2
            diff -= step >> 1
            delta += step >> 1
        if diff >= step >> 2:
            code |= 1
            delta += step >> 2
        predictor = predictor - delta if code & 8 else predictor + delta
        predictor = max(-32768, min(32767, predictor))
        index = max(0, min(88, index + INDEX[code]))
        nibbles.append(code)
    if len(nibbles) % 2:
        nibbles.append(0)
    body = bytes(nibbles[i] | (nibbles[i + 1] << 4) for i in range(0, len(nibbles), 2))
    return header + body


def ulaw(samples):
    out = bytearray([1])
    for x in samples:
        s = max(-32635, min(32635, int(round(x * 32767))))
        sign = 0x80 if s < 0 else 0
        s = abs(s) + 0x84
        exponent, mask = 7, 0x4000
        while exponent > 0 and not (s & mask):
            exponent -= 1
            mask >>= 1
        mantissa = (s >> (exponent + 3)) & 0x0F
        out.append(~(sign | (exponent << 4) | mantissa) & 0xFF)
    return bytes(out)


def adpcm_decoded(data):
    index, predictor = data[0], int.from_bytes(data[1:3], "little", signed=True)
    out = [predictor]
    for byte in data[3:]:
        for code in (byte & 15, byte >> 4):
            step = STEPS[index]
            delta = step >> 3
            if code & 4:
                delta += step
            if code & 2:
                delta += step >> 1
            if code & 1:
                delta += step >> 2
            predictor = max(-32768, min(32767, predictor - delta if code & 8 else predictor + delta))
            index = max(0, min(88, index + INDEX[code]))
            out.append(predictor)
    return out


def pack(samples):
    """ADPCM if it is faithful enough, else mu-law; and the ratio kept."""
    packed = adpcm(samples)
    decoded = adpcm_decoded(packed)
    signal = sum(x * x for x in samples)
    error = sum((samples[i] - decoded[i] / 32767) ** 2 for i in range(len(samples)))
    snr = 10 * math.log10(signal / max(error, 1e-12))
    if snr >= 30:
        return bytes([2]) + packed, f"ADPCM, {snr:.0f} dB"
    return ulaw(samples), "mu-law"


def main():
    wav_dir = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "Ablox.swiftpm", "Sources", "Engine", "CueRecordings.swift")
    # "<sha256> <id>.wav" lines, from SFXMint's own metadata for each sound.
    expected = {}
    if os.path.exists(os.path.join(wav_dir, "SHA256SUMS")):
        for line in open(os.path.join(wav_dir, "SHA256SUMS")):
            digest, name = line.split()
            expected[name] = digest
    cases, notes, total = [], [], 0
    for cue, sid, seconds in CUES:
        path = os.path.join(wav_dir, f"{sid}.wav")
        data = open(path, "rb").read()
        digest = hashlib.sha256(data).hexdigest()
        if expected.get(f"{sid}.wav") != digest:
            sys.exit(f"{sid}.wav: SHA-256 {digest} is not the one SFXMint lists ({expected.get(sid + '.wav', 'none listed')})")
        samples, rate = read(path)
        samples = normalize(halve(trim(samples, rate, seconds), rate))
        encoded, kind = pack(samples)
        total += len(encoded)
        text = base64.b64encode(encoded).decode()
        lines = "\n".join(text[i:i + 100] for i in range(0, len(text), 100))
        cases.append(f'        case .{cue}:\n            return """\n{lines}\n"""')
        notes.append(f"///   {cue:<10} {sid} ({len(samples) / RATE:.2f} s, {kind}; WAV SHA-256 {digest[:16]}…, "
                     f"stored {hashlib.sha256(encoded).hexdigest()[:16]}…)")
    swift = f'''import Foundation
import AbloxCore

// Written by scripts/cue-recordings.py. Do not edit by hand: change the list
// there and run it again.

/// The 30 built-in sounds as recordings, inside the app.
///
/// Each is a sound from SFXMint (https://sfxmint.com, CC0: free to use, no
/// credit owed), shortened, made one channel at {RATE:,} samples a second and
/// stored as 4-bit IMA ADPCM or 8-bit mu-law in base64 — {total // 1024} KB for all
/// thirty. The script's header says exactly how. A cue whose recording cannot
/// be read plays its tones (`SoundCue.tones`) instead.
///
{chr(10).join(notes)}
enum CueRecordings {{

    static let sampleRate: Double = {RATE}

    private static let lock = NSLock()
    private static var decoded: [SoundCue: SoundClip] = [:]

    /// The cue's recording, decoded the first time it is asked for.
    static func clip(for cue: SoundCue) -> SoundClip? {{
        lock.lock()
        defer {{ lock.unlock() }}
        if let clip = decoded[cue] {{ return clip }}
        guard let clip = SoundClipDecoder.clip(packedBase64: text(for: cue), rate: sampleRate) else {{ return nil }}
        decoded[cue] = clip
        return clip
    }}

    /// Decodes every cue, so the first of each in a game is not late.
    static func prepareAll() {{
        for cue in SoundCue.allCases {{ _ = clip(for: cue) }}
    }}

    private static func text(for cue: SoundCue) -> String {{
        switch cue {{
{chr(10).join(cases)}
        }}
    }}
}}
'''
    open(out_path, "w").write(swift)
    print(f"{out_path}: {len(CUES)} sounds, {total} bytes ({len(swift)} characters of Swift)")


main()
