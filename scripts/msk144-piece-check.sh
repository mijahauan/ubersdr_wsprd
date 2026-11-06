#!/usr/bin/env bash
# One piece of the MSK144 port against the reference, byte for byte:
#
#   scripts/msk144-piece-check.sh PIECE
#
# builds scripts/msk144-PIECE-oracle.f90 against WSJT-X's own library
# (scripts/msk144-oracle.sh fortran, in the wsjtx-oracle image) and
# scripts/msk144-PIECE-check.cpp against the port's sources with jt9's
# floating-point flags (CMakeLists.txt's FT8_FP_OPTIONS), runs the oracle,
# gives its output to the driver on stdin, and diffs the two outputs. Exit 0
# when they are identical. The oracle makes its own fixed inputs and prints
# them with its results; the driver reads the inputs back out of that output
# and prints the port's results in the same format.
#
# A later piece adds its oracle, its driver, and one line to the table below
# (the port's sources that driver links).
#
# ldpc also checks intermediate values: the oracle gets, appended, a copy of
# the reference's lib/bpdecode128_90.f90 (sed: renamed bpdecode128_90_trace,
# plus a declaration and one call, at the top of each iteration, of
# msk144_trace_print, which prints checksums of zn and tov), and the port's
# optional hook (bpdecode128_90_trace in src/msk144_ldpc.h) prints the same.
# The sed anchors are checked: the script stops if the reference moved.
#
# frontend also checks intermediate values: the oracle gets, appended, a copy
# of the reference's lib/analytic.f90 (sed: renamed analytic_trace, plus two
# calls, one before the filter's `if( beq )`, one before `c(1)=0.5*c(1)` and
# one after it, that print the filter response h, the equalizer corr, and c
# after the forward FFT, after the filter and after the half of the DC term), and the port's hook (analytic_trace in
# src/msk_frontend.h) prints the same. It also runs msk144_freq_search once
# per trial frequency, for each trial's correlation peak. The driver links
# FFTW (-lfftw3f).
#
# sync also checks intermediate values: the oracle gets, appended, two copies
# of the reference's routines (sed: lib/msk144sync.f90 renamed
# msk144sync_trace, with calls that print the constants pp and cb at its first
# call and c and xcc before its peak search; lib/msk144spd.f90 renamed
# msk144spd_trace, with calls that print its constants, its spectrum windows,
# each step's peaks and ratios, the detection arrays and median, the
# candidates, each call of msk144sync, and where it calls msk144decodeframe a
# hook that runs the reference's frame decoder and prints a hash of what it was
# given and what it answered). The port's hooks (sync_trace and spd_trace in
# src/msk144_sync.h) print the same; the port's frame decoder is a driver
# stand-in that replays the reference's answers (the real one is a later
# piece). Every case also runs the library's routines and the oracle stops if
# a copy's results differ from them.
#
# The oracle is compiled afresh on every run (scripts/msk144-oracle.sh fortran
# does not cache by name), so an edit to a oracle's source always shows.
#
# Flags: the driver is built with what CMakeLists.txt gives jt9's MSK144
# files: FT8_FP_OPTIONS (-ffp-contract=off, plus -mno-fma on GCC before 13
# for x86-64), on top of CMake's Release -O3 and the -march=x86-64-v3
# default. To verify they still match: run
#   cmake --build build -t jt9 -- VERBOSE=1 (after touching src/msk144_ldpc.cpp)
# and compare the compile line of msk144_ldpc.cpp with `flags` below.
#
#   MSK144_ORACLE_WORK=DIR   as scripts/msk144-oracle.sh (default
#                            ~/.cache/msk144-oracle); needs its `build`
#
# Pieces: ldpc frontend sync
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
piece=${1:-}
case $piece in
    ldpc) sources="src/msk144_ldpc.cpp src/ft8_ldpc.cpp src/wsprd_osd.cpp" ;;
    frontend) sources="src/msk_frontend.cpp src/ft8_maths.cpp src/fft.cpp src/fft_wisdom.cpp" ;;
    sync) sources="src/msk144_sync.cpp src/msk_frontend.cpp src/ft8_maths.cpp src/fft.cpp src/fft_wisdom.cpp" ;;
    *) sed -n '/^# Pieces:/p' "$0" | sed 's/^# //' >&2; exit 2 ;;
esac
oracle_src=$repo/scripts/msk144-$piece-oracle.f90
driver_src=$repo/scripts/msk144-$piece-check.cpp
[[ -f $oracle_src && -f $driver_src ]] || { echo "msk144-piece-check: $piece has no oracle or driver" >&2; exit 2; }

work=${MSK144_ORACLE_WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/msk144-oracle}/piece-$piece
mkdir -p "$work"

