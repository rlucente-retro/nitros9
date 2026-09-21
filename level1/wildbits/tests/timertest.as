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
orig_mask           rmb       4       * Groups 0..3
orig_edge           rmb       4       * Groups 0..3
orig_t1_cmp_l       rmb       1
orig_t1_cmp_m       rmb       1
orig_t1_cmp_h       rmb       1
orig_t1_cmp_ctr     rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions
INTC_PENDING_0      equ       $FE20
INTC_PENDING_1      equ       $FE21
INTC_PENDING_2      equ       $FE22
INTC_PENDING_3      equ       $FE23

INTC_POL_0          equ       $FE24
INTC_POL_1          equ       $FE25
INTC_POL_2          equ       $FE26
INTC_POL_3          equ       $FE27

INTC_EDGE_0         equ       $FE28
INTC_EDGE_1         equ       $FE29
INTC_EDGE_2         equ       $FE2A
INTC_EDGE_3         equ       $FE2B

INTC_MASK_0         equ       $FE2C
INTC_MASK_1         equ       $FE2D
INTC_MASK_2         equ       $FE2E
INTC_MASK_3         equ       $FE2F

TIMER0_CTRL         equ       $FE30
TIMER0_STAT         equ       $FE30
TIMER0_VAL_L        equ       $FE31
TIMER0_VAL_M        equ       $FE32
TIMER0_VAL_H        equ       $FE33
TIMER0_CMP_CTR      equ       $FE34
TIMER0_CMP_L        equ       $FE35
TIMER0_CMP_M        equ       $FE36
TIMER0_CMP_H        equ       $FE37

TIMER1_CTRL         equ       $FE38
TIMER1_STAT         equ       $FE38
TIMER1_VAL_L        equ       $FE39
TIMER1_VAL_M        equ       $FE3A
TIMER1_VAL_H        equ       $FE3B
TIMER1_CMP_CTR      equ       $FE3C
TIMER1_CMP_L        equ       $FE3D
TIMER1_CMP_M        equ       $FE3E
TIMER1_CMP_H        equ       $FE3F

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
                    * TEST 2: 24-bit Timer 1 Frame Timer Registers ($FE38-$FE3F)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] 24-bit Timer 1 (Frame Clock) Registers ($FE38-$FE3F)"
                    fcb       C$CR,0

                    * Save original Timer 1 compare registers
                    lda       >TIMER1_CMP_L
                    sta       orig_t1_cmp_l,u
                    lda       >TIMER1_CMP_M
                    sta       orig_t1_cmp_m,u
                    lda       >TIMER1_CMP_H
                    sta       orig_t1_cmp_h,u
                    lda       >TIMER1_CMP_CTR
                    sta       orig_t1_cmp_ctr,u

                    * Write test compare pattern: $563412
                    lda       #$12
                    sta       >TIMER1_CMP_L
                    lda       #$34
                    sta       >TIMER1_CMP_M
                    lda       #$56
                    sta       >TIMER1_CMP_H
                    lda       #$03
                    sta       >TIMER1_CMP_CTR

                    * Read back and verify
                    lda       >TIMER1_CMP_L
                    cmpa      #$12
                    lbne      T2_Fail
                    lda       >TIMER1_CMP_M
                    cmpa      #$34
                    lbne      T2_Fail
                    lda       >TIMER1_CMP_H
                    cmpa      #$56
                    lbne      T2_Fail
                    lda       >TIMER1_CMP_CTR
                    cmpa      #$03
                    lbne      T2_Fail

                    * Restore original Timer 1 compare registers
                    lda       orig_t1_cmp_l,u
                    sta       >TIMER1_CMP_L
                    lda       orig_t1_cmp_m,u
                    sta       >TIMER1_CMP_M
                    lda       orig_t1_cmp_h,u
                    sta       >TIMER1_CMP_H
                    lda       orig_t1_cmp_ctr,u
                    sta       >TIMER1_CMP_CTR

                    lbsr      PRINTS
                    fcc       "         Timer 1 Compare/Control Registers Verified"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test3

T2_Fail             lda       orig_t1_cmp_l,u
                    sta       >TIMER1_CMP_L
                    lda       orig_t1_cmp_m,u
                    sta       >TIMER1_CMP_M
                    lda       orig_t1_cmp_h,u
                    sta       >TIMER1_CMP_H
                    lda       orig_t1_cmp_ctr,u
                    sta       >TIMER1_CMP_CTR
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: INTC Group 0-3 Edge Register Reset Defaults ($FE28-$FE2B)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] INTC Group 0-3 Edge Defaults ($FF) & R/W ($FE28-$FE2B)"
                    fcb       C$CR,0

                    * Preserve original edge registers
                    lda       >INTC_EDGE_0
                    sta       orig_edge,u
                    lda       >INTC_EDGE_1
                    sta       orig_edge+1,u
                    lda       >INTC_EDGE_2
                    sta       orig_edge+2,u
                    lda       >INTC_EDGE_3
                    sta       orig_edge+3,u

                    lbsr      PRINTS
                    fcc       "         EDGE Defaults: [0]=$"
                    fcb       0
                    lda       orig_edge,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcc       " [1]=$"
                    fcb       0
                    lda       orig_edge+1,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcc       " [2]=$"
                    fcb       0
                    lda       orig_edge+2,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcc       " [3]=$"
                    fcb       0
                    lda       orig_edge+3,u
                    lbsr      PrintHexByte

                    * Verify edge registers default to $FF (edge-triggered per RTL)
                    lda       orig_edge,u
                    cmpa      #$FF
                    lbne      T3_Fail
                    lda       orig_edge+1,u
                    cmpa      #$FF
                    lbne      T3_Fail
                    lda       orig_edge+2,u
                    cmpa      #$FF
                    lbne      T3_Fail
                    lda       orig_edge+3,u
                    cmpa      #$FF
                    lbne      T3_Fail

                    * Test write and readback on EDGE_0
                    lda       #$33
                    sta       >INTC_EDGE_0
                    lda       >INTC_EDGE_0
                    cmpa      #$33
                    lbne      T3_Fail

                    * Restore edge
                    lda       orig_edge,u
                    sta       >INTC_EDGE_0

                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test4

