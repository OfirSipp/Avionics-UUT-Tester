"""
ila_plot.py - ILA-style waveform captures of the testbenches

Runs both testbenches in GHDL or nvc with a VCD dump, then draws five captures
in the look of a logic-analyzer waveform window into docs/img/:
  ila_overview.png  the whole tb_Tone_Recognition run: signals, glitches, results
  ila_glitch.png    one glitch absorbed by the grace cycles, then a real edge
  ila_alert2.png    Alert 2 declared on the 6th matching segment
  ila_adc.png       one LTC2327 conversion read by ADC_LTC
  ila_dac.png       one DAC8043 transfer by DAC8043FP2

Usage:  python sim/ila_plot.py [--sim ghdl|nvc] [--reuse]   (needs GHDL or nvc, and matplotlib)
"""
import argparse
import bisect
import math
import os
import re
import shutil
import subprocess
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle

ROOT = Path(__file__).resolve().parent.parent
SRC = ["rtl/Tone_Config.vhd", "rtl/ADC_LTC.vhd", "rtl/DAC8043FP2.vhd", "rtl/Tone_Recognition.vhd",
       "sim/Tone_Generator.vhd", "sim/tb_ADC_DAC.vhd", "sim/tb_Tone_Recognition.vhd"]
# tb_Tone_Recognition: no clock in the dump (63 M edges); it is drawn from its definition
TONE_SIGS = ["sel", "tone", "glitch", "line", "flag", "rec", "valid", "gen/phase",
             "dut/level", "dut/grace_cnt", "dut/seg_len", "dut/n_a1", "dut/n_a2", "dut/n_bad"]
TONE_CLK = (200e-9, 100e-9)            # 5 MHz: period, first rising edge
TONE_HZ = 5e6

C = dict(bg="#000000", pane="#0d1117", head="#161b22", line="#21262d", grid="#1c2128",
         text="#e6edf3", dim="#7d8590", sig="#3fea6b", busfill="#0a2914", analog="#f5c542",
         bad="#ff5c5c", cursor="#f5c542", marker="#4da3ff")
FONT = "Consolas" if os.name == "nt" else "DejaVu Sans Mono"


# --- simulation + VCD ----------------------------------------------------------
class Sig:
    def __init__(self, width):
        self.w, self.t, self.v = width, [], []

    def at(self, t):
        i = bisect.bisect_right(self.t, t) - 1
        return self.v[i] if i >= 0 else "U"

    def window(self, t0, t1):
        """[(t, value)] inside [t0, t1), starting with the value at t0"""
        i = bisect.bisect_right(self.t, t0)
        j = bisect.bisect_left(self.t, t1)
        return [(t0, self.at(t0))] + list(zip(self.t[i:j], self.v[i:j]))

    def becomes(self, value, after=0.0):
        """times at which the signal changes to value"""
        i = bisect.bisect_right(self.t, after)
        return [self.t[k] for k in range(max(i, 1), len(self.t))
                if self.v[k] == value and self.v[k - 1] != value]


def read_vcd(path):
    sigs, ids, scope, header = {}, {}, [], []
    with open(path) as f:
        for line in f:
            header.append(line)
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var":
                name = "/".join(scope[1:] + [tok[4].split("[")[0]])
                sigs[name] = Sig(int(tok[2]))
                ids.setdefault(tok[3], []).append(sigs[name])
            elif tok[0] == "$enddefinitions":
                break
        n, unit = re.search(r"\$timescale\s+(\d+)\s*(\w+)", "".join(header)).groups()
        scale = int(n) * {"s": 1, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15}[unit]
        t = 0.0
        for line in f:
            c = line[0]
            if c == "#":
                t = int(line[1:]) * scale
                continue
            if c in "bB":
                v, code = line[1:].split()
            elif c in "01xzuwlhXZUWLH-":
                v, code = c, line[1:].strip()
            else:
                continue
            for s in ids.get(code, ()):
                s.t.append(t)
                s.v.append(v.zfill(s.w) if s.w > 1 and set(v) <= set("01") and s.w < 32 else v)
    return sigs