# jt9's flags: CMake's Release (-O3) and FT8_FP_OPTIONS: -ffp-contract=off,
# and -mno-fma on GCC before 13 for x86-64; -march=x86-64-v3 as the default
# build, where this CPU has AVX2.
cxx=${CXX:-c++}
flags=(-std=c++17 -O3 -DNDEBUG -ffp-contract=off -Wall -Wextra -I "$repo/src")
if [[ $(uname -m) == x86_64 ]]; then
    gccmajor=$("$cxx" -dumpversion | cut -d. -f1)
    [[ $("$cxx" --version | head -1) != *clang* && $gccmajor -lt 13 ]] && flags+=(-mno-fma)
    grep -q avx2 /proc/cpuinfo && flags+=(-march=x86-64-v3)
fi
srcs=(); for s in $sources; do srcs+=("$repo/$s"); done

# the oracle's source: for ldpc, with the instrumented copy of the reference's routine appended
oracle_full=$oracle_src
if [[ $piece == ldpc ]]; then
    ref=${WSJTX:-$HOME/repos/wsjtx}/lib/bpdecode128_90.f90
    oracle_full=$work/msk144-ldpc-oracle-traced.f90
    sed -e 's/^subroutine bpdecode128_90(/subroutine bpdecode128_90_trace(/' \
        -e 's/^end subroutine bpdecode128_90$/end subroutine bpdecode128_90_trace/' \
        -e 's/^  real Tmn$/&\n  logical ltrace\n  common \/msktrace\/ ltrace/' \
        -e 's/^! Check to see if we have a codeword (check before we do any iteration)\.$/    if( ltrace ) call msk144_trace_print(iter,zn,tov)\n&/' \
        "$ref" > "$work/trace-routine.f90"
    [[ $(diff "$ref" "$work/trace-routine.f90" | grep -c '^>') == 5 ]] ||
        { echo "msk144-piece-check: the sed instrumentation did not apply to $ref" >&2; exit 1; }
    cat "$oracle_src" "$work/trace-routine.f90" > "$oracle_full"
fi

if [[ $piece == frontend ]]; then
    ref=${WSJTX:-$HOME/repos/wsjtx}/lib/analytic.f90
    oracle_full=$work/msk144-frontend-oracle-traced.f90
    sed -e 's/^subroutine analytic(/subroutine analytic_trace(/' \
        -e 's/^end subroutine analytic$/end subroutine analytic_trace/' \
        -e 's/^  if( beq ) then$/  call msk144_dump_hcf(h,corr,c,nfft)\n&/' \
        -e 's/^  c(1)=0\.5\*c(1) .*$/  call msk144_dump_g(c,nfft)\n&\n  call msk144_dump_w(c)/' \
        "$ref" > "$work/trace-routine.f90"
    [[ $(diff "$ref" "$work/trace-routine.f90" | grep -c '^>') == 5 ]] ||
        { echo "msk144-piece-check: the sed instrumentation did not apply to $ref" >&2; exit 1; }
    cat "$oracle_src" "$work/trace-routine.f90" > "$oracle_full"
fi

if [[ $piece == sync ]]; then
    lib=${WSJTX:-$HOME/repos/wsjtx}/lib
    oracle_full=$work/msk144-sync-oracle-traced.f90
    sed -e 's/^subroutine msk144sync(/subroutine msk144sync_trace(/' \
        -e 's/^end subroutine msk144sync$/end subroutine msk144sync_trace/' \
        -e 's/^     first=\.false\.$/&\n     call msk144_sync_consts(pp,cb)/' \
        -e 's/^! Find npeaks largest peaks$/  call msk144_sync_peak(xmax,fest,c,xcc,nfreqs)\n&/' \
        "$lib/msk144sync.f90" > "$work/trace-sync.f90"
    [[ $(diff "$lib/msk144sync.f90" "$work/trace-sync.f90" | grep -c '^>') == 4 ]] ||
        { echo "msk144-piece-check: the sed instrumentation did not apply to $lib/msk144sync.f90" >&2; exit 1; }
    sed -e 's/^subroutine msk144spd(/subroutine msk144spd_trace(/' \
        -e 's/^end subroutine msk144spd$/end subroutine msk144spd_trace/' \
        -e 's/^     first=\.false\.$/&\n     call msk144_spd_consts(rcw)/' \
        -e 's/^  i4000=nint(nfhi\/df) + 1$/&\n  call msk144_spd_win(ihlo,ihhi,illo,ilhi,i2000,i4000)/' \
        -e 's/^    detfer(istp)=ferr$/&\n    call msk144_spd_step(istp,ihpk,ilpk,deltah,deltal,ah,al,trath,tratl,ferr)/' \
        -e 's/^  xmed=detmet(indices(nstep\/4))$/&\n  call msk144_spd_med(nstep,indices,xmed,detmet,detmet2,detfer)/' \
        -e 's/^  npeaks=2$/  call msk144_spd_cands(ndet,nstart,ferrs,snrs)\n&/' \
        -e 's/call msk144sync(cdat,3,/call msk144sync_trace(cdat,3,/' \
        -e 's/^           nsyncsuccess,xmax,c)$/&\n      call msk144_spd_sync(icand,iav,nsyncsuccess,fest,xmax,npkloc)/' \
        -e 's/call msk144decodeframe(ct,softbits,msgreceived,ndecodesuccess)/call msk144_frame_hook(ct,softbits,msgreceived,ndecodesuccess)/' \
        "$lib/msk144spd.f90" > "$work/trace-spd.f90"
    [[ $(diff "$lib/msk144spd.f90" "$work/trace-spd.f90" | grep -c '^>') == 10 ]] ||
        { echo "msk144-piece-check: the sed instrumentation did not apply to $lib/msk144spd.f90" >&2; exit 1; }
    cat "$oracle_src" "$work/trace-sync.f90" "$work/trace-spd.f90" > "$oracle_full"
