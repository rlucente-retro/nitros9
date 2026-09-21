********************************************************************
* cursortest.as - TinyVicky II Master Video & Text Cursor Diagnostic
*
* Validates TinyVicky II Master Control registers ($FFC0-$FFC1) and
* Hardware Text Cursor registers ($FFD0-$FFD7) with complete register
* preservation across tests.
********************************************************************
                    nam       cursortest
                    ttl       TinyVicky Video & Cursor Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
orig_mstr0          rmb       1
orig_mstr1          rmb       1
orig_crsr_ctrl      rmb       1
orig_crsr_char      rmb       1
orig_crsr_colr      rmb       1
orig_crsr_x         rmb       2
orig_crsr_y         rmb       2
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions ($FFC0 - $FFDF)
VKY_MSTR_CTRL_0     equ       $FFC0
VKY_MSTR_CTRL_1     equ       $FFC1
VKY_CRSR_CTRL       equ       $FFD0
VKY_CRSR_CHAR       equ       $FFD2
VKY_CRSR_COLR       equ       $FFD3
VKY_CRSR_X_H        equ       $FFD4
VKY_CRSR_X_L        equ       $FFD5
VKY_CRSR_Y_H        equ       $FFD6
VKY_CRSR_Y_L        equ       $FFD7

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== TINYVICKY II VIDEO & CURSOR DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: TinyVicky Master Video Controls ($FFC0-$FFC1)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Video Master Control Registers ($FFC0-$FFC1)"
                    fcb       C$CR,0

                    lda       >VKY_MSTR_CTRL_0
                    sta       orig_mstr0,u
                    lda       >VKY_MSTR_CTRL_1
                    sta       orig_mstr1,u

                    lbsr      PRINTS
                    fcc       "         MSTR_CTRL_0: $"
                    fcb       0
                    lda       orig_mstr0,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcc       " | MSTR_CTRL_1: $"
                    fcb       0
                    lda       orig_mstr1,u
                    lbsr      PrintHexByte

                    * Verify Text Mode Enable (bit 0 of MSTR_CTRL_0 must be set)
                    lda       orig_mstr0,u
                    bita      #$01
                    lbeq      T1_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test2

T1_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: Hardware Cursor Control Register ($FFD0)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] Hardware Cursor Control Register ($FFD0)"
                    fcb       C$CR,0

                    lda       >VKY_CRSR_CTRL
                    sta       orig_crsr_ctrl,u

                    * Write test pattern $05 (Enable=1, Line Mode=1)
                    lda       #$05
                    sta       >VKY_CRSR_CTRL
                    lda       >VKY_CRSR_CTRL
                    cmpa      #$05
                    lbne      T2_Fail

                    * Write test pattern $00 (Disabled)
                    lda       #$00
                    sta       >VKY_CRSR_CTRL
                    lda       >VKY_CRSR_CTRL
                    cmpa      #$00
                    lbne      T2_Fail

                    * Restore original cursor control
                    lda       orig_crsr_ctrl,u
                    sta       >VKY_CRSR_CTRL

                    lbsr      PRINTS
                    fcc       "         Cursor Control Register R/W Verified"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test3

T2_Fail             lda       orig_crsr_ctrl,u
                    sta       >VKY_CRSR_CTRL
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: Hardware Cursor Position Registers ($FFD4-$FFD7)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] Hardware Cursor Position (X/Y: $FFD4-$FFD7)"
                    fcb       C$CR,0

                    * Preserve existing cursor coordinates
                    ldd       >VKY_CRSR_X_H
                    std       orig_crsr_x,u
                    ldd       >VKY_CRSR_Y_H
                    std       orig_crsr_y,u

                    lbsr      PRINTS
                    fcc       "         Original Cursor Pos: (X=$"
                    fcb       0
                    ldd       orig_crsr_x,u
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcc       ", Y=$"
                    fcb       0
                    ldd       orig_crsr_y,u
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcc       ")"
                    fcb       0

                    * Write test coordinates: X = $0028 (40), Y = $000F (15)
                    ldd       #$0028
                    std       >VKY_CRSR_X_H
                    ldd       #$000F
                    std       >VKY_CRSR_Y_H

                    * Verify readback
                    ldd       >VKY_CRSR_X_H
                    cmpd      #$0028
                    lbne      T3_Fail
                    ldd       >VKY_CRSR_Y_H
                    cmpd      #$000F
                    lbne      T3_Fail

                    * Restore original coordinates
                    ldd       orig_crsr_x,u
                    std       >VKY_CRSR_X_H
                    ldd       orig_crsr_y,u
                    std       >VKY_CRSR_Y_H

                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Test4

T3_Fail             ldd       orig_crsr_x,u
                    std       >VKY_CRSR_X_H
                    ldd       orig_crsr_y,u
                    std       >VKY_CRSR_Y_H
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: Hardware Cursor Glyph & Color ($FFD2-$FFD3)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] Cursor Glyph & Color Registers ($FFD2-$FFD3)"
                    fcb       C$CR,0

                    lda       >VKY_CRSR_CHAR
                    sta       orig_crsr_char,u
                    lda       >VKY_CRSR_COLR
                    sta       orig_crsr_colr,u

                    * Write test character $5F ('_') and color $F0
                    lda       #$5F
                    sta       >VKY_CRSR_CHAR
                    lda       #$F0
                    sta       >VKY_CRSR_COLR

                    * Verify readback
                    lda       >VKY_CRSR_CHAR
                    cmpa      #$5F
                    lbne      T4_Fail
                    lda       >VKY_CRSR_COLR
                    cmpa      #$F0
                    lbne      T4_Fail

                    * Restore original glyph and color
                    lda       orig_crsr_char,u
                    sta       >VKY_CRSR_CHAR
                    lda       orig_crsr_colr,u
                    sta       >VKY_CRSR_COLR

                    lbsr      PRINTS
                    fcc       "         Cursor Character & Attribute Verified"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Summary

T4_Fail             lda       orig_crsr_char,u
                    sta       >VKY_CRSR_CHAR
                    lda       orig_crsr_colr,u
                    sta       >VKY_CRSR_COLR
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
                    fcc       "RESULT: ALL VIDEO & CURSOR TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: TINYVICKY VIDEO/CURSOR MISMATCH DETECTED!"
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

PrintHexWord        pshs      b
                    bsr       PrintHexByte
                    puls      a

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