def simulate(sim, exe, work, reuse):
    work.mkdir(parents=True, exist_ok=True)
    if reuse and (work / "adc.vcd").exists() and (work / "tone.vcd").exists():
        return read_vcd(work / "adc.vcd"), read_vcd(work / "tone.vcd")

    def run(*args):
        subprocess.run([exe, *args], cwd=work, check=True, capture_output=True, text=True)

    src = [str(ROOT / s) for s in SRC]
    if sim == "ghdl":
        run("-a", "--std=08", *src)
        (work / "tone.opt").write_text(
            "$ version 1.1\n" + "".join(f"/tb_tone_recognition/{s}\n" for s in TONE_SIGS))
        print("tb_ADC_DAC ...")
        run("--elab-run", "--std=08", "tb_ADC_DAC", "--vcd=adc.vcd")
        print("tb_Tone_Recognition ...")
        run("--elab-run", "--std=08", "tb_Tone_Recognition", "--read-wave-opt=tone.opt", "--vcd=tone.vcd")
    else:                                                   # nvc
        run("--std=2008", "-a", *src)
        print("tb_ADC_DAC ...")
        run("--std=2008", "-e", "tb_ADC_DAC", "-r", "--format=vcd", "--wave=adc.vcd")
        print("tb_Tone_Recognition ...")
        inc = [f"--include=:tb_tone_recognition:{s.replace('/', ':')}" for s in TONE_SIGS]
        run("--std=2008", "-e", "tb_Tone_Recognition", "-r", "--format=vcd", "--wave=tone.vcd", *inc)
    return read_vcd(work / "adc.vcd"), read_vcd(work / "tone.vcd")


# --- value formats ----------------------------------------------------------------
def num(v):
    return int(v, 2) if v and set(v) <= set("01") else None


def hexf(v):
    n = num(v)
    return None if n is None else f"{n:0{(len(v) + 3) // 4}X}"


def dec(v):
    n = num(v)
    return None if n is None else str(n)


def ms(v):
    n = num(v)
    return None if n is None else f"{n / TONE_HZ * 1e3:.2f} ms"


REC = {"00": "00 disconnected", "01": "01 other", "10": "10 Alert 1", "11": "11 Alert 2"}
PHASE = {"00": "quiet", "01": "other", "10": "Alert 1", "11": "Alert 2"}


# --- drawing ----------------------------------------------------------------------
def clock_points(period, first, t0, t1):
    k = math.floor((t0 - first) / period)
    pts, t = [], first + k * period
    while t < t1:
        pts += [(t, "1"), (t + period / 2, "0")]
        t += period
    pts = [(t, v) for t, v in pts if t > t0]
    return [(t0, "0" if not pts or pts[0][1] == "1" else "1")] + [p for p in pts if p[0] < t1]


def draw_bit(ax, pts, t1, y, h):
    lo, hi = y + 0.22 * h, y + 0.78 * h
    xs, ys = [], []
    for (t, v), (tn, _) in zip(pts, pts[1:] + [(t1, None)]):
        yy = hi if v in "1H" else lo if v in "0L" else (lo + hi) / 2
        xs += [t, tn]
        ys += [yy, yy]
        if v not in "01LH":
            ax.add_patch(Rectangle((t, lo), tn - t, hi - lo, color=C["bad"], alpha=0.35, lw=0))
    ax.plot(xs, ys, color=C["sig"], lw=1.3, solid_joinstyle="miter")


def draw_bus(ax, pts, t0, t1, y, h, fmt, pxs):
    lo, hi, mid = y + 0.18 * h, y + 0.82 * h, y + 0.5 * h
    slant = 3.5 / pxs
    for (t, v), (tn, _) in zip(pts, pts[1:] + [(t1, None)]):
        label = fmt(v)
        sl = min(slant, (tn - t) / 2) if t > t0 else 0
        sr = min(slant, (tn - t) / 2) if tn < t1 else 0
        poly = [(t, mid), (t + sl, hi), (tn - sr, hi), (tn, mid), (tn - sr, lo), (t + sl, lo)]
        bad = label is None
        ax.add_patch(Polygon(poly, closed=True, fc="#3a0d0d" if bad else C["busfill"],
                             ec=C["bad"] if bad else C["sig"], lw=1.1))
        label = "X" if bad else label
        if (tn - t) * pxs <= 7.6 * len(label) + 10:
            label = label.split()[0]                            # "10 Alert 1" -> "10"
        if (tn - t) * pxs > 7.6 * len(label) + 10:
            ax.text((t + tn) / 2, mid, label, color=C["text"], fontsize=9.5, family=FONT,
                    ha="center", va="center", clip_on=True)


