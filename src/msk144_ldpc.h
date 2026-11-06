// MSK144's forward error correction: WSJT-X's (128,90) LDPC belief-
// propagation decoder and its 13-bit CRC check (lib at 567ad29ce:
// bpdecode128_90.f90, ldpc_128_90_reordered_parity.f90, lib/ft8/chkcrc13a.f90,
// lib/crc13.cpp, lib/platanh.f90), giving the reference's results to the bit:
// the same message, codeword, hard-error count and iteration count from the
// same soft bits, and the same message77 left behind when decoding fails.
//
// What it rests on: no multiply-adds fused (-ffp-contract=off, CMakeLists.txt);
// float sums and products in the Fortran's order; glibc's tanhf (tanhf_glibc,
// ft8_ldpc.h), which gfortran calls for tanh of a default real.
//
// bpdecode128_90.f90, chkcrc13a.f90, crc13.cpp: Steven Franke, K9AN, and Joe
// Taylor, K1JT, WSJT-X (GNU GPL v3), and so is this.
#pragma once

namespace msk144 {

// bpdecode128_90(llr, apmask, maxiterations, message77, cw, nharderror, iter),
// with apmask all zero, as msk144decodeframe passes it. message77 is written
// only on success (it keeps its value otherwise, as the Fortran's does); cw is
// the last hard decision; nharderror is -1 on failure; niterations is `iter`
// as the Fortran leaves it (maxiterations+1 when the loop runs out). Bits are
// 0/1. Returns nharderror.
int bpdecode128_90(const float llr[128], int maxiterations, signed char message77[77], signed char cw[128],
                   int& nharderror, int& niterations);

// chkcrc13a(decoded, nbadcrc) with nbadcrc == 0: true when the 13 bits after
// the 77 of decoded(1:90) are the CRC of the 77 (bits 0/1).
bool chkcrc13a(const signed char decoded[90]);

}  // namespace msk144
