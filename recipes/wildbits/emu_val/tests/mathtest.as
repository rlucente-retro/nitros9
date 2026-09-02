********************************************************************
* mathtest.as - Wildbits Jr2 Math Coprocessor Diagnostic Suite
*
* Validates 16x16 unsigned multiplication, 16/16 unsigned division,
* remainder, divide-by-zero saturation, and 32-bit addition.
********************************************************************
                    nam       mathtest
                    ttl       Math Coprocessor Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions ($FEE0 - $FEFB)
MATH_MULU_A         equ       $FEE0   * Operand A (16-bit unsigned)
MATH_MULU_B         equ       $FEE2   * Operand B (16-bit unsigned)
MATH_DIVU_DEN       equ       $FEE4   * Denominator (16-bit unsigned)
MATH_DIVU_NUM       equ       $FEE6   * Numerator (16-bit unsigned)
MATH_ADD_A          equ       $FEE8   * Addend A (32-bit unsigned)
MATH_ADD_B          equ       $FEEC   * Addend B (32-bit unsigned)

MATH_MULU_RES       equ       $FEF0   * 32-bit Product ($FEF0=HH/HL, $FEF2=LH/LL)
MATH_QUOU_RES       equ       $FEF4   * 16-bit Quotient
MATH_REMU_RES       equ       $FEF6   * 16-bit Remainder
MATH_ADD_RES        equ       $FEF8   * 32-bit Sum

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 MATH COPROCESSOR DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: MULU Small Values (100 * 200 = 20000 -> $4E20)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] MULU: $0064 * $00C8 (100 * 200)"
                    fcb       C$CR,0

                    ldd       #100
                    std       >MATH_MULU_A
                    ldd       #200
                    std       >MATH_MULU_B

                    lbsr      PRINTS
                    fcc       "         EXP: $00004E20 | GOT: $"
                    fcb       0

                    ldd       >MATH_MULU_RES
                    lbsr      PrintHexWord
                    ldd       >MATH_MULU_RES+2
                    lbsr      PrintHexWord

                    ldd       >MATH_MULU_RES
                    cmpd      #$0000
                    bne       T1_Fail
                    ldd       >MATH_MULU_RES+2
                    cmpd      #$4E20
                    bne       T1_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: MULU Max Values ($FFFF * $FFFF = $FFFE0001)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] MULU: $FFFF * $FFFF (65535 * 65535)"
                    fcb       C$CR,0

                    ldd       #$FFFF
                    std       >MATH_MULU_A
                    std       >MATH_MULU_B

                    lbsr      PRINTS
                    fcc       "         EXP: $FFFE0001 | GOT: $"
                    fcb       0

                    ldd       >MATH_MULU_RES
                    lbsr      PrintHexWord
                    ldd       >MATH_MULU_RES+2
                    lbsr      PrintHexWord

                    ldd       >MATH_MULU_RES
                    cmpd      #$FFFE
                    bne       T2_Fail
                    ldd       >MATH_MULU_RES+2
                    cmpd      #$0001
                    bne       T2_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: DIVU Standard Division (1005 / 10 = Q:100, R:5)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] DIVU: $03ED / $000A (1005 / 10)"
                    fcb       C$CR,0

                    ldd       #10
                    std       >MATH_DIVU_DEN
                    ldd       #1005
                    std       >MATH_DIVU_NUM

                    lbsr      PRINTS
                    fcc       "         EXP: Q=$0064 R=$0005 | GOT: Q=$"
                    fcb       0

                    ldd       >MATH_QUOU_RES
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcc       " R=$"
                    fcb       0
                    ldd       >MATH_REMU_RES
                    lbsr      PrintHexWord

                    ldd       >MATH_QUOU_RES
                    cmpd      #100
                    bne       T3_Fail
                    ldd       >MATH_REMU_RES
                    cmpd      #5
                    bne       T3_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test4

T3_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: DIVU Divide-by-Zero Protection (1234 / 0)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] DIVU: $04D2 / $0000 (1234 / 0 - DivZero Guard)"
                    fcb       C$CR,0

                    ldd       #0
                    std       >MATH_DIVU_DEN
                    ldd       #1234
                    std       >MATH_DIVU_NUM

                    lbsr      PRINTS
                    fcc       "         EXP: Q=$FFFF R=$04D2 | GOT: Q=$"
                    fcb       0

                    ldd       >MATH_QUOU_RES
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcc       " R=$"
                    fcb       0
                    ldd       >MATH_REMU_RES
                    lbsr      PrintHexWord

                    ldd       >MATH_QUOU_RES
                    cmpd      #$FFFF
                    bne       T4_Fail
                    ldd       >MATH_REMU_RES
                    cmpd      #1234
                    bne       T4_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test5

T4_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 5: 32-bit Addition Carry ($0000FFFF + $00000001)
                    * ========================================================
Test5               lbsr      PRINTS
                    fcc       "[TEST 5] ADD : $0000FFFF + $00000001 (32-bit Carry)"
                    fcb       C$CR,0

                    ldd       #0
                    std       >MATH_ADD_A
                    ldd       #$FFFF
                    std       >MATH_ADD_A+2
                    ldd       #0
                    std       >MATH_ADD_B
                    ldd       #$0001
                    std       >MATH_ADD_B+2

                    lbsr      PRINTS
                    fcc       "         EXP: $00010000 | GOT: $"
                    fcb       0

                    ldd       >MATH_ADD_RES
                    lbsr      PrintHexWord
                    ldd       >MATH_ADD_RES+2
                    lbsr      PrintHexWord

                    ldd       >MATH_ADD_RES
                    cmpd      #$0001
                    bne       T5_Fail
                    ldd       >MATH_ADD_RES+2
                    cmpd      #$0000
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
                    fcc       "RESULT: ALL MATH TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: MATH COPROCESSOR HARDWARE MISMATCH DETECTED!"
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

* Print 16-bit word in D as 4 hex ASCII characters
PrintHexWord        pshs      b
                    bsr       PrintHexByte
                    puls      a

* Print 8-bit byte in A as 2 hex ASCII characters
PrintHexByte        pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nibble2Hex
                    puls      a
                    anda      #$0f

Nibble2Hex          adda      #$90    ; very cleverly convert to ASCII
                    daa
                    adca      #$40
                    daa
putc_ok             lbsr      PUTC
                    rts

* Single character write via os9 I$Write (preserving all registers)
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

* Inline string print (100% register preserving)
PRINTS              pshs      x
                    ldx       2,s
prints_lp           lda       ,x+
                    beq       prints_ex
                    lbsr      PUTC
                    bra       prints_lp
prints_ex           stx       2,s
                    puls      x,pc

                    endsect   0