fi

# the oracle
oracle=$("$repo/scripts/msk144-oracle.sh" fortran "$oracle_full" "msk144-$piece-oracle")
"$repo/scripts/msk144-oracle.sh" exec "$oracle" "$repo" > "$work/oracle.out"

# sync: the release jt9 links the OpenMP variant of the library (msk144sync then runs
# min(4, OMP_GET_MAX_THREADS()) threads, each with a slice of the trial frequencies, merged by a strict >).
# The port is serial. The same oracle, linked against libwsjt_fort_omp.a with -fopenmp and run with four
# threads (a full team: OMP_DYNAMIC=false, OMP_THREAD_LIMIT unset), must print the same.
if [[ $piece == sync ]]; then
    oracle_omp=$("$repo/scripts/msk144-oracle.sh" fortran "$oracle_full" "msk144-$piece-oracle-omp" omp)
    "$repo/scripts/msk144-oracle.sh" exec env -u OMP_THREAD_LIMIT OMP_NUM_THREADS=4 OMP_DYNAMIC=false \
        "$oracle_omp" "$repo" > "$work/oracle-omp.out"
    cmp -s "$work/oracle.out" "$work/oracle-omp.out" ||
        { echo "msk144-piece-check: sync: the OpenMP library at 4 threads DIFFERS: diff $work/oracle.out $work/oracle-omp.out" >&2
          diff "$work/oracle.out" "$work/oracle-omp.out" | head -10 >&2 || true; exit 1; }
fi

# the driver (no output file if the port is missing: the link fails)
rm -f "$work/driver"
"$cxx" "${flags[@]}" "$driver_src" "${srcs[@]}" -lfftw3f -lm -lpthread -o "$work/driver"
"$work/driver" < "$work/oracle.out" > "$work/driver.out"

if cmp -s "$work/oracle.out" "$work/driver.out"; then
    if [[ $piece == frontend ]]; then
        echo "msk144-piece-check: $piece: identical ($(wc -l < "$work/oracle.out") lines: $(grep -c '^A' "$work/oracle.out") analytic, $(grep -c '^T' "$work/oracle.out") tweak1, $(grep -c '^S' "$work/oracle.out") freq_search, $(grep -c '^Q' "$work/oracle.out") trial peaks)"
        exit 0
    fi
    if [[ $piece == sync ]]; then
        echo "msk144-piece-check: sync: identical, and the OpenMP library at 4 threads the same ($(wc -l < "$work/oracle.out") lines: $(grep -c '^SYN' "$work/oracle.out") msk144sync and $(grep -c '^SPD' "$work/oracle.out") msk144spd runs; $(awk '$1 == "X" && $3 == 1 && $4 !~ /^\|/' "$work/oracle.out" | wc -l) msk144sync successes; $(grep -c '^F ' "$work/oracle.out") frame decodes replayed ($(grep -c '^F .* [1-9][0-9]* |' "$work/oracle.out") decoded); $(grep -c '^T' "$work/oracle.out") spd steps, $(grep -c '^[LJKW] ' "$work/oracle.out") piece cases)"
        exit 0
    fi
    echo "msk144-piece-check: $piece: identical ($(wc -l < "$work/oracle.out") lines, $(grep -c '^R' "$work/oracle.out") decodes run, $(grep -c '^I' "$work/oracle.out") trace lines, $(grep -c '^P' "$work/oracle.out") platanh and $(grep -c '^T' "$work/oracle.out") tanh values, $(awk '$1 == "R" && $4 >= 0' "$work/oracle.out" | wc -l) decoded, $(grep -c '^C' "$work/oracle.out") CRC checks)"
else
    echo "msk144-piece-check: $piece: DIFFERS: diff $work/oracle.out $work/driver.out" >&2
    diff "$work/oracle.out" "$work/driver.out" | head -10 >&2 || true
    exit 1
fi
