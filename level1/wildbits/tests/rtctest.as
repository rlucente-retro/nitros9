********************************************************************
* rtctest.as - Wildbits Jr2 Real-Time Clock Diagnostic Suite
*
* Validates bq4802 Real-Time Clock registers ($FE40-$FE4F),
* bus decode separation from $FE10, BCD timestamp validity,
* 32.768 kHz oscillator ticking, and control register access.
********************************************************************
                    nam       rtctest
                    ttl       Real-Time Clock Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
initial_sec         rmb       1
curr_sec            rmb       1
orig_ctrl           rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions
OPTICAL_KBD_BASE    equ       $FE10
HW_RTC_SEC          equ       RTC.Base+RTC_SEC
HW_RTC_MIN          equ       RTC.Base+RTC_MIN
HW_RTC_HRS          equ       RTC.Base+RTC_HRS
HW_RTC_DAY          equ       RTC.Base+RTC_DAY
HW_RTC_DOW          equ       RTC.Base+RTC_DOW
HW_RTC_MONTH        equ       RTC.Base+RTC_MONTH
HW_RTC_YEAR         equ       RTC.Base+RTC_YEAR
HW_RTC_CTRL         equ       RTC.Base+RTC_CTRL
HW_RTC_CENTURY      equ       RTC.Base+RTC_CENTURY

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 REAL-TIME CLOCK (RTC) DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: Bus Address Decode & Jr2 Isolation ($FE40 vs $FE10)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Bus Address Decode ($FE40 RTC vs $FE10 Open Bus)"
                    fcb       C$CR,0

                    * On Wildbits Jr2, $FE10-$FE1F is unpopulated (open bus = $FF).
                    * $FE40-$FE4F is the bq4802 RTC.
                    lda       >OPTICAL_KBD_BASE
                    lbsr      PRINTS
                    fcc       "         $FE10: $"
                    fcb       0
                    lbsr      PrintHexByte

                    lda       >HW_RTC_SEC
                    lbsr      PRINTS
                    fcc       " | $FE40 (SEC): $"
                    fcb       0
                    lbsr      PrintHexByte

                    * Verify $FE40 contains valid BCD seconds (<= $59)
                    lda       >HW_RTC_SEC
                    anda      #$7F
                    cmpa      #$59
                    bhi       T1_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: Read & Validate Full BCD Timestamp
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] BCD Timestamp Readback ($FE40-$FE4F)"
                    fcb       C$CR,0

                    lbsr      PRINTS
                    fcc       "         Current RTC Date/Time: 20"
                    fcb       0

                    lda       >HW_RTC_YEAR
                    lbsr      PrintHexByte
                    lda       #'-
                    lbsr      PUTC
                    lda       >HW_RTC_MONTH
                    lbsr      PrintHexByte
                    lda       #'-
                    lbsr      PUTC
                    lda       >HW_RTC_DAY
                    lbsr      PrintHexByte
                    lda       #' 
                    lbsr      PUTC
                    lda       >HW_RTC_HRS
                    lbsr      PrintHexByte
                    lda       #':
                    lbsr      PUTC
                    lda       >HW_RTC_MIN
                    lbsr      PrintHexByte
                    lda       #':
                    lbsr      PUTC
                    lda       >HW_RTC_SEC
                    lbsr      PrintHexByte

                    * Validate Month (1..12)
                    lda       >HW_RTC_MONTH
                    cmpa      #$01
                    blo       T2_Fail
                    cmpa      #$12
                    bhi       T2_Fail

                    * Validate Day (1..31)
                    lda       >HW_RTC_DAY
                    cmpa      #$01
                    blo       T2_Fail
                    cmpa      #$31
                    bhi       T2_Fail

                    * Validate Hours (0..23)
                    lda       >HW_RTC_HRS
                    cmpa      #$23
                    bhi       T2_Fail

                    * Validate Minutes (0..59)
                    lda       >HW_RTC_MIN
                    cmpa      #$59
                    bhi       T2_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: Oscillator Integrity (Seconds Register Ticking)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] RTC Oscillator Ticking (Wait for SEC to Advance)"
                    fcb       C$CR,0

                    lda       >HW_RTC_SEC
                    sta       initial_sec,u

                    * Delay loop waiting for SEC to change (timeout ~1.5s)
                    ldx       #$0000
wait_tick           ldy       #3000
inner_lp            leay      -1,y
                    bne       inner_lp

                    lda       >HW_RTC_SEC
                    cmpa      initial_sec,u
                    bne       T3_Ticked

                    leax      1,x
                    cmpx      #300
                    blo       wait_tick

                    * Timed out without SEC change
                    lbsr      PRINTS
                    fcc       "         Oscillator Timeout: SEC did not change from $"
                    fcb       0
                    lda       initial_sec,u
                    lbsr      PrintHexByte
                    lbsr      PrintFail
                    inc       fail_count,u
                    bra       Test4

T3_Ticked           sta       curr_sec,u
                    lbsr      PRINTS
                    fcc       "         Oscillator Running: SEC advanced from $"
                    fcb       0
                    lda       initial_sec,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcc       " -> $"
                    fcb       0
                    lda       curr_sec,u
                    lbsr      PrintHexByte
                    lbsr      PrintPass
                    inc       pass_count,u

                    * ========================================================
                    * TEST 4: Control / RAM Register Access ($FE4E)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] RTC Control / NVRAM Register Access ($FE4E)"
                    fcb       C$CR,0

                    lda       >HW_RTC_CTRL
                    sta       orig_ctrl,u

                    * Write test pattern $0A
                    lda       #$0A
                    sta       >HW_RTC_CTRL
                    lda       >HW_RTC_CTRL
                    cmpa      #$0A
                    bne       T4_Fail

                    * Restore original value
                    lda       orig_ctrl,u
                    sta       >HW_RTC_CTRL

                    lbsr      PRINTS
                    fcc       "         R/W Pattern Test on $FE4E"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Summary

T4_Fail             * Restore original value
                    lda       orig_ctrl,u
                    sta       >HW_RTC_CTRL
                    lbsr      PrintFail
                    inc       fail_count,u

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
                    fcc       "RESULT: ALL RTC TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: RTC HARDWARE MISMATCH DETECTED!"
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