def draw_analog(ax, pts, t1, y, h, vmax):
    lo, hi = y + 0.12 * h, y + 0.88 * h
    xs, ys, vals = [], [], [num(v) or 0 for _, v in pts]
    for (t, _), (tn, _), n in zip(pts, pts[1:] + [(t1, None)], vals):
        yy = lo + (hi - lo) * n / vmax
        xs += [t, tn]
        ys += [yy, yy]
    ax.fill_between(xs, lo, ys, color=C["analog"], alpha=0.12, lw=0)
    ax.plot(xs, ys, color=C["analog"], lw=1.4)
    for (t, _), n, m in zip(pts[1:], vals, vals[1:]):    # label each peak
        if m < n:
            ax.text(t, lo + (hi - lo) * n / vmax + 0.06 * h, str(n), color=C["analog"],
                    fontsize=9.5, family=FONT, ha="right", va="bottom", fontweight="bold")


def nice_ticks(t0, t1):
    span = t1 - t0
    unit, uname = next((u, n) for u, n in [(1, "s"), (1e-3, "ms"), (1e-6, "us"), (1e-9, "ns")]
                       if span >= 2 * u)
    raw = span / 10
    mag = 10 ** math.floor(math.log10(raw))
    step = next(m * mag for m in (1, 2, 5, 10) if m * mag >= raw)
    digits = max(0, -math.floor(math.log10(step / unit) + 1e-9))
    ticks = [k * step for k in range(math.ceil(t0 / step), math.floor(t1 / step) + 1)]
    return ticks, [f"{t / unit:.{digits}f}" for t in ticks], uname


