# MSK144 in UberSDR's jt9 — design

**Status:** design approved by Michael Hauan (AC0G), 2026-11-06; plan in docs/superpowers/plans/.  Fork: github.com/mijahauan/ubersdr_wsprd,
upstream madpsy/ubersdr_wsprd at 529ec5d.

## 1. Why

On 2026-10-24 sigmond made UberSDR's jt9 the default decoder on every station (sigmond b4d12f6).
That jt9 decodes FT2, FT4, FT8 and FST4W.  It has no MSK144.  Given `--msk144` it prints its usage
and exits 0, so meteor-scatter ran it on every slot and decoded nothing from each station's switch
onward.  UACNJ had logged between 270 and 660 MSK144 lines a day, 663 at the Orionids peak, and
then none.

meteor-scatter now runs WSJT-X's own jt9 by its full path (meteor-scatter 9babd4c), which restored
decoding on all eight stations on 2026-11-04.  That stopgap leaves each station with two decoder
builds and a client that must know which one to call.  Michael wants one binary.  UberSDR's
README already promises "more of jt9's modes to follow", so MSK144 belongs in it, ported the way
its other modes were ported, and offered back upstream.

## 2. What this builds

`jt9 --msk144` (and `-k`) in UberSDR's jt9, reading WAV files as WSJT-X's jt9 reads them.  For the
same files and the same command line it prints the same lines, writes the same files and exits
with the same status, byte for byte, as the WSJT-X reference named in section 4.

The port follows the house method the README and `scripts/` already set out:

- WSJT-X's Fortran, ported line for line into C++ where it can be, so the two read side by side;
- the same arithmetic contract: `-ffp-contract=off`, `-mno-fma` on GCC below 13, glibc 2.39's maths
  carried through `ft8_maths.h`, so every multiply and add rounds as gfortran's code rounds it;
- small Fortran oracle programs, built from the reference's own routines, that check each piece
  (LDPC, sync, frequency search, the analytic filter) against the port;
- `scripts/jt9-compare.sh` running new and stock jt9 side by side on every test case.

## 3. Goals, non-goals, anti-goals

Goals:

1. Parity with the reference: stdout, stderr, the exit status and every file left in the data
   directory, on x86-64 Linux; on arm64, every printed line.
2. Two options WSJT-X's file mode hard-codes off, exposed as flags: short messages (MSK40, WSJT-X's
   `bshmsg`) and SWL mode (`bswl`).  The MSQP working group asked for both (Robert Suggs,
   2026-10-20).  With both off, which stays the default, parity holds.  With either on, parity holds
   against a reference patched the same way.
3. One jt9 binary on every station for FT8, FT4, FT2, FST4W and MSK144, beside the same build's
   wsprd.
4. CPU no worse than the reference's.  The other modes ran at a third to a seventh; MSK144's cost
   sits mostly in the FFTs and the sync search, so some gain seems likely, but this design promises
   none.

Non-goals:

