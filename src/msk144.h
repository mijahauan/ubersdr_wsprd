// MSK144's real-time decoder and its file driver: WSJT-X's mskrtd.f90
// (with update_recent_shmsgs) and decode_msk144.f90 (decode_msk144_core) at 567ad29ce (3.2.0-rc1), line for
// line, giving the reference's numbers to the bit on x86-64. It rests on what
// src/msk144_sync.h, src/msk144_decode.h and src/msk_frontend.h rest on.
//
// mskrtd keeps state from call to call in `save`d variables: the dupe
// checker's last message and SNR, the noise level, the last time, the
// period's UTC. Here that state is an RtdState, one per file: WSJT-X's jt9
// runs one process per file, so the state never crosses files, and the port
// resets it (and the packjt77 tables, msk144_reset_packjt77()) at the start
// of every file, --feed included. That covers the MSK40 hash table and the
// recent SWL messages too (nhasharray, recent_shmsgs).
//
// The short-message decoder msk40spd (src/msk40.h) runs when bshmsg or bswl
// is true. Both are false in WSJT-X's jt9 file mode; here --msk-shmsg and
// --msk-swl set them (off by default), as scripts/msk144-oracle.sh's patched
// reference does with MSK144_SHMSG and MSK144_SWL.
//
// Joe Taylor, K1JT, Steven Franke, K9AN, and the WSJT-X team (GNU GPL v3),
// and so is this.
#pragma once

#include <array>
#include <cstdint>
#include <ostream>
#include <string>

#include "msk40.h"
#include "msk_frontend.h"
#include "packjt77.h"

namespace msk144 {

// mskrtd's saved variables (its `save` and `data` statements), and the
// arrays it keeps.
struct RtdState {
    static constexpr int NFFT1 = 8192;
    bool first = true;
    float tsec0 = 0.0f;
    int nutc00 = 0;
    float pnoise = -1.0f;
    std::array<cfloat, NFFT1> cdat{};  // the analytic signal (saved by the Fortran, written whole each call)
    std::string msglast = std::string(37, ' ');
    std::string msglastswl = std::string(37, ' ');
    int nsnrlast = -99;
    int nsnrlastswl = -99;
    std::array<double, 5> pcoeffs{};  // decode_msk144's pcoeffs: zeros
    static constexpr int NSHMEM = 50;  // number of recent SWL messages to remember
    std::array<std::string, NSHMEM> recent_shmsgs = [] {
        std::array<std::string, NSHMEM> a;
        for (auto& m : a) m = std::string(37, ' ');
        return a;
    }();
    Msk40State m40;  // nhasharray, and msk40decodeframe's mycall0, hiscall0 and ihash
    // The state a fresh jt9 process starts with.
    void reset() { *this = RtdState(); }
};

// mskrtd(id2, nutc0, tsec, ntol, nrxfreq, ndepth, mycall, hiscall, bshmsg,
// btrain, pcoeffs, bswl, datadir, line) with btrain false:
// id2 the NZ = 7168 samples of a block, mycall and hiscall character*12
// (blank padded to 12), pk the module packjt77's tables. Returns the
// Fortran's `line` (char(0) in its first place when nothing was decoded) as
// the text up to its char(0): empty for none.
std::string mskrtd(RtdState& st, packjt77::Packjt77& pk, const int16_t* id2, int nutc0, float tsec, int ntol,
                   int nrxfreq, int ndepth, const std::string& mycall12, const std::string& hiscall12, bool bshmsg,
                   bool bswl);

// decode_msk144_core(audio_samples, params, data_dir, completion): the
// decode lines of one file's samples (audio, `nsamples` of them, the rest
// of the period zero), each as the Fortran writes it with format a80 (80
// characters and a newline), to out. ntr is params%ntr (the period in whole
// seconds), ntol params%ntol (already limited), nfqso params%nfqso. Returns
// message_count (bshmsg and bswl as in mskrtd). The caller resets st and the
// packjt77 tables first.
int decode_msk144(RtdState& st, packjt77::Packjt77& pk, const int16_t* audio, long nsamples, int nutc, int ntr, int ntol,
                  int nfqso, int ndepth, const std::string& mycall12, const std::string& hiscall12, bool bshmsg, bool bswl,
                  std::ostream& out);

}  // namespace msk144
