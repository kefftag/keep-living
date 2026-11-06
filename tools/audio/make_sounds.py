"""
Keep Living: procedural sound effects.

Every sound in the game is synthesised here with numpy (no samples, so no
licensing questions). Output: assets/audio/<name>.wav, 44.1 kHz 16-bit mono.

    python3 tools/audio/make_sounds.py

Replace any file with a recorded sound of the same name later; the game only
cares about the filenames (see scripts/autoload/sfx.gd).
"""

import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(2026)


# --- building blocks ---------------------------------------------------------

def t(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def brown(dur):
    x = np.cumsum(noise(dur))
    x -= np.convolve(x, np.ones(2000) / 2000, mode="same")  # remove drift
    return x / (np.abs(x).max() + 1e-9)


def spectral(x, curve):
    """Filter by multiplying the spectrum with curve(freqs)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * curve(f), len(x))


def lowpass(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def peaks(x, centres, widths, gains):
    """Formant / resonance filter: sum of Gaussian bumps."""
    def curve(f):
        c = np.zeros_like(f)
        for fc, bw, g in zip(centres, widths, gains):
            c += g * np.exp(-0.5 * ((f - fc) / bw) ** 2)
        return c
    return spectral(x, curve)


def env_exp(n, decay):
    return np.exp(-np.arange(n) / SR / decay)


def adsr(n, a, d, s, r):
    e = np.ones(n) * s
    total = (a + d + r) * SR
    k = min(1.0, 0.95 * n / total) if total > 0 else 1.0  # squeeze to fit short sounds
    ai, di, ri = int(a * SR * k), int(d * SR * k), int(r * SR * k)
    e[:ai] = np.linspace(0, 1, ai)
    e[ai:ai + di] = np.linspace(1, s, di)
    e[n - ri:] *= np.linspace(1, 0, ri)
    return e


def resonator(dur, freqs, decays, amps):
    tt = t(dur)
    out = np.zeros_like(tt)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2 * np.pi * f * tt + rng.random() * 6.28) * np.exp(-tt / d)
    return out


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    dst[i:j] += src[:j - i]
    return dst


def norm(x, peak=0.9):
    return x / (np.abs(x).max() + 1e-9) * peak


def fade_loop(x, fade=0.4):
    """Crossfade the tail into the head so it loops seamlessly."""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


def save(name, x, peak=0.9):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# --- sounds ------------------------------------------------------------------

def footsteps():
    for i in range(4):
        # Socked/slippered foot on flooring: soft low thump + a little creak.
        d = 0.18
        thump = lowpass(noise(d), 180 + rng.random() * 60) * env_exp(int(d * SR), 0.03)
        knock = resonator(d, [95 + rng.random() * 20, 210], [0.04, 0.02], [1, 0.4])
        scuff = bandpass(noise(d), 1200, 4000) * env_exp(int(d * SR), 0.015) * 0.08
        save("step_wood_%d" % i, thump * 1.4 + knock * 0.5 + scuff, 0.8)
        # Shoe on tile / concrete: harder, brighter, with a gritty scrape.
        click = bandpass(noise(d), 600, 6000) * env_exp(int(d * SR), 0.012)
        grit = bandpass(noise(d), 2500, 9000) * env_exp(int(d * SR), 0.05) * 0.15
        heel = resonator(d, [140 + rng.random() * 30], [0.02], [1])
        save("step_tile_%d" % i, click + grit + heel * 0.6, 0.8)


def doors():
    d = 0.9
    latch = bandpass(noise(0.03), 1500, 7000) * env_exp(int(0.03 * SR), 0.004)
    hinge = peaks(noise(d), [700, 1100, 1700], [40, 60, 80], [1, 0.6, 0.3]) * adsr(int(d * SR), 0.1, 0.2, 0.5, 0.3) * 0.25
    x = np.zeros(int(d * SR))
    place(x, latch, 0.0)
    place(x, hinge, 0.05)
    save("door_open", x, 0.6)
    y = np.zeros(int(0.6 * SR))
    place(y, lowpass(noise(0.3), 220) * env_exp(int(0.3 * SR), 0.05), 0.0)
    place(y, resonator(0.3, [120, 330], [0.06, 0.03], [1, 0.4]), 0.0)
    place(y, latch * 1.2, 0.02)
    save("door_close", y, 0.75)
    # Sliding door: wheels rolling along the track, then the soft bump.
    n = int(0.75 * SR)
    roll = bandpass(noise(0.75), 200, 1200) * adsr(n, 0.08, 0.1, 0.7, 0.15)
    roll *= 1 + 0.3 * np.sin(2 * np.pi * 23 * t(0.75))
    z = np.zeros(int(0.95 * SR))
    place(z, roll * 0.5, 0)
    place(z, lowpass(noise(0.2), 250) * env_exp(int(0.2 * SR), 0.04), 0.72)
    save("slide_door", z, 0.6)


def bangs():
    for i in range(3):
        # Fists / bodies on the steel front door: dull boom + metallic ring.
        d = 1.2
        boom = lowpass(noise(d), 120) * env_exp(int(d * SR), 0.09) * 2.5
        ring = resonator(d, [212 + 10 * i, 347, 563, 891, 1270], [0.35, 0.25, 0.2, 0.12, 0.08], [0.5, 0.4, 0.3, 0.2, 0.1])
        slap = bandpass(noise(0.05), 300, 3000) * env_exp(int(0.05 * SR), 0.01)
        x = boom + ring * 0.6
        place(x, slap, 0)
        if i == 2:  # double hit
            place(x, (boom + ring * 0.5)[: int(0.8 * SR)] * 0.7, 0.28)
        save("bang_door_%d" % i, x)
        # Palms on window glass: thud plus the pane rattling in its sash.
        g = lowpass(noise(d), 200) * env_exp(int(d * SR), 0.05) * 1.5
        rattle = bandpass(noise(d), 1500, 6000) * env_exp(int(d * SR), 0.12) * (np.sin(2 * np.pi * 31 * t(d)) > 0.6) * 0.25
        pane = resonator(d, [1830 + 40 * i, 2710, 3950], [0.15, 0.1, 0.07], [0.3, 0.2, 0.15])
        save("bang_glass_%d" % i, g + rattle + pane * 0.4)


def breaks():
    d = 2.2
    x = np.zeros(int(d * SR))
    place(x, bandpass(noise(0.25), 800, 12000) * env_exp(int(0.25 * SR), 0.06), 0)
    place(x, lowpass(noise(0.3), 300) * env_exp(int(0.3 * SR), 0.08) * 1.5, 0)
    for k in range(70):  # shards tinkling down
        at = 0.02 + rng.exponential(0.35)
        if at > d - 0.2:
            continue
        f = rng.uniform(2500, 9000)
        place(x, resonator(0.15, [f, f * 1.48], [0.03, 0.02], [1, 0.5]) * rng.uniform(0.05, 0.3), at)
    save("glass_break", x)
    y = np.zeros(int(1.8 * SR))
    place(y, lowpass(noise(0.5), 180) * env_exp(int(0.5 * SR), 0.12) * 2, 0)
    place(y, resonator(1.6, [180, 290, 470, 760], [0.5, 0.35, 0.25, 0.15], [1, 0.7, 0.5, 0.3]), 0)
    for k in range(8):  # wood splintering
        place(y, bandpass(noise(0.04), 1000, 6000) * env_exp(int(0.04 * SR), 0.008) * 0.5, rng.uniform(0, 0.3))
    save("door_break", y)


def groan_voice(dur, f0, f1, vowel, rasp=0.5, seed=0):
    """A vocal-ish groan: glottal pulse train with jitter through formants."""
    r = np.random.default_rng(seed)
    tt = t(dur)
    f = np.linspace(f0, f1, len(tt)) * (1 + 0.04 * np.sin(2 * np.pi * 5.5 * tt)) \
        * (1 + 0.03 * np.cumsum(r.standard_normal(len(tt))) / np.sqrt(len(tt)))
    phase = np.cumsum(f / SR)
    src = (phase % 1.0) ** 3  # buzzy glottal-ish pulse
    src -= src.mean()
    src += rasp * bandpass(r.standard_normal(len(tt)), 300, 4000) * 0.3  # wet rasp
    formants = {"a": ([700, 1150, 2600], [90, 110, 160]), "o": ([450, 800, 2500], [70, 90, 150]),
                "u": ([330, 700, 2300], [60, 80, 140]), "e": ([550, 1700, 2500], [80, 120, 150])}[vowel]
    v = peaks(src, formants[0], formants[1], [1, 0.6, 0.25])
    v += lowpass(src, 250) * 0.4
    e = adsr(len(tt), 0.15, 0.3, 0.7, 0.4) * (0.8 + 0.2 * np.sin(2 * np.pi * 2.3 * tt))
    return v * e


def groans():
    specs = [(1.6, 95, 70, "a"), (1.2, 120, 85, "o"), (2.2, 80, 60, "u"), (0.9, 140, 110, "e"), (1.8, 105, 65, "a")]
    for i, (d, f0, f1, v) in enumerate(specs):
        save("groan_%d" % i, groan_voice(d, f0, f1, v, seed=i))
    # Shriek when they break in: higher, strained.
    s = groan_voice(1.3, 220, 160, "a", rasp=1.2, seed=9) + groan_voice(1.3, 233, 170, "e", rasp=1.0, seed=10) * 0.6
    save("shriek", s)
    # Death gurgle.
    g = groan_voice(1.0, 90, 50, "o", rasp=1.5, seed=11) * np.linspace(1, 0, int(1.0 * SR))
    save("zombie_die", g)


def combat():
    d = 0.35
    n = int(d * SR)
    sweep = np.zeros(n)
    x = noise(d)
    for k, (lo, hi) in enumerate([(300, 900), (500, 1500), (800, 2500), (500, 1500), (300, 900)]):
        seg = slice(k * n // 5, (k + 1) * n // 5)
        sweep[seg] = bandpass(x, lo, hi)[seg]
    save("swing", sweep * adsr(n, 0.08, 0.05, 0.8, 0.15), 0.5)
    d = 0.4
    hit = lowpass(noise(d), 300) * env_exp(int(d * SR), 0.05) * 2 + bandpass(noise(d), 400, 2000) * env_exp(int(d * SR), 0.03)
    save("hit_flesh", hit + resonator(d, [90], [0.06], [1]) * 0.6)
    bite = bandpass(noise(0.5), 300, 3000) * env_exp(int(0.5 * SR), 0.1) * (1 + np.sin(2 * np.pi * 37 * t(0.5)))
    save("bite", bite + lowpass(noise(0.5), 200) * env_exp(int(0.5 * SR), 0.08))


def work():
    for i in range(3):
        d = 0.45
        x = bandpass(noise(0.02), 1500, 9000) * env_exp(int(0.02 * SR), 0.003)
        y = resonator(d, [420 + 30 * i, 1180, 2650], [0.08, 0.04, 0.02], [1, 0.5, 0.3]) + lowpass(noise(d), 300) * env_exp(int(d * SR), 0.03)
        place(y, x * 2, 0)
        save("hammer_%d" % i, y, 0.8)
        r = np.zeros(int(0.7 * SR))
        for k in range(10):
            g = bandpass(noise(0.06), 1500, 8000) * env_exp(int(0.06 * SR), 0.02) * rng.uniform(0.2, 1.0)
            place(r, g, rng.uniform(0, 0.6))
        place(r, lowpass(noise(0.15), 400) * env_exp(int(0.15 * SR), 0.05) * 0.6, rng.uniform(0, 0.4))
        save("rummage_%d" % i, r, 0.6)
    p = bandpass(noise(0.5), 2000, 9000) * adsr(int(0.5 * SR), 0.02, 0.1, 0.4, 0.2) * (1 + 0.6 * np.sin(2 * np.pi * 13 * t(0.5)))
    save("paper", p, 0.5)


def phone():
    d = 2.2
    x = np.zeros(int(d * SR))
    for start in (0.0, 0.55):
        seg = 0.4
        tt = t(seg)
        buzz = np.sign(np.sin(2 * np.pi * 165 * tt)) * 0.5 + np.sin(2 * np.pi * 330 * tt)
        rattle = bandpass(noise(seg), 1000, 5000) * (np.sin(2 * np.pi * 165 * tt) > 0.7) * 0.4  # against the wood
        place(x, lowpass(buzz + rattle, 3000) * adsr(len(tt), 0.01, 0.02, 1.0, 0.03), start)
    save("phone_buzz", x, 0.6)


def alarm():
    """Original early-warning tone (NOT the broadcast chime): rising triad x3."""
    notes = [880, 1108.7, 1318.5, 1760]
    x = np.zeros(int(3.6 * SR))
    for rep in range(3):
        for k, f in enumerate(notes):
            seg = t(0.16)
            tone = (np.sin(2 * np.pi * f * seg) + 0.3 * np.sin(2 * np.pi * 2 * f * seg)) * adsr(len(seg), 0.005, 0.03, 0.8, 0.05)
            place(x, tone, rep * 1.15 + k * 0.17)
    save("eew_alarm", x, 0.7)


def quake():
    d = 6.0
    n = int(d * SR)
    rumble = lowpass(brown(d), 60) * 3 + lowpass(noise(d), 120) * 0.5
    e = adsr(n, 0.8, 0.5, 0.85, 2.5) * (1 + 0.25 * np.sin(2 * np.pi * 1.7 * t(d)))
    x = rumble * e
    for k in range(120):  # crockery, hangers, window rattle
        at = rng.uniform(0.5, 4.8)
        f = rng.uniform(1500, 6000)
        place(x, resonator(0.12, [f, f * 1.37], [0.025, 0.015], [1, 0.4]) * rng.uniform(0.02, 0.12), at)
    for k in range(25):
        place(x, bandpass(noise(0.06), 200, 2000) * env_exp(int(0.06 * SR), 0.015) * rng.uniform(0.1, 0.4), rng.uniform(0.5, 4.5))
    save("quake_rumble", x)
    y = np.zeros(int(2.0 * SR))
    place(y, lowpass(noise(0.6), 150) * env_exp(int(0.6 * SR), 0.15) * 3, 0)
    place(y, resonator(1.5, [70, 140, 260], [0.4, 0.25, 0.15], [1, 0.6, 0.4]), 0)
    for k in range(20):  # books and things spilling
        place(y, bandpass(noise(0.05), 400, 4000) * env_exp(int(0.05 * SR), 0.012) * rng.uniform(0.2, 0.7), rng.uniform(0.05, 1.2))
    save("furniture_crash", y)


def loops():
    d = 6.0
    save("gas_hiss", fade_loop(bandpass(noise(d), 3000, 11000) * (1 + 0.05 * np.sin(2 * np.pi * 0.5 * t(d)))), 0.5)
    # Tokyo is on the 50 Hz grid: compressor hum at 50/100/150 Hz.
    tt = t(d)
    hum = sum(a * np.sin(2 * np.pi * f * tt) for f, a in [(50, 1), (100, 0.6), (150, 0.25), (200, 0.1)])
    save("fridge_hum", fade_loop(hum + lowpass(noise(d), 400) * 0.15), 0.4)
    crackle = np.zeros(len(tt))
    for k in range(200):
        place(crackle, noise(0.004) * rng.uniform(0.3, 1.5), rng.uniform(0, d - 0.01))
    static = bandpass(noise(d), 300, 5000) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.3 * tt)) + crackle
    save("radio_static", fade_loop(static), 0.5)
    hb = np.zeros(int(1.0 * SR))
    place(hb, resonator(0.15, [55, 110], [0.05, 0.03], [1, 0.4]), 0.0)
    place(hb, resonator(0.15, [50, 100], [0.05, 0.03], [0.7, 0.3]), 0.28)
    save("heartbeat", hb, 0.8)
    # Helicopter: rotor slap at ~18 Hz plus turbine whine.
    d = 4.0
    tt = t(d)
    slap = lowpass(noise(d), 600) * (np.sin(2 * np.pi * 18 * tt) > 0.85) * 2
    turbine = np.sin(2 * np.pi * 2300 * tt) * 0.05 + lowpass(brown(d), 100)
    save("helicopter", fade_loop(slap + turbine), 0.8)


def ambience():
    d = 24.0
    tt = t(d)
    # Day: distant traffic hush, a far siren that rises and falls, a crow or two.
    city = lowpass(noise(d), 500) * 0.4 + lowpass(brown(d), 120) * 0.6
    siren = np.zeros(len(tt))
    s_t = t(9.0)
    fsweep = 750 + 180 * np.sin(2 * np.pi * 0.25 * s_t)
    tone = np.sin(2 * np.pi * np.cumsum(fsweep) / SR) * adsr(len(s_t), 2.5, 0.5, 0.8, 3.0)
    place(siren, lowpass(tone, 1500) * 0.08, 6.0)
    for at in (3.0, 15.5):
        caw = groan_voice(0.35, 600, 520, "a", rasp=1.5, seed=int(at)) * 0.04
        place(siren, bandpass(caw, 500, 4000), at)
        place(siren, bandpass(caw, 500, 4000) * 0.8, at + 0.45)
    save("ambience_day", fade_loop(city + siren, 1.5), 0.35)
    # Night: wind around the building, far-off screams, a dog.
    wind = bandpass(noise(d), 150, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * tt) ** 2)
    wind += bandpass(noise(d), 600, 2500) * 0.15 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * tt + 1))
    far = np.zeros(len(tt))
    place(far, lowpass(groan_voice(1.2, 330, 250, "a", rasp=0.8, seed=21), 1800) * 0.06, 8.0)
    place(far, lowpass(groan_voice(1.6, 110, 75, "o", seed=22), 900) * 0.05, 17.0)
    save("ambience_night", fade_loop(wind + far, 1.5), 0.3)


def misc():
    d = 2.5
    x = bandpass(noise(d), 200, 2500) * adsr(int(d * SR), 0.1, 0.2, 0.7, 0.6)
    x *= 1 + 0.4 * np.sin(2 * np.pi * 7 * t(d)) * rng.random()
    save("water_pour", x, 0.5)
    y = np.zeros(int(2.5 * SR))
    for at in (0.0, 0.35, 0.9, 1.5):
        place(y, resonator(0.4, [160, 410, 980], [0.12, 0.08, 0.05], [1, 0.6, 0.3]) * rng.uniform(0.5, 1), at)
    place(y, lowpass(noise(1.0), 400) * env_exp(int(1.0 * SR), 0.3) * 0.3, 1.0)
    save("pipes_knock", y, 0.7)
    tt = t(2.5)
    f = 120 * np.exp(-tt * 1.2)
    down = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.linspace(1, 0, len(tt))
    save("power_down", down + lowpass(noise(2.5), 300) * 0.1 * np.linspace(1, 0, len(tt)), 0.6)
    save("ui_click", bandpass(noise(0.03), 1000, 6000) * env_exp(int(0.03 * SR), 0.005), 0.4)


def ash():
    """Ash scenario: coughs, a crowbar in the door gap, tape, shovel, the bus."""
    # Coughs: a short voiced burst followed by a noisy expulsion, x2-3.
    for i in range(3):
        r = np.random.default_rng(40 + i)
        y = np.zeros(int(1.4 * SR))
        at = 0.0
        for k in range(2 + i % 2):
            burst = groan_voice(0.08, 180 + 20 * k, 140, "a", rasp=1.5, seed=50 + 3 * i + k) * 0.6
            air = bandpass(r.standard_normal(int(0.22 * SR)), 300, 3500) * env_exp(int(0.22 * SR), 0.06)
            air += lowpass(r.standard_normal(int(0.22 * SR)), 250) * env_exp(int(0.22 * SR), 0.04) * 0.8
            place(y, burst, at)
            place(y, air, at + 0.05)
            at += r.uniform(0.28, 0.4)
        save("cough_%d" % i, y, 0.7)
    # Crowbar: metal levering in a door gap, creak + grinding squeal + thud.
    for i in range(2):
        d = 1.6
        tt = t(d)
        f = 900 + 400 * np.sin(2 * np.pi * (0.6 + 0.2 * i) * tt) + 60 * np.sin(2 * np.pi * 23 * tt)
        squeal = np.sin(2 * np.pi * np.cumsum(f) / SR) * bandpass(noise(d), 500, 4000) * 0.6
        squeal *= adsr(len(tt), 0.2, 0.3, 0.6, 0.4)
        y = squeal + resonator(d, [140, 380, 1250], [0.2, 0.1, 0.05], [1, 0.5, 0.3]) * 0.8
        place(y, lowpass(noise(0.2), 300) * env_exp(int(0.2 * SR), 0.05) * 1.5, 1.2)
        save("crowbar_%d" % i, y, 0.8)
    # Tape: a fast rip of a packing-tape roll.
    for i in range(2):
        d = 0.7
        tt = t(d)
        rip = bandpass(noise(d), 1500, 9000) * (1 + 0.8 * np.sign(np.sin(2 * np.pi * (60 + 30 * i) * tt)))
        save("tape_%d" % i, rip * adsr(len(tt), 0.02, 0.1, 0.8, 0.15), 0.5)
    # Shovel in wet ash: a gritty scrape and a dump.
    d = 1.3
    scrape = bandpass(noise(d), 200, 3000) * adsr(int(d * SR), 0.1, 0.2, 0.7, 0.3)
    scrape *= 1 + 0.5 * np.sin(2 * np.pi * 9 * t(d))
    place(scrape, lowpass(noise(0.4), 250) * env_exp(int(0.4 * SR), 0.12) * 1.5, 0.9)
    save("shovel", scrape, 0.7)
    # Evacuation bus: a diesel idle with two horn blasts (major third, like a Japanese bus).
    d = 4.0
    tt = t(d)
    diesel = lowpass(noise(d), 150) * (1 + 0.5 * np.sin(2 * np.pi * 28 * tt)) * 0.6
    y = diesel.copy()
    for at in (1.0, 1.9):
        h = int(0.6 * SR)
        th = np.arange(h) / SR
        horn = (np.sign(np.sin(2 * np.pi * 330 * th)) + 0.8 * np.sign(np.sin(2 * np.pi * 415 * th))) * 0.3
        place(y, lowpass(horn, 2500) * adsr(h, 0.03, 0.05, 0.9, 0.1), at)
    save("bus", y * np.minimum(1, tt / 0.8), 0.8)


def tide():
    """Tide scenario: typhoon wind, rain on glass, debris hits, knocking, the crank, a boat."""
    r = np.random.default_rng(1919)  # own generator: regenerating only these keeps the rest identical

    def rnoise(dur):
        return r.standard_normal(int(dur * SR))

    # Typhoon wind around the building: a roaring low band whose strength
    # surges in gusts, a whistle in the balcony railings, a buffeting rumble.
    d = 12.0
    tt = t(d)
    gust = np.zeros(len(tt))
    for k in range(9):  # slow overlapping gust envelopes
        c, w = r.uniform(0, d), r.uniform(0.8, 2.2)
        gust += np.exp(-0.5 * ((tt - c) / w) ** 2) * r.uniform(0.5, 1.0)
        gust += np.exp(-0.5 * ((tt - c + d) / w) ** 2) * 0.5  # wrap so the loop doesn't dip
    gust = 0.45 + gust / gust.max()
    roar = bandpass(rnoise(d), 120, 900) * gust
    hiss = bandpass(rnoise(d), 1200, 5000) * 0.25 * gust ** 1.5
    fw = 820 + 260 * np.sin(2 * np.pi * 0.11 * tt) + 120 * gust
    whistle = np.sin(2 * np.pi * np.cumsum(fw) / SR) * 0.05 * np.clip(gust - 0.9, 0, None)
    thump = lowpass(rnoise(d), 60) * 0.9 * gust
    save("wind_storm", fade_loop(roar + hiss + whistle + thump, 1.5), 0.6)
    # Wind-driven rain on glass: dense fine ticks over a wash, in sheets.
    d = 8.0
    tt = t(d)
    wash = bandpass(rnoise(d), 800, 9000) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.23 * tt) ** 2)
    ticks = np.zeros(len(tt))
    for k in range(2600):
        n = int(r.uniform(0.0015, 0.004) * SR)
        place(ticks, r.standard_normal(n) * np.exp(-np.arange(n) / SR / 0.0008) * r.uniform(0.2, 1.0), r.uniform(0, d - 0.01))
    ticks = highpass(ticks, 1500)
    save("rain_glass", fade_loop(wash * 0.5 + ticks * 0.9, 1.0), 0.5)
    # Debris hitting the glass or frame: a dull slap, a rattle of the sash, a skitter.
    for i in range(3):
        y = np.zeros(int(1.0 * SR))
        place(y, lowpass(rnoise(0.12), 700) * env_exp(int(0.12 * SR), 0.03) * 1.6, 0.0)
        place(y, resonator(0.6, [230 + 40 * i, 610, 1450, 3100], [0.12, 0.07, 0.05, 0.03], [0.8, 0.5, 0.35, 0.2]), 0.0)
        for k in range(6):  # the sash rattling in its frame
            place(y, bandpass(rnoise(0.02), 1500, 6000) * env_exp(int(0.02 * SR), 0.005) * r.uniform(0.2, 0.6), 0.05 + k * r.uniform(0.04, 0.07))
        save("debris_hit_%d" % i, y, 0.85)
    # Knocking on a steel apartment door: three knuckle raps, a little uneven.
    for i in range(3):
        y = np.zeros(int(1.6 * SR))
        at = 0.0
        for k in range(3 + (i == 1)):
            rap = resonator(0.35, [180, 410, 870, 1320], [0.09, 0.06, 0.04, 0.025], [1, 0.7, 0.4, 0.2])
            place(rap, lowpass(rnoise(0.02), 2000) * env_exp(int(0.02 * SR), 0.004) * 0.8, 0.0)
            place(y, rap * r.uniform(0.7, 1.0) * (1.0 - 0.15 * k), at)
            at += r.uniform(0.22, 0.32)
        save("knock_%d" % i, lowpass(y, 2500), 0.8)
    # Hand-crank charger: a geared whirr rising and falling with each turn.
    d = 1.6
    tt = t(d)
    rate = 7.0 + 2.0 * np.sin(2 * np.pi * 1.2 * tt)
    gear = np.sign(np.sin(2 * np.pi * np.cumsum(rate * 22) / SR)) * 0.25
    whirr = bandpass(gear + rnoise(d) * 0.2, 400, 4000) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.2 * tt) ** 2)
    save("crank", whirr * adsr(len(tt), 0.05, 0.1, 0.9, 0.2), 0.6)
    # An outboard motor coming closer over open water: a two-stroke buzz.
    d = 6.0
    tt = t(d)
    f0 = 55 + 6 * np.sin(2 * np.pi * 0.3 * tt)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    engine = sum(np.sin(k * ph) / k for k in range(1, 12)) + bandpass(rnoise(d), 300, 2500) * 0.25
    engine = lowpass(engine, 2200) * (1 + 0.3 * np.sin(2 * np.pi * 5.0 * tt))
    slap = lowpass(rnoise(d), 400) * (0.4 + 0.3 * np.sin(2 * np.pi * 0.7 * tt)) * 0.4  # hull on the water
    save("boat", (engine + slap) * np.minimum(1, tt / 2.5) * np.minimum(1, (d - tt) / 0.5), 0.8)


GROUPS = (footsteps, doors, bangs, breaks, groans, combat, work, phone, alarm, quake, loops, ambience, misc, ash, tide)


def main():
    """`make_sounds.py` makes everything; `make_sounds.py tide ash` only those groups."""
    import sys
    os.makedirs(OUT, exist_ok=True)
    want = set(sys.argv[1:])
    for fn in GROUPS:
        if want and fn.__name__ not in want:
            continue
        fn()
        print("made", fn.__name__)


if __name__ == "__main__":
    main()