- `jt9 -s` (shared memory, the WSJT-X program's path) for MSK144.  meteor-scatter runs file mode.
- WebAssembly.
- Real-time decoding inside jt9.  WSJT-X's own `decode_msk144` walks a finished slot in blocks;
  the port does the same.
- Training (`btrain`) and phase equalization (`pcoeffs`): file mode fixes them off and zero.

Anti-goals.  The port fails, even if it decodes, if:

- it decodes something the reference does not, or misses something the reference decodes, on any
  test case — a decoder that differs, however slightly, can no longer be compared with the MSQP
  entrants who run WSJT-X;
- it changes what FT8, FT4, FT2, FST4W or wsprd produce in any existing test;
- a flag's default differs from WSJT-X's.

## 4. The reference: which WSJT-X

Two WSJT-X versions matter, and their MSK144 code differs.

- **3.0.2** (ccdfaf3c1), which sigmond pins and which every station's stopgap runs today.
- **3.2.0-rc1** (567ad29ce), the reference for every mode UberSDR already carries.

Between the two, WSJT-X hardened MSK144: finiteness checks in the frequency search and the
spectral peak search, double-precision bin edges in `msk144sync`, frame counts bounded in
`msk144spd` and `msk40spd`, and `decode_msk144` reworked around a completion record and a
streaming emitter.  On ordinary signals both should decode the same, but a port matched bit for
bit to one need not match the other on edge cases.

**Decided (Michael, 2026-11-04):** port 3.2.0-rc1, the reference the rest of the binary
already holds and the one upstream would accept.  Run 3.0.2 beside it on the whole corpus as an
A/B, and report every difference with the change in WSJT-X that explains it.  The stations then
move from 3.0.2 to 3.2.0-rc1's MSK144 when they move to the new binary, knowingly and with the
differences on paper.

## 5. What gets ported

`decode_msk144` walks the slot in 7168-sample blocks (about 0.6 s) at half-block steps and hands
each block to `mskrtd`, WSJT-X's real-time decoder.  `mskrtd` keeps state between blocks: a noise
estimate, the averaging buffers, and the last message with its SNR, which suppresses a repeat
unless it arrives stronger or earlier.  The closure, counted at 3.0.2:

| Routine | Lines | Notes |
|---|---|---|
| `decode_msk144` | 60 | the block walk, the output lines, `<DecodeFinished>` |
| `mskrtd` | 261 | state across blocks; duplicate suppression; averaging patterns by depth |
| `msk144spd`, `msk144sync`, `msk144_freq_search` | 347 | short-ping detector, sync, frequency search |
| `msk144decodeframe`, `bpdecode128_90` | 229 | frame decode; the (128,90) belief-propagation LDPC with CRC-13 |
| `msk144signalquality` | 213 | runs on every decode; writes files only when training, which file mode never does |
| `msk40spd`, `msk40sync`, `msk40_freq_search`, `msk40decodeframe` | 517 | short messages; reached only with the new flag |
| `bpdecode40`, `encode_msk40`, `hash`, `fmtmsg`, `update_msk40_hasharray` | small | MSK40's code and its hash table |
| `analytic`, `tweak1`, `indexx`, `four2a`, `polyfit`, `chkcrc13a`, `platanh` | shared | some already ported for FT8/FT4 (FFT wrapper, `polyfit`); the rest new |
| `unpack77` | — | already ported (`packjt77.cpp`) |

About 2,000 lines of Fortran, a third of them MSK40.  The house layout suggests `msk144.cpp`
(`decode_msk144` and `mskrtd`), `msk144_sync.cpp`, `msk144_ldpc.cpp` with its tables, `msk40.cpp`,
`msk_frontend.cpp` (`analytic`, `tweak1`, the frequency searches) and `msk144_jt9.cpp` for the
command line, as FT4 has `ft4_jt9.cpp`.

## 6. Command line and output

The port reads what WSJT-X's jt9 reads for MSK144: `-p` the T/R period, `-F` the tolerance, `-f`
the receive frequency, `-d` the depth, `-a` the data directory, `-c` and `-x` my call and his call,
and `-q`.  Everything else WSJT-X takes and ignores, the port takes and ignores.

Three behaviours deserve a line each, because each looks wrong and must stay as it stands:

- **The last mode wins.**  WSJT-X's `-Y` selects FST4W's hash22 mode, and a later `--msk144`
  overrides it.  meteor-scatter has always passed `-Y --msk144`, so its slots have always decoded as
  plain MSK144.  The port parses modes in order, as WSJT-X does.  (meteor-scatter may drop the `-Y`;
  it does nothing.)
- **Decodes go to stdout.**  MSK144 writes nothing to `decoded.txt`; meteor-scatter learned that the
  hard way (877fc0b).
- **Each file starts fresh.**  WSJT-X runs one process per file, so `mskrtd`'s saved state never
  crosses files.  The port resets it per file, `--feed` included, where one process reads many
  files.  Otherwise a repeat across two slots would vanish in the port and not in WSJT-X.

New flags, both off by default:

- `--msk-shmsg`: decode MSK40 short messages.
- `--msk-swl`: SWL mode, which also reports the averaged decodes a QSO operator would not see.

## 7. Proving parity

The oracle: the reference jt9 built in the house's `wsjtx-oracle` image, plus a second build with
`bshmsg` and `bswl` patched on for the flag cases.  Small Fortran oracles, one per piece, in
`scripts/msk144-*-oracle.f90`, compare the LDPC decoder, the sync and frequency search, and the
analytic filter on fixed inputs before the whole decoder exists.

The cases, under `tests/data/msk144/`, each with its SHA256SUMS:

- WSJT-X's four published MSK144 samples (160915_113100, 160915_113230, 181211_120500,
  181211_120800), 15 s at 12 kHz.
