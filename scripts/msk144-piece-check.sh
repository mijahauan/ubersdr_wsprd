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
#   MSK144_ORACLE_WORK=DIR   as scripts/msk144-oracle.sh (default
#                            ~/.cache/msk144-oracle); needs its `build`
#
# Pieces: ldpc
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
piece=${1:-}
case $piece in
    ldpc) sources="src/msk144_ldpc.cpp src/ft8_ldpc.cpp src/wsprd_osd.cpp" ;;
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

# the oracle
oracle=$("$repo/scripts/msk144-oracle.sh" fortran "$oracle_src" "msk144-$piece-oracle")
"$repo/scripts/msk144-oracle.sh" exec "$oracle" > "$work/oracle.out"

# the driver (no output file if the port is missing: the link fails)
rm -f "$work/driver"
"$cxx" "${flags[@]}" "$driver_src" "${srcs[@]}" -o "$work/driver"
"$work/driver" < "$work/oracle.out" > "$work/driver.out"

if cmp -s "$work/oracle.out" "$work/driver.out"; then
    echo "msk144-piece-check: $piece: identical ($(wc -l < "$work/oracle.out") lines, $(grep -c '^R' "$work/oracle.out") decodes run, $(awk '$1 == "R" && $4 >= 0' "$work/oracle.out" | wc -l) decoded, $(grep -c '^C' "$work/oracle.out") CRC checks)"
else
    echo "msk144-piece-check: $piece: DIFFERS: diff $work/oracle.out $work/driver.out" >&2
    diff "$work/oracle.out" "$work/driver.out" | head -10 >&2 || true
    exit 1
fi