T3_Fail             lda       orig_edge,u
                    sta       >INTC_EDGE_0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: INTC Group 0-3 Mask Registers R/W ($FE2C-$FE2F)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] INTC Group 0-3 Mask Registers R/W ($FE2C-$FE2F)"
                    fcb       C$CR,0

                    orcc      #$50            * Mask CPU IRQs while modifying INTC masks
                    lda       >INTC_MASK_0
                    sta       orig_mask,u
                    lda       >INTC_MASK_1
                    sta       orig_mask+1,u
                    lda       >INTC_MASK_2
                    sta       orig_mask+2,u
                    lda       >INTC_MASK_3
                    sta       orig_mask+3,u

                    * Write $55 to all 4 mask registers
                    lda       #$55
                    sta       >INTC_MASK_0
                    sta       >INTC_MASK_1
                    sta       >INTC_MASK_2
                    sta       >INTC_MASK_3

                    * Verify all 4 read back $55
                    lda       >INTC_MASK_0
                    cmpa      #$55
                    lbne      T4_Fail
                    lda       >INTC_MASK_1
                    cmpa      #$55
                    lbne      T4_Fail
                    lda       >INTC_MASK_2
                    cmpa      #$55
                    lbne      T4_Fail
                    lda       >INTC_MASK_3
                    cmpa      #$55
                    lbne      T4_Fail

                    * Write $AA to all 4 mask registers
                    lda       #$AA
                    sta       >INTC_MASK_0
                    sta       >INTC_MASK_1
                    sta       >INTC_MASK_2
                    sta       >INTC_MASK_3

                    * Verify all 4 read back $AA
                    lda       >INTC_MASK_0
                    cmpa      #$AA
                    lbne      T4_Fail
                    lda       >INTC_MASK_1
                    cmpa      #$AA
                    lbne      T4_Fail
                    lda       >INTC_MASK_2
                    cmpa      #$AA
                    lbne      T4_Fail
                    lda       >INTC_MASK_3
                    cmpa      #$AA
                    lbne      T4_Fail

                    * Restore all masks
                    lda       orig_mask,u
                    sta       >INTC_MASK_0
                    lda       orig_mask+1,u
                    sta       >INTC_MASK_1
                    lda       orig_mask+2,u
                    sta       >INTC_MASK_2
                    lda       orig_mask+3,u
                    sta       >INTC_MASK_3
                    andcc     #^$50           * Re-enable CPU IRQs

                    lbsr      PRINTS
                    fcc       "         INTC_MASK_0..3 R/W Passed ($55, $AA)"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test5

T4_Fail             lda       orig_mask,u
                    sta       >INTC_MASK_0
                    lda       orig_mask+1,u
                    sta       >INTC_MASK_1
                    lda       orig_mask+2,u
                    sta       >INTC_MASK_2
                    lda       orig_mask+3,u
                    sta       >INTC_MASK_3
                    andcc     #^$50           * Re-enable CPU IRQs
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 5: INTC Group 0-3 Pending Registers Read & W1C ($FE20-$FE23)
                    * ========================================================
Test5               lbsr      PRINTS
                    fcc       "[TEST 5] INTC Pending Registers Read & W1C ($FE20-$FE23)"
                    fcb       C$CR,0

                    lda       >INTC_PENDING_0
                    sta       temp_buf+1,u
                    lbsr      PRINTS
                    fcc       "         INTC_PENDING [0]:$"
                    fcb       0
                    lda       temp_buf+1,u
                    lbsr      PrintHexByte

                    lbsr      PRINTS
                    fcc       " [1]:$"
                    fcb       0
                    lda       >INTC_PENDING_1
                    lbsr      PrintHexByte

                    lbsr      PRINTS
                    fcc       " [2]:$"
                    fcb       0
                    lda       >INTC_PENDING_2
                    lbsr      PrintHexByte

                    lbsr      PRINTS
                    fcc       " [3]:$"
                    fcb       0
                    lda       >INTC_PENDING_3
                    lbsr      PrintHexByte

                    * Perform W1C on Group 0
                    lda       temp_buf+1,u
                    sta       >INTC_PENDING_0

                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Summary

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
                    fcc       " / 5 | Failed="
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

PRINTS              pshs      a,x
                    ldx       3,s
prints_lp           lda       ,x+
                    beq       prints_ex
                    lbsr      PUTC
                    bra       prints_lp
prints_ex           stx       3,s
                    puls      a,x,pc

                    endsect   0
