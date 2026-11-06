// The port's side of scripts/msk144-piece-check.sh ldpc: reads the oracle's
// output (scripts/msk144-ldpc-oracle.f90) on stdin, takes its L and C lines
// as inputs, and prints every line as the reference printed it, the R and C
// results from src/msk144_ldpc.cpp instead. The two outputs must be
// identical byte for byte.
//
// License: GNU GPL v3 (as WSJT-X)
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

#include "msk144_ldpc.h"

int main() {
    std::string line;
    float llr[128] = {};
    signed char m77[77] = {};
    int iv = 0;
    while (std::getline(std::cin, line)) {
        if (line.rfind("L ", 0) == 0) {
            ++iv;
            for (int i = 0; i < 128; ++i) {
                const uint32_t b = static_cast<uint32_t>(std::strtoul(line.substr(2 + 8 * i, 8).c_str(), nullptr, 16));
                std::memcpy(&llr[i], &b, 4);
            }
            std::puts(line.c_str());
        } else if (line.rfind("R ", 0) == 0) {
            const int maxiter = (iv % 5 == 0) ? 30 : 10;
            int nharderror = -99, iter = -99;
            signed char cw[128] = {};
            msk144::bpdecode128_90(llr, maxiter, m77, cw, nharderror, iter);
            signed char word[90];
            std::memcpy(word, cw, 90);
            const int nbadcrc = msk144::chkcrc13a(word) ? 0 : 1;
            std::string m, c;
            for (int i = 0; i < 77; ++i) m += static_cast<char>('0' + m77[i]);
            for (int i = 0; i < 128; ++i) c += static_cast<char>('0' + cw[i]);
            std::printf("R %d %d %d %s %s %d\n", maxiter, iter, nharderror, m.c_str(), c.c_str(), nbadcrc);
        } else if (line.rfind("C ", 0) == 0) {
            signed char word[90];
            for (int i = 0; i < 90; ++i) word[i] = static_cast<signed char>(line[2 + i] - '0');
            std::printf("C %s %d\n", line.substr(2, 90).c_str(), msk144::chkcrc13a(word) ? 0 : 1);
        }
    }
    return 0;
}
