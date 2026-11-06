# MSK144 test corpus

The reference outputs for `jt9 -k` (`--msk144`): WSJT-X 3.2.0-rc1, commit
567ad29ce, built in the `wsjtx-oracle` image by `scripts/msk144-oracle.sh`.
Every piece of the port checks itself against these files, or against a small
Fortran oracle built from the same tree.

## Regenerate

    git clone https://github.com/wsjtx/wsjtx ~/repos/wsjtx
    git -C ~/repos/wsjtx checkout 567ad29ce
    scripts/msk144-oracle.sh all            # builds, then makes the corpus
    scripts/msk144-oracle.sh --print-env    # paths of the binaries

`DOCKER=podman` picks the container runner; without it the script uses docker
if present, else podman. The script builds jt9 and `msk144sim` three times:

| build     | what                                                              |
|-----------|-------------------------------------------------------------------|
| `release` | WSJT-X's own Release flags: the reference, `$MSK144_REF`          |
| `o2`      | `-O2 -ffp-contract=off`; must agree with `release` on every run   |
| `patched` | `release` with `bshmsg` and `bswl` read from `MSK144_SHMSG=1` and `MSK144_SWL=1` in the environment (`$MSK144_REF_PATCHED`) |

WSJT-X's `decode_msk144.f90` sets both switches false and offers no way to
turn them on. The sed patch in the script (recorded in `BUILD.txt`) replaces
the two initial values by reads of those variables. With both set, both are
forced true. With one set, the build gives what `--msk-shmsg` or `--msk-swl`
alone must give. With neither, it decodes as `release` (the script checks this
on the two WSJT-X samples).

`scripts/msk144-oracle.sh fortran FILE.f90` compiles a Fortran oracle against
the reference's `libwsjt_fort.a` and prints the binary's path. `exec CMD`
runs a command in the image with the work dir and repository mounted at their
own paths.

## Layout

    tests/data/msk144/cases/CASE/jt9-VARIANT/{args.txt,stdout.txt,status.txt[,stderr.txt],decoded.txt}
    tests/data/msk144/inputs/SHA256SUMS      sha256sum -c, run from the repository root
    recordings/msk144-samples/               WSJT-X's samples
    recordings/msk144-sim/                   the generated grid (+ MANIFEST: case, T/R)
    recordings/msk144-real/                  a real slot

`args.txt` holds `jt9` and its arguments, paths from the repository root.
`decoded.txt` is the empty file jt9 opens: MSK144 writes nothing to it.
`scripts/jt9-compare.sh` names a run `msk144-CASE/VARIANT`.

## Variants

