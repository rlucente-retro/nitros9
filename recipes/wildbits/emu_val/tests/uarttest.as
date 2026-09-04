********************************************************************
* uarttest.as - Wildbits Jr2 16550 UART Serial Diagnostic Suite
*
* Validates 16550 UART registers ($FE60-$FE67), Scratchpad (SCR)
* bit walking patterns, DLAB divisor latch switching, IER interrupt
* mask access, and LSR transmitter status.
********************************************************************
                    nam       uarttest
                    ttl       16550 UART Serial Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
orig_lcr            rmb       1
orig_ier            rmb       1
orig_scr            rmb       1
lsr_val             rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions ($FE60 - $FE67)
UART_RBR            equ       $FE60   * DLAB=0: Rx Buffer (R) / Tx Holding (W)
UART_DLL            equ       $FE60   * DLAB=1: Divisor Latch Low
UART_IER            equ       $FE61   * DLAB=0: Interrupt Enable
UART_DLH            equ       $FE61   * DLAB=1: Divisor Latch High
UART_IIR            equ       $FE62   * Interrupt ID (R) / FIFO Control (W)
UART_LCR            equ       $FE63   * Line Control Register
UART_MCR            equ       $FE64   * Modem Control Register
UART_LSR            equ       $FE65   * Line Status Register
UART_MSR            equ       $FE66   * Modem Status Register
UART_SCR            equ       $FE67   * Scratchpad Register

INTC_PENDING_1      equ       $FE21   * INTC Group 1 Pending Register

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 16550 UART SERIAL DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: Scratch Register Bit Walking Pattern ($FE67)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Scratchpad (SCR) Walking Bit Pattern ($FE67)"
                    fcb       C$CR,0

                    lda       >UART_SCR
                    sta       orig_scr,u

                    * Pattern 1: $55
                    lda       #$55
                    sta       >UART_SCR
                    lda       >UART_SCR
                    cmpa      #$55
                    bne       T1_Fail

                    * Pattern 2: $AA
                    lda       #$AA
                    sta       >UART_SCR
                    lda       >UART_SCR
                    cmpa      #$AA
                    bne       T1_Fail

                    * Pattern 3: $00
                    lda       #$00
                    sta       >UART_SCR
                    lda       >UART_SCR
                    cmpa      #$00
                    bne       T1_Fail

                    * Pattern 4: $FF
                    lda       #$FF
                    sta       >UART_SCR
                    lda       >UART_SCR
                    cmpa      #$FF
                    bne       T1_Fail

                    * Restore SCR
                    lda       orig_scr,u
                    sta       >UART_SCR

                    lbsr      PRINTS
                    fcc       "         SCR Passed ($55, $AA, $00, $FF)"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lda       orig_scr,u
                    sta       >UART_SCR
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: DLAB Divisor Latch Switching ($FE63 bit 7)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] DLAB Divisor Latch Switching (DLL/DLH vs RBR/IER)"
                    fcb       C$CR,0

                    lda       >UART_LCR
                    sta       orig_lcr,u

                    * Set DLAB = 1
                    ora       #$80
                    sta       >UART_LCR

                    * Write test divisor $000C (9600 baud base)
                    lda       #$0C
                    sta       >UART_DLL
                    lda       #$00
                    sta       >UART_DLH

                    * Read back DLL/DLH
                    lda       >UART_DLL
                    cmpa      #$0C
                    bne       T2_Fail
                    lda       >UART_DLH
                    cmpa      #$00
                    bne       T2_Fail

                    * Clear DLAB = 0
                    lda       orig_lcr,u
                    anda      #$7F
                    sta       >UART_LCR

                    * Restore standard 230,400 baud divisor 5: DLL=5, DLH=0
                    lda       orig_lcr,u
                    ora       #$80
                    sta       >UART_LCR
                    lda       #5
                    sta       >UART_DLL
                    lda       #0
                    sta       >UART_DLH
                    lda       orig_lcr,u
                    sta       >UART_LCR

                    lbsr      PRINTS
                    fcc       "         DLAB Switching & Divisor Latch Readback"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lda       orig_lcr,u
                    sta       >UART_LCR
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: Interrupt Enable Register Masking ($FE61)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] Interrupt Enable Register Masking ($FE61)"
                    fcb       C$CR,0

                    lda       >UART_IER
                    sta       orig_ier,u

                    * Test write $01 (ERBFI: Enable Received Data Interrupt)
                    lda       #$01
                    sta       >UART_IER
                    lda       >UART_IER
                    cmpa      #$01
                    bne       T3_Fail

                    * Test write $00
                    lda       #$00
                    sta       >UART_IER
                    lda       >UART_IER
                    cmpa      #$00
                    bne       T3_Fail

                    * Restore IER
                    lda       orig_ier,u
                    sta       >UART_IER

                    lbsr      PRINTS
                    fcc       "         IER R/W Masking Passed"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test4

T3_Fail             lda       orig_ier,u
                    sta       >UART_IER
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: Line Status Register Idle State ($FE65)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] Line Status Register Idle State ($FE65)"
                    fcb       C$CR,0

                    lda       >UART_LSR
                    sta       lsr_val,u
                    lbsr      PRINTS
                    fcc       "         LSR Readback: $"
                    fcb       0
                    lda       lsr_val,u
                    lbsr      PrintHexByte

                    * Check if THRE (bit 5) and TEMT (bit 6) are set ($60)
                    lda       lsr_val,u
                    bita      #$60
                    beq       T4_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test5

T4_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 5: INTC Group 1 UART Interrupt Line ($FE21)
                    * ========================================================
Test5               lbsr      PRINTS
                    fcc       "[TEST 5] INTC Group 1 UART Line Status ($FE21)"
                    fcb       C$CR,0

                    * In idle state without incoming bytes, INT_UART (bit 0) is 0
                    lda       >INTC_PENDING_1
                    lbsr      PRINTS
                    fcc       "         INTC_PENDING_1: $"
                    fcb       0
                    lbsr      PrintHexByte

                    * W1C test: write bit 0 to clear any pending UART event
                    lda       #$01
                    sta       >INTC_PENDING_1
                    lda       >INTC_PENDING_1
                    bita      #$01
                    bne       T5_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Summary

T5_Fail             lbsr      PrintFail
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
                    fcc       "RESULT: ALL UART TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: 16550 UART HARDWARE MISMATCH DETECTED!"
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
