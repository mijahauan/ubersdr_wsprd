# MSK144: WSJT-X 3.0.2 against 3.2.0-rc1

The stations run 3.0.2's `jt9` today. The port follows 3.2.0-rc1 (commit
`567ad29ce`) and matches it byte for byte on all 367 stored runs. This file
lists where 3.0.2 (commit `ccdfaf3c1`) differs from those stored outputs, and
which WSJT-X change explains each difference. The A/B lists differences. It
fixes none.

Run it with `scripts/msk144-ab-302.sh [JT9]`.

## What ran

- **3.0.2's jt9**: `/opt/git/sigmond/wsjtx/build-sigmond/jt9` on this host
  (x86-64), as sigmond builds it: Release with `-march=native -O3
  -fbounds-check -funroll-all-loops`, OpenMP linked. One process per file,
  `OMP_DYNAMIC` and `OMP_THREAD_LIMIT` unset, each run in a fresh directory,
  as the 3.2.0-rc1 references were made.
- **Compared**: stdout, exit status, stderr and the files left in the
  directory, against `tests/data/msk144/cases`.
- **Runs compared**: 293 of the 367. Left out, 74: the 35 `shmsg` and 36 `swl`
  runs, the `swl-state` runs that pass `--msk-swl` (`jt9-files` and
  `jt9-feed`), and the other `jt9-feed` run (3.0.2 has no `--feed`; its
  `jt9-files` twin covers the same files). 3.0.2's `decode_msk144` also fixes
  `bshmsg` and `bswl` false and has no option for them. Patching 3.0.2 the way
  the reference was patched would give them a counterpart. We did not.
- **Result**: 267 runs the same, 26 different.

The 26 fall into three causes. A second build separates source from build
flags: 3.0.2's source, built in the `wsjtx-oracle` image with 3.0.2's own
CMake and no `-march=native`, gives the same 26 differences, so none comes
from the compiler flags. Single changes then went into that tree, one build
each:

| tree | differing runs |
|---|---:|
| 3.0.2 as it is | 26 |
| plus `c7df4aced` (`msk144sync.f90`) | 19 |
| plus `c7df4aced` and `591214b05`'s `msk144spd.f90`, `msk_spectrum.f90` | 12 |

The last twelve come from `71f683f9e`. That attribution rests on the error
texts, which first appear in that commit (`git log -S`). We did not rebuild
with it.

## The 26 differences

### 1. `msk144sync` passed the wrong array element: 7 runs

| run | 3.2.0-rc1 (the port) | 3.0.2 |
|---|---|---|
| `sample-181211_120800/d1`, `/d3`, `/ms` | `1455` Hz | `1453` Hz |
| `odd-clipped/d1`, `/d3`, `/ms` | `1455` Hz | `1453` Hz |
| `width-1-sp00/defaults` | `5.2` s, `1500` Hz | `5.3` s, `1499` Hz |

The decoded message, SNR and the other decode of each file stay the same. Only
the reported frequency (and once DT) moves.

Cause: `c7df4aced`, "Fix a bug in msk144sync.f90. Thanks to WA6BEV!"
(Steven Franke, 2026-02-19). `msk144sync` handed `msk144_freq_search` the
element `xccs(1,id)`. The array runs from index 0, so the callee's
`xccs(0:NSPM-1)` started one sample late. 3.2.0-rc1 passes the section
`xccs(:,id)`. The commit is not in 3.0.2. Confirmed by building 3.0.2 with
that one line changed: all seven runs then match.

### 2. A frequency window past the spectrum: 7 runs

`freq-edge/f0-F1000`, `f200-F1000`, `f200-F200`, `f200-F700`, `f6000-F5000`,
`f800-F1000`, `f9000-F1000`.

3.2.0-rc1 prints its decodes (or only `<DecodeFinished>`) and exits 0. 3.0.2
prints nothing, writes this to stderr and exits 2:

```
At line 94 of file .../lib/msk144spd.f90        (line 102 for f200-F200, f200-F700, f800-F1000)
Fortran runtime error: Index '-71' of dimension 1 of array 'ismask' outside of expected range (1:864)
```

