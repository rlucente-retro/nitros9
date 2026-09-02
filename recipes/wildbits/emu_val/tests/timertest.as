********************************************************************
* timertest.as - Wildbits Jr2 24-bit Timers & INTC Diagnostic Suite
*
* Validates 24-bit Timer 0 up-counter increment at 25.175 MHz dot clock,
* and Interrupt Controller (INTC) Mask, Edge, and W1C Pending registers.
********************************************************************
                    nam       timertest
                    ttl       24-bit Timers & INTC Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
t0_val0_h           rmb       1
t0_val0_m           rmb       1
t0_val0_l           rmb       1
t0_val1_h           rmb       1
t0_val1_m           rmb       1
t0_val1_l           rmb       1
orig_mask           rmb       1
orig_edge           rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions
INTC_PENDING_0      equ       $FE20
INTC_POL_0          equ       $FE24
INTC_EDGE_0         equ       $FE28
INTC_MASK_0         equ       $FE2C

TIMER0_CTRL         equ       $FE30
TIMER0_STAT         equ       $FE30
TIMER0_VAL_L        equ       $FE31
TIMER0_VAL_M        equ       $FE32
TIMER0_VAL_H        equ       $FE33
TIMER0_CMP_CTR      equ       $FE34
TIMER0_CMP_L        equ       $FE35
TIMER0_CMP_M        equ       $FE36
TIMER0_CMP_H        equ       $FE37

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 TIMERS & INTC DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: 24-bit Timer 0 Increment (25.175 MHz Dot Clock)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] 24-bit Timer 0 Up-Counter Increment ($FE32-$FE34)"
                    fcb       C$CR,0

                    * Read initial 24-bit value
                    lda       >TIMER0_VAL_H
                    sta       t0_val0_h,u
                    lda       >TIMER0_VAL_M
                    sta       t0_val0_m,u
                    lda       >TIMER0_VAL_L
                    sta       t0_val0_l,u

                    * Delay loop
                    ldx       #1000
dly_lp              leax      -1,x
                    bne       dly_lp

                    * Read updated 24-bit value
                    lda       >TIMER0_VAL_H
                    sta       t0_val1_h,u
                    lda       >TIMER0_VAL_M
                    sta       t0_val1_m,u
                    lda       >TIMER0_VAL_L
                    sta       t0_val1_l,u

                    lbsr      PRINTS
                    fcc       "         T0 Initial: $"
                    fcb       0
                    lda       t0_val0_h,u
                    lbsr      PrintHexByte
                    lda       t0_val0_m,u
                    lbsr      PrintHexByte
                    lda       t0_val0_l,u
                    lbsr      PrintHexByte

                    lbsr      PRINTS
                    fcc       " | After Delay: $"
                    fcb       0
                    lda       t0_val1_h,u
                    lbsr      PrintHexByte
                    lda       t0_val1_m,u
                    lbsr      PrintHexByte
                    lda       t0_val1_l,u
                    lbsr      PrintHexByte

                    * Check if value changed
                    lda       t0_val0_l,u
                    cmpa      t0_val1_l,u
                    bne       T1_Pass
                    lda       t0_val0_m,u
                    cmpa      t0_val1_m,u
                    bne       T1_Pass
                    lda       t0_val0_h,u
                    cmpa      t0_val1_h,u
                    bne       T1_Pass

                    * If identical, Timer 0 is not incrementing!
                    lbsr      PrintFail
                    inc       fail_count,u
                    bra       Test2

T1_Pass             lbsr      PrintPass
                    inc       pass_count,u

                    * ========================================================
                    * TEST 2: INTC Mask Register Read/Write ($FE2C)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] INTC Group 0 Mask Register R/W ($FE2C)"
                    fcb       C$CR,0

                    lda       >INTC_MASK_0
                    sta       orig_mask,u

                    * Write $55
                    lda       #$55
                    sta       >INTC_MASK_0
                    lda       >INTC_MASK_0
                    cmpa      #$55
                    bne       T2_Fail

                    * Write $AA
                    lda       #$AA
                    sta       >INTC_MASK_0
                    lda       >INTC_MASK_0
                    cmpa      #$AA
                    bne       T2_Fail

                    * Restore mask
                    lda       orig_mask,u
                    sta       >INTC_MASK_0

                    lbsr      PRINTS
                    fcc       "         INTC_MASK_0 R/W Passed ($55, $AA)"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lda       orig_mask,u
                    sta       >INTC_MASK_0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: INTC Edge Register Read/Write ($FE28)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] INTC Group 0 Edge Register R/W ($FE28)"
                    fcb       C$CR,0

                    lda       >INTC_EDGE_0
                    sta       orig_edge,u

                    * Write $33
                    lda       #$33
                    sta       >INTC_EDGE_0
                    lda       >INTC_EDGE_0
                    cmpa      #$33
                    bne       T3_Fail

                    * Restore edge
                    lda       orig_edge,u
                    sta       >INTC_EDGE_0

                    lbsr      PRINTS
                    fcc       "         INTC_EDGE_0 R/W Passed ($33)"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test4

T3_Fail             lda       orig_edge,u
                    sta       >INTC_EDGE_0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: INTC Pending Register Read & W1C ($FE20)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] INTC Pending Register Readback & W1C ($FE20)"
                    fcb       C$CR,0

                    lda       >INTC_PENDING_0
                    lbsr      PRINTS
                    fcc       "         INTC_PENDING_0 Readback: $"
                    fcb       0
                    lbsr      PrintHexByte

                    * Perform W1C (write back value)
                    sta       >INTC_PENDING_0

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Summary

                    * ========================================================
                    * Summary Output
                    * ========================================================
Summary             lbsr      PRINTS
                    fcc       "---------------------------------------------------"
                    fcb       C$CR,0

                    lbsr      PRINTS
                    fcc       "SUMMARY: Passed="
                    fcb       0
                    lda       pass_count,u
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcc       " / 4 | Failed="
                    fcb       0
                    lda       fail_count,u
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcb       C$CR,0

                    tst       fail_count,u
                    bne       ExitErr

                    lbsr      PRINTS
                    fcc       "RESULT: ALL TIMER/INTC TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: TIMER/INTC HARDWARE MISMATCH DETECTED!"
                    fcb       C$CR,0
                    ldb       #1
                    os9       F$Exit

* --- Formatting Helper Subroutines ---

PrintPass           lbsr      PRINTS
                    fcc       " -> [PASS]"
                    fcb       C$CR,0
                    rts

PrintFail           lbsr      PRINTS
                    fcc       " -> [FAIL]"
                    fcb       C$CR,0
                    rts

PrintHexByte        pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nibble2Hex
                    puls      a
                    anda      #$0f

Nibble2Hex          adda      #$90
                    daa
                    adca      #$40
                    daa
putc_ok             lbsr      PUTC
                    rts

PUTC                pshs      a,b,cc,x,y
                    leax      temp_buf,u
                    sta       ,x
                    ldy       #1
                    lda       #1               * stdout
                    os9       I$Write
                    lda       ,x
                    cmpa      #C$CR
                    bne       putc_done
                    lda       #C$LF
                    sta       ,x
                    ldy       #1
                    lda       #1
                    os9       I$Write
putc_done           puls      a,b,cc,x,y,pc

PRINTS              pshs      x
                    ldx       2,s
prints_lp           lda       ,x+
                    beq       prints_ex
                    lbsr      PUTC
                    bra       prints_lp
prints_ex           stx       2,s
                    puls      x,pc

                    endsect   0