def capture(path, title, note, t0, t1, rows, markers=(), cursor=None):
    """rows: (name, kind, data, extra). kind: bit | clk | bus | analog"""
    H = sum(r[3].get("h", 1) for r in rows)
    head, ruler, rowh, foot = 0.85, 0.75, 0.42, 0.2
    W, Hin = 18.0, head + ruler + rowh * H + foot
    fig = plt.figure(figsize=(W, Hin), dpi=110, facecolor=C["bg"])
    yb, hh = foot / Hin, rowh * H / Hin
    L, NW, VW = 0.004, 0.15, 0.085
    ax = fig.add_axes([L + NW + VW + 0.004, yb, 1 - (L + NW + VW + 0.004) - 0.006, hh + 0.38 / Hin])
    an = fig.add_axes([L, yb, NW, hh])
    av = fig.add_axes([L + NW + 0.002, yb, VW, hh])
    top = H + 0.38 / rowh                                   # room for marker labels
    pxs = ax.get_position().width * W * fig.dpi / (t1 - t0)

    for a in (ax, an, av):
        a.set_facecolor(C["bg"] if a is ax else C["pane"])
        a.set_ylim(0, top if a is ax else H)
        for s in a.spines.values():
            s.set_color(C["line"])
    for a in (an, av):
        a.set_xlim(0, 1)
        a.set_xticks([])
        a.set_yticks([])
    ax.set_xlim(t0, t1)
    ax.set_yticks([])

    origin = markers[0][0] if markers and t0 > 50 * (t1 - t0) else 0.0   # T = first marker
    ticks, labels, uname = nice_ticks(t0 - origin, t1 - origin)
    ax.set_xticks([t + origin for t in ticks], labels)
    ax.xaxis.tick_top()
    ax.tick_params(axis="x", colors=C["dim"], labelsize=10, length=4)
    for lab in ax.get_xticklabels():
        lab.set_family(FONT)
    for t in ticks:
        ax.axvline(t, color=C["grid"], lw=0.8, zorder=0)
    fig.text(L + 0.003, yb + hh + 0.2 / Hin, "Name", color=C["dim"], fontsize=10, family=FONT)
    fig.text(L + NW + 0.005, yb + hh + 0.2 / Hin, "Value", color=C["dim"], fontsize=10, family=FONT)
    fig.text(L + NW + VW, yb + hh + 0.2 / Hin, f"{'t - T' if origin else 'time'} [{uname}]", color=C["dim"],
             fontsize=10, family=FONT, ha="right")

    cur = cursor if cursor is not None else t1
    y = H
    for name, kind, data, ex in rows:
        h = ex.get("h", 1)
        y -= h
        ax.axhline(y, color=C["line"], lw=0.6)
        an.axhline(y, color=C["line"], lw=0.6)
        av.axhline(y, color=C["line"], lw=0.6)
        if kind == "clk":
            pts = clock_points(*data, t0, t1)
            if len(pts) > 900:                              # too dense to draw edge by edge
                ax.add_patch(Rectangle((t0, y + 0.22 * h), t1 - t0, 0.56 * h, color=C["sig"], alpha=0.3, lw=0))
            else:
                draw_bit(ax, pts, t1, y, h)
            value = "clk"
        else:
            pts = data.window(t0, t1)
            if kind == "bit":
                draw_bit(ax, pts, t1, y, h)
            elif kind == "bus":
                draw_bus(ax, pts, t0, t1, y, h, ex["fmt"], pxs)
            else:
                draw_analog(ax, pts, t1, y, h, ex["vmax"])
            fmt = ex.get("fmt", lambda v: v if kind == "bit" else dec(v))
            value = fmt(data.at(cur)) or "X"
        an.text(0.04, y + h / 2, name, color=C["text"], fontsize=10.5, family=FONT, va="center")
        if ex.get("sub"):
            an.text(0.96, y + h / 2, ex["sub"], color=C["dim"], fontsize=9, family=FONT, va="center", ha="right")
        av.text(0.08, y + h / 2, value, color=C["sig"], fontsize=10, family=FONT, va="center")

    if cursor is not None:
        ax.axvline(cursor, color=C["cursor"], lw=1.4, zorder=5)
    for i, (t, label) in enumerate(markers):
        ax.axvline(t, color=C["marker"], lw=1.1, ls=(0, (5, 3)), zorder=5)
        right = (t - t0) / (t1 - t0) > 0.72
        label = f"T  {label}" if origin and i == 0 else label
        ax.text(t, H + (0.1 if i % 2 else 0.45) * 0.38 / rowh, f" {label} ", color="#0d1117",
                fontsize=9.5, family=FONT, fontweight="bold", ha="right" if right else "left",
                va="bottom", zorder=6, bbox=dict(boxstyle="square,pad=0.2", fc=C["marker"], ec="none"))

    fig.patches.append(Rectangle((0, 1 - head / Hin), 1, head / Hin, transform=fig.transFigure,
                                 color=C["head"], zorder=-1))
    fig.text(0.008, 1 - 0.36 / Hin, title, color=C["text"], fontsize=15, fontweight="bold", family=FONT)
    fig.text(0.008, 1 - 0.68 / Hin, note, color=C["dim"], fontsize=10.5, family=FONT)
    fig.text(0.994, 1 - 0.36 / Hin, "Avionics UUT Tester  ·  VHDL simulation",
             color=C["dim"], fontsize=10, family=FONT, ha="right")
    if origin:
        fig.text(0.994, 1 - 0.68 / Hin, f"T = {origin * 1e3:.6f} ms", color=C["dim"],
                 fontsize=10, family=FONT, ha="right")
    fig.savefig(path, facecolor=C["bg"])
    plt.close(fig)
    print("wrote", path)