- A generated grid from WSJT-X's own `msk144sim`: SNR from below threshold to strong, frequency
  offsets across the tolerance, ping widths from tens of milliseconds to whole slots, several pings
  per slot, T/R of 15 and 30 s; and MSK40 messages from `genmsk40` for the short-message flag.
- Real slots from our stations: decoded recordings from the MSQP archive once it fills, and an hour
  of raw slots, decoded or not, from UACNJ's morning window.  Undecoded slots matter as much as
  decoded ones, since a false decode fails parity too.
- Odd WAVs: short files, 30 s files at a 15 s period, silence, clipping.

Acceptance: `jt9-compare.sh` reports no difference on any `msk144-*` case on x86-64 Linux; on
arm64, no printed line differs.  The 3.0.2 A/B runs on the same cases and its differences get
listed, not fixed.

## 8. Order of work

1. The oracles and the corpus, before any port code, so every later piece lands against a test.
2. LDPC and CRC; then the analytic filter and frequency search; then sync; then the frame decode.
3. `mskrtd` and `decode_msk144`, with the state across blocks; the command line; full-file parity.
4. MSK40 and the two flags.
5. CPU measurement against the reference; the README section, in the house's manner.
6. The pull request to madpsy.

## 9. Into sigmond and meteor-scatter

- sigmond's pin moves to the fork's commit (`_UBERSDR_REPO`, `_UBERSDR_COMMIT` in `bin/smd`), and
  back to upstream's once the pull request merges.  Rob owns `_build_ubersdr_decoders`; the change
  goes to him on the claude-bus first.
- meteor-scatter's `resolve_jt9_binary` already takes the first jt9 whose help lists `--msk144`.
  Once the UberSDR build lists it, meteor-scatter should prefer jt9 on PATH again, and keep the
  check, so a decoder switch can never silence it a second time.
- B4 first, beside the stopgap's WSJT-X build: both decode the same slots for a week and the
  results get compared before any other station moves.

## 10. Decisions for Michael

1. ~~The reference~~ — decided: 3.2.0-rc1, with 3.0.2 as an A/B (section 4).
2. ~~The Geminids~~ — decided (Michael, 2026-11-06): build the port now, and prepare the small
   fleet to monitor the Geminids as a multi-site contribution beside the regular MSQP effort, run
   the way a meteor-shower contest runs.  The fleet moves to the new binary only if it passes parity
   and a week beside the stopgap on B4 by Nov 27; otherwise the stopgap's WSJT-X jt9 carries the
   shower and the move waits until after Dec 20.  *(The Nov 27 gate is my call, from the freeze
   date above.)*

## 11. Left to the builder

- How to split the work across files, within the house layout.
- How to carry `mskrtd`'s saved state in C++ (a struct reset per file seems natural).
- How much of `four2a`, `indexx` and `polyfit` to share with the FT8/FT4 port rather than repeat.
- The exact `msk144sim` grid, within the ranges above.

## Credits and licence

MSK144 and its decoder come from Joe Taylor, K1JT, Steven Franke, K9AN, and the WSJT-X developers,
under the GNU GPL v3; the port carries the same licence, as the rest of UberSDR's decoders do.