| variant    | arguments (T/R of the case in place of 15)                         | from    |
|------------|--------------------------------------------------------------------|---------|
| `d1`       | `-a . -k -p 15 -f 1500 -F 200 -d 1`                                | release |
| `d3`       | `-a . -k -p 15 -f 1500 -F 200 -d 3`                                | release |
| `defaults` | `-a . -k -p 15` (jt9's own `-f`, `-F`, `-d`)                       | release |
| `ms`       | `-Y --msk144 -p 15 -f 1500 -F 200 -d 3 -a .`: the line meteor-scatter runs (`build_jt9_cmd` in its `core/decoder.py`), with `-a .` for its work dir | release |
| `bare`     | `-a . -k` alone (jt9's 60 s period); the four samples only         | release |
| `shmsg`    | as `d3`, plus `--msk-shmsg`                                        | patched, `MSK144_SHMSG=1` |
| `swl`      | as `d3`, plus `--msk-swl`                                          | patched, `MSK144_SWL=1` |

`-Y` is jt9's FST4W switch; `--msk144` after it wins, as the last mode does.
`shmsg` and `swl` exist for the samples, the real slot, the SNR sweep, the
message types, the pings, the MSK40 cases, the two `msk144sim` cases, silence,
noise and the clipped file. Our jt9 does not take `--msk-shmsg` and
`--msk-swl` yet: `jt9-compare.sh` and `jt9-wine-check.sh` skip those two
variants until its usage lists them, then check them against the stored
outputs (the reference has no such option to run beside).

## Inputs

**WSJT-X's samples.** `181211_120500.wav` and `181211_120800.wav` come from
`samples/MSK144/` in the 567ad29ce tree. `160915_113100.wav` and
`160915_113230.wav` are not in that tree or in 3.0.2's. They came from an
earlier session's scratch directory, where someone had fetched them from
WSJT-X's sample download (https://sourceforge.net/projects/wsjt/files/samples/MSK144/);
the session kept no record of the exact URL. Both are 12 kHz mono 16-bit,
15 s. Neither decodes with the reference (the 2016 recordings predate the
128/90 LDPC format of 2019), so they test the no-decode path on real audio.

**Generated grid.** `scripts/msk144-sim-grid.sh` drives two generators:
WSJT-X's `msk144sim` (two cases, `stock-*`, its usage examples) and
`scripts/msk144-sim.f90` (`msk144-sim`), which takes the choices `msk144sim`
fixes: pings per slot and their times, seeded noise, MSK40 frames. Both run
against WSJT-X's own `genmsk_128_90` (which calls `genmsk40`), `makepings`'
ping shape and `gran`'s noise scaling. File *n* has seed 1000+*n*. Axes, each
swept with the others at their base (`K1ABC W9XYZ EN37`, 1500 Hz, one ping
0.2 s wide at 5 s, T/R 15 s):

- `snr-*`: -8 to +10 dB in 2 dB steps
- `freq-*`: offsets 0, +-100, +-200 Hz, at +4 and -2 dB
- `width-*`: 0.05, 0.2, 1, 5 s and `slot` (the whole slot at peak amplitude), at +4 and 0 dB
- `pings1-*`, `pings3-*`: one and three pings a slot, at 0 and +6 dB
- `tr30-*`: T/R 30 s, two pings, at -2, +4, +10 dB; `tr30-wide-s04` has width 2.5 s
- `msg-*`: CQ, report, RRR, prefix, suffix, free text, at +6 dB
- `msk40-*`: four MSK40 frames (`<K1ABC W9XYZ> +03` and three more), for Task 7's short-message flag
- `odd-*`: `silence` (zeros), `noise` (noise alone), `tr30-run-p15` (30 s file with `-p 15`), `short7` (7 s file, `-p 15`), `clipped` (`181211_120800` at 40x gain, clipped); and `stereo`, `rate11025`, `bits8`, `header`, `tiny`, made by `scripts/jt9-compare.sh`'s own generator (`@I/` in `args.txt`)

**Real.** `msk144_261023_105030.wav`: 30 s of 6 m (50.260 MHz) audio from
AC0G/B4's meteor-scatter recorder, slot start 2026-10-23 10:50:30 UTC. Its
sidecar JSON records one decode, `C67MIP/P BI7CEG/P NN73` at -8 dB, and a
frontend status of "partial" (radiod status packets missing for part of the
slot). Two cases run it: `real-261023-p30`
(T/R 30 s) and `real-261023-p15` (its first 15 s). Copied from
`proofs/agu-2026/spectrum/data/`.

**Raw station slots.** None kept. meteor-scatter keeps no raw slots by
default, so the corpus holds no hour of undecoded slots from a station. The
design (section 7) wants that hour; it needs a station with slot retention
switched on.

## What the reference does here

- 66 cases, 338 runs. `release` and `o2` agree on all 268 runs of the plain variants.
- On the SNR sweep, depth 1 decodes down to -2 dB and depth 3 down to -4 dB. At -6 dB and below nothing decodes.
- `-F 200` reaches all four +-200 Hz offsets at depth 3; at depth 1 three of the four fail. `defaults` (`-F 20`) loses every offset but 0.
- MSK40 frames decode only under `shmsg` or `swl`, and not all of them: `msk40-rpt03` decodes under neither, `msk40-r03` only under `swl`. The port must reproduce that.
- The clipped file still decodes (two lines, as the unclipped sample).
- The stereo, 11025 Hz and 8-bit files end with status 2 and a line on stderr; the header-only and tiny files end 0.