# --- the five captures ------------------------------------------------------------
def tone_captures(S, out):
    starts = S["flag"].becomes("1")
    phase_at = {t: S["sel"].at(t) for t in starts}
    verdicts = S["valid"].becomes("1")
    clk = TONE_CLK

    # overview
    end = max(sig.t[-1] for sig in S.values() if sig.t) + 0.05
    marks = []
    for v in verdicts:
        p = max(t for t in starts if t <= v)
        marks.append((v, f"{S['rec'].at(v)} after {(v - p) * 1e3:.0f} ms"))
    capture(out / "ila_overview.png", "tb_Tone_Recognition - whole run",
            "Tone_Generator plays each signal (example tones from rtl/Tone_Config.vhd), Tone_Recognition "
            "is restarted, must report it and hold it 500 ms. A 1-29-cycle glitch hits the line every 5.3 ms.",
            0, end, [
                ("sel[1:0]", "bus", S["sel"], dict(fmt=lambda v: PHASE.get(v), sub="generator")),
                ("iFlagBinaryRec", "bit", S["flag"], {}),
                ("oTone", "bit", S["tone"], dict(sub="generator")),
                ("n_a1", "bus", S["dut/n_a1"], dict(fmt=dec, sub="Alert 1 segs")),
                ("n_a2", "bus", S["dut/n_a2"], dict(fmt=dec, sub="Alert 2 segs")),
                ("n_bad", "bus", S["dut/n_bad"], dict(fmt=dec, sub="no match")),
                ("oRecognized[1:0]", "bus", S["rec"], dict(fmt=lambda v: REC.get(v))),
                ("oFlagRecognized", "bit", S["valid"], {}),
            ], marks)

    # one glitch absorbed, then a real edge: a glitch inside a high half,
    # followed closely by the tone's own falling edge
    a1 = next(t for t in starts if phase_at[t] == "10")
    other = next(t for t in starts if phase_at[t] == "01")
    best = None
    for s in S["glitch"].becomes("1", a1):
        if s > other:
            break
        e = next(t for t in S["glitch"].becomes("0", s))
        if S["tone"].window(s - 2e-6, e + 1e-6)[1:] or S["tone"].at(s) != "1":
            continue
        te = S["tone"].becomes("0", e)[0]
        if 2e-6 < te - e < 9e-6 and (best is None or e - s > best[1] - best[0]):
            best = (s, e, te)
    s, e, te = best
    tl = S["dut/level"].becomes("0", te)[0]
    n = round((e - s) / TONE_CLK[0])
    capture(out / "ila_glitch.png", "Tone_Recognition - 30 grace cycles",
            f"A {n}-cycle glitch flips the line and grace_cnt counts it, but the line returns "
            f"in time: absorbed. The real edge holds for 30 cycles: accepted.",
            s - 3e-6, tl + 3e-6, [
                ("iclk", "clk", clk, dict(sub="5 MHz sim")),
                ("oTone", "bit", S["tone"], dict(sub="generator")),
                ("glitch", "bit", S["glitch"], dict(sub="testbench")),
                ("iBinaryRec", "bit", S["line"], dict(sub="tone^glitch")),
                ("grace_cnt", "analog", S["dut/grace_cnt"], dict(vmax=30, h=2.2, fmt=dec)),
                ("level", "bit", S["dut/level"], dict(sub="accepted")),
            ], [(s, "glitch starts"), (e, f"line back: absorbed ({n} < 30)"),
                (te, "real edge"), (tl, "30 cycles: level changes")], cursor=e - 1e-9)

    # Alert 2 declared
    a2 = next(t for t in starts if phase_at[t] == "11")
    tv = next(v for v in verdicts if v > a2)
    capture(out / "ila_alert2.png", "Tone_Recognition - Alert 2 declared",
            f"Each finished segment that fits Alert 2 raises n_a2. The 6th in a row "
            f"(3 full cycles) declares 11, {(tv - a2) * 1e3:.0f} ms after the start.",
            tv - 6e-3, tv + 2.5e-3, [
                ("iBinaryRec", "bit", S["line"], {}),
                ("phase", "bus", S["gen/phase"], dict(fmt=lambda v: {"0": "tone A", "1": "tone B"}.get(v),
                                                       sub="generator")),
                ("seg_len", "bus", S["dut/seg_len"], dict(fmt=ms, sub="segment")),
                ("n_a2", "bus", S["dut/n_a2"], dict(fmt=dec, sub="Alert 2 segs")),
                ("n_bad", "bus", S["dut/n_bad"], dict(fmt=dec)),
                ("oRecognized[1:0]", "bus", S["rec"], dict(fmt=lambda v: REC.get(v))),
                ("oFlagRecognized", "bit", S["valid"], {}),
            ], [(tv, "6th segment: Alert 2 declared")], cursor=tv + 1e-9)


