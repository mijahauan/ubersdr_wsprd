! WSJT-X's (128,90) LDPC decoder and CRC-13 check, for
! scripts/msk144-piece-check.sh ldpc: generates its own fixed inputs and
! prints them and what the reference does with them, for
! scripts/msk144-ldpc-check.cpp (src/msk144_ldpc.cpp) to match line for line.
! Built against WSJT-X's own library (libwsjt_fort.a): encode_128_90,
! bpdecode128_90, chkcrc13a.
!
!   L HEX*128          the soft bits (float bits, 8 hex digits each)
!   R maxiter iter nharderror message77 cw128 nbadcrc
!                      bpdecode128_90 with apmask 0 on the L line above;
!                      message77 carries over from vector to vector (it is
!                      written only on success); nbadcrc is chkcrc13a on
!                      cw(1:90)
!   C BITS90 nbadcrc   chkcrc13a on a 90-bit word
!
! Inputs: a 32-bit LCG (x = x*1664525 + 1013904223 mod 2**32, seed 20261106);
! 200 random 77-bit messages encoded by encode_128_90, soft bits
! (2/s**2)*(+-1 + s*g) with g a sum of 12 uniforms less 6, at s = 0.55, 0.75
! and 0.95 in turn (maxiter 10, as msk144decodeframe) and every fifth at
! maxiter 30; then 40 of pure noise; then 90-bit words for chkcrc13a: the
! first 90 bits of 40 codewords, each also with one bit flipped, and 40
! random.
!
! License: GNU GPL v3 (as WSJT-X)
program msk144_ldpc_oracle
   implicit none
   integer*8 :: state
   integer*1 :: apmask(128), msg(77), cw(128), cwout(128), m77(77), word(90), enc(40,128)
   real :: llr(128), sigma(0:2), s
   integer :: ibits(128), iv, i, j, maxiter, iter, nharderror, nbadcrc, nenc
   data sigma/0.55, 0.75, 0.95/

   apmask = 0
   state = 20261106_8
   m77 = 0
   nenc = 0
   do iv = 1, 240
      if (iv .le. 200) then
         do i = 1, 77
            msg(i) = int(nextu() * 2.0d0, 1)
         enddo
         call encode_128_90(msg, cw)
         if (nenc .lt. 40) then
            nenc = nenc + 1
            enc(nenc, :) = cw
         endif
         s = sigma(mod(iv, 3))
         do i = 1, 128
            llr(i) = (2.0 / (s * s)) * (real(2 * cw(i) - 1) + s * gauss())
         enddo
      else
         do i = 1, 128
            llr(i) = 4.0 * gauss()
         enddo
      endif
      maxiter = 10
      if (mod(iv, 5) .eq. 0) maxiter = 30
      ibits = transfer(llr, ibits)
      write(*, '(a,128z8.8)') 'L ', ibits
      nharderror = -99
      iter = -99
      cwout = 0
      call bpdecode128_90(llr, apmask, maxiter, m77, cwout, nharderror, iter)
      word = cwout(1:90)
      call chkcrc13a(word, nbadcrc)
      write(*, '(a,i0,1x,i0,1x,i0,1x,77i1,1x,128i1,1x,i0)') 'R ', maxiter, iter, nharderror, m77, cwout, nbadcrc
   enddo

   do iv = 1, 40
      word = enc(iv, 1:90)
      call chkcrc13a(word, nbadcrc)
      write(*, '(a,90i1,1x,i0)') 'C ', word, nbadcrc
      i = 1 + int(nextu() * 90.0d0)
      word(i) = 1 - word(i)
      call chkcrc13a(word, nbadcrc)
      write(*, '(a,90i1,1x,i0)') 'C ', word, nbadcrc
      do j = 1, 90
         word(j) = int(nextu() * 2.0d0, 1)
      enddo
      call chkcrc13a(word, nbadcrc)
      write(*, '(a,90i1,1x,i0)') 'C ', word, nbadcrc
   enddo
contains
   real(8) function nextu()
      state = mod(state * 1664525_8 + 1013904223_8, 4294967296_8)
      nextu = real(state, 8) / 4294967296.0d0
   end function nextu
   real function gauss()
      real(8) :: t
      integer :: k
      t = -6.0d0
      do k = 1, 12
         t = t + nextu()
      enddo
      gauss = real(t)
   end function gauss
end program msk144_ldpc_oracle