The index differs by run (`-71`, `-42`, `-143`, `-100`, `1081`, `1225`).
For `f0-F1000`, `f200-F1000`, `f200-F700` and `f800-F1000`, 3.2.0-rc1 decodes
`K1ABC W9XYZ EN37` that 3.0.2 never reaches.

Cause: `591214b05`, "fix(msk): harden spectrum edge processing" (David
Christle, 2026-08-18). 3.0.2's `msk144spd` computes the high and low tone
windows with `nint` and indexes `ismask` with them even when `-f` and `-F`
push the window past bins 1 to 864. 3.2.0-rc1 clips the window first
(`msk_clip_spectrum_window` in the new `lib/msk_spectrum.f90`) and returns
when nothing remains. The abort belongs to the sigmond build's
`-fbounds-check`. 3.2.0-rc1's CMake dropped that flag (`b954366c8`, "remove
bounds checks and limit loop unrolling"). A 3.0.2 without the flag would index
outside the array without stopping. We did not build that one. Confirmed by
replacing `msk144spd.f90` and adding `msk_spectrum.f90` in the 3.0.2 tree: all
seven runs match.

The same commit also adds the finiteness checks, the `nstep` cap and the
`xmax` initialisation the spec names. No corpus run reaches them.

### 3. Input validation in `jt9`: 12 runs

`odd-bits8`, `odd-rate11025` and `odd-stereo`, each at `d1`, `d3`, `defaults`
and `ms`.

| | 3.2.0-rc1 (the port) | 3.0.2 |
|---|---|---|
| 8-bit, stereo WAV | stderr `jt9: cannot read WAV file ...: unsupported WAV format; expected mono 16-bit PCM`, `STOP 2`, exit 2 | ` EOF on input file ...`, `<DecodeFinished>   0   0        0`, exit 0 |
| 11025 Hz WAV | stderr `jt9: unsupported 11025 Hz WAV sample rate for the selected mode`, `STOP 2`, exit 2 | the same ` EOF` line, exit 0 |

3.0.2 also leaves an empty `decoded.txt` for the 11025 Hz and the stereo file;
3.2.0-rc1 stops before it opens one.

Cause: `71f683f9e`, "fix(jt9): validate CLI and WAV inputs" (David Christle,
2026-07-17): `jt9_input_validation.f90`, a stricter `readwav.f90` and
`jt9.f90`. Both error texts first appear there. The port's WAV reader follows
3.2.0-rc1.

## Changes between the two that no corpus run shows

`git log ccdfaf3c1..567ad29ce` over the MSK144 files and `jt9`:

- `591214b05` also changes `msk144_freq_search`, `msk40_freq_search`, `msk40spd`
  and `msk40sync`: finite-value checks, the outputs (`xmax`, `bestf`, `cs`,
  `xccs`) set before the search, the frame count `NSPM*nframes` in place of
  `7*NSPM`, the first frequency always taken as the best so far, and the
  `xccs(:,id)` section in `msk40sync` that `c7df4aced` gave `msk144sync`. The
  corpus decodes show no effect from the first four. The `msk40` changes lie
  in the `shmsg` and `swl` runs, which 3.0.2 cannot take.
- `8540841e1`: `tweak1` takes `twopi` as a parameter, and `msk40sync` gains
  ThreadSanitizer hooks. No effect on output.
- `a70de72cf`, `decode_msk144` reworked around a completion record and a
  streaming emitter: output of the file mode stays as it was.
- `genmsk_128_90`, `msk144code`, `msk144sim` (signal generation, not decoding).
- `e2291855d`, `4df348dc5`: freeing the decoder's workspace, and `wav12`'s
  `save`.

## Reading it

On ordinary signals both versions decode the same: 267 of 293 runs agree
character for character. Where they differ, 3.0.2 reports a carrier 1 or 2 Hz
off on some decodes, aborts when `-f`/`-F` put a window past the
spectrum, and accepts WAV files that 3.2.0-rc1 refuses. The stations move from
the first to the second knowing this.