def adc_dac_captures(S, out):
    clk = S["clk"]
    td = S["adc_data"].becomes("0111111111111110")[0]
    tc = [t for t in S["adc_cnv"].becomes("1") if t < td][-1]
    tb = S["adc_busy"].becomes("0", tc)[0]
    tf = S["adc_flag"].becomes("0", tc)[0]
    capture(out / "ila_adc.png", "ADC_LTC - one LTC2327-16 conversion",
            "oCNV starts a conversion, BUSY falls, 16 SCK periods shift the word in MSB first, "
            "then oDATA and oFlag change together.",
            tc - 0.3e-6, td + 0.6e-6, [
                ("iclk", "bit", clk, dict(sub="50 MHz")),
                ("ADC input", "bus", S["adc_value"], dict(fmt=hexf, sub="model")),
                ("oCNV", "bit", S["adc_cnv"], {}),
                ("iBusy", "bit", S["adc_busy"], {}),
                ("oSCK", "bit", S["adc_sck"], {}),
                ("iSDO", "bit", S["adc_sdo"], {}),
                ("shreg[15:0]", "bus", S["adc/shreg"], dict(fmt=hexf)),
                ("bit_cnt", "bus", S["adc/bit_cnt"], dict(fmt=dec)),
                ("oDATA[15:0]", "bus", S["adc_data"], dict(fmt=hexf)),
                ("oFlag", "bit", S["adc_flag"], {}),
            ], [(tc, "oCNV: convert"), (tb, "BUSY low: MSB on SDO"), (tf, "oFlag low: shifting"),
                (td, "oDATA = 7FFE, oFlag high")], cursor=td + 1e-9)

    tq = S["dac_flag"].becomes("1")[0]
    tl = S["dac_ld"].becomes("0", tq)[0]
    th = S["dac_ld"].becomes("1", tl)[0]
    capture(out / "ila_dac.png", "DAC8043FP2 - one DAC8043 transfer",
            "A rising iFlag starts the transfer: 12 bits leave MSB first on SRI, one per CLK "
            "rising edge, then LD loads the DAC register once with the whole word.",
            tq - 0.3e-6, th + 0.4e-6, [
                ("iclk", "bit", clk, dict(sub="50 MHz")),
                ("iData[11:0]", "bus", S["dac_word"], dict(fmt=hexf)),
                ("iFlag", "bit", S["dac_flag"], {}),
                ("shreg[11:0]", "bus", S["dac/shreg"], dict(fmt=hexf)),
                ("oSDT", "bit", S["dac_sdt"], dict(sub="-> SRI")),
                ("oCLK", "bit", S["dac_clk"], {}),
                ("oLD", "bit", S["dac_ld"], {}),
                ("DAC register", "bus", S["dac_out"], dict(fmt=hexf, sub="model")),
            ], [(tq, "iFlag high: word ready"), (tl, "oLD low: load"), (th, "done")], cursor=th + 1e-9)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--sim", choices=["ghdl", "nvc"], help="simulator (default: ghdl if found, else nvc)")
    ap.add_argument("--exe", help="simulator executable (default: found on PATH)")
    ap.add_argument("--work", default=os.path.join(os.environ.get("TEMP", "/tmp"), "uut_tester_waves"))
    ap.add_argument("--out", default=str(ROOT / "docs" / "img"))
    ap.add_argument("--reuse", action="store_true", help="redraw from the last VCDs, no simulation")
    a = ap.parse_args()
    sim = a.sim or ("ghdl" if shutil.which("ghdl") else "nvc")
    adc, tone = simulate(sim, a.exe or sim, Path(a.work), a.reuse)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    tone_captures(tone, out)
    adc_dac_captures(adc, out)


if __name__ == "__main__":
    main()
