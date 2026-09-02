********************************************************************
* diptest.as - Wildbits Jr2 Machine ID & DIP Switch Diagnostic Suite
*
* Validates Machine ID register ($FE07 = $1A), system control registers
* ($FE00-$FE01), and motherboard hardware DIP switches ($FF90).
********************************************************************
                    nam       diptest
                    ttl       Machine ID & DIP Switch Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
mid_val             rmb       1
dip_val             rmb       1
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions
REG_SYS0            equ       $FE00
REG_SYS1            equ       $FE01
REG_MID             equ       $FE07
REG_DIPSW           equ       $FF90

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 MACHINE ID & DIP SWITCH DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: Machine ID Register ($FE07 == $1A)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Machine ID Verification ($FE07)"
                    fcb       C$CR,0

                    lda       >REG_MID
                    sta       mid_val,u
                    lbsr      PRINTS
                    fcc       "         EXP: $1A (Jr2 6809) | GOT: $"
                    fcb       0
                    lda       mid_val,u
                    lbsr      PrintHexByte

                    lda       mid_val,u
                    cmpa      #$1A
                    bne       T1_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: Motherboard System Registers ($FE00, $FE01)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] System Control Registers ($FE00 SYS0, $FE01 SYS1)"
                    fcb       C$CR,0

                    lbsr      PRINTS
                    fcc       "         SYS0: $"
                    fcb       0
                    lda       >REG_SYS0
                    lbsr      PrintHexByte

                    lbsr      PRINTS
                    fcc       " | SYS1: $"
                    fcb       0
                    lda       >REG_SYS1
                    lbsr      PrintHexByte

                    lbsr      PrintPass
                    inc       pass_count,u

                    * ========================================================
                    * TEST 3: Hardware Configuration DIP Switches ($FF90)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] Motherboard DIP Switches Decode ($FF90)"
                    fcb       C$CR,0

                    lda       >REG_DIPSW
                    sta       dip_val,u

                    lbsr      PRINTS
                    fcc       "         Raw DIP Register Value: $"
                    fcb       0
                    lda       dip_val,u
                    lbsr      PrintHexByte
                    lbsr      PRINTS
                    fcb       C$CR,0

                    * Decode Bit 7: Gamma Correction
                    lbsr      PRINTS
                    fcc       "         - Bit 7 [Gamma]: "
                    fcb       0
                    lda       dip_val,u
                    bita      #$80
                    bne       gamma_on
                    lbsr      PRINTS
                    fcc       "Disabled (Off)"
                    fcb       C$CR,0
                    bra       chk_turbo
gamma_on            lbsr      PRINTS
                    fcc       "Enabled (On)"
                    fcb       C$CR,0

chk_turbo           * Decode Bit 6: Turbo Stretch Mode (~1.4x)
                    lbsr      PRINTS
                    fcc       "         - Bit 6 [Turbo]: "
                    fcb       0
                    lda       dip_val,u
                    bita      #$40
                    bne       turbo_on
                    lbsr      PRINTS
                    fcc       "Standard 6.29 MHz (Off)"
                    fcb       C$CR,0
                    bra       chk_user
turbo_on            lbsr      PRINTS
                    fcc       "Turbo ~8.8 MHz (On)"
                    fcb       C$CR,0

chk_user            * Decode Bits 5..4: User DIP Switches
                    lbsr      PRINTS
                    fcc       "         - Bits 5:4 [User DIPs]: %"
                    fcb       0
                    lda       dip_val,u
                    lsra
                    lsra
                    lsra
                    lsra
                    anda      #$03
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcb       C$CR,0

                    * Decode Bits 3..0: Boot Mode
                    lbsr      PRINTS
                    fcc       "         - Bits 3:0 [Boot Mode]: $"
                    fcb       0
                    lda       dip_val,u
                    anda      #$0F
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PrintPass
                    inc       pass_count,u

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
                    fcc       " / 3 | Failed="
                    fcb       0
                    lda       fail_count,u
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcb       C$CR,0

                    tst       fail_count,u
                    bne       ExitErr

                    lbsr      PRINTS
                    fcc       "RESULT: ALL DIP/ID TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: HARDWARE ID/DIP MISMATCH DETECTED!"
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
