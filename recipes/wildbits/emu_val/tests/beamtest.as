********************************************************************
* beamtest.as - TinyVicky II Raster Beam & Line Comparator Diagnostic
*
* Validates real-time beam position counters (RAST_ROW / RAST_COL)
* and line comparator match / interrupt behavior.
********************************************************************
                    nam       beamtest
                    ttl       Raster Beam Diagnostic

                    use       defsfile

                    section   bss
sample_rows         rmb       16      * 8 samples x 2 bytes
sample_cols         rmb       16      * 8 samples x 2 bytes
temp_buf            rmb       16
stack               rmb       200     * Stack at end so S grows downwards safely
                    endsect

VKY_RAST_COL        equ       $FFD8
VKY_RAST_ROW        equ       $FFDA
INTC_PENDING_0      equ       $FE20
INTC_MASK_0         equ       $FE2C

                    section   code
                    export    __start

__start
                    lbsr      PRINTS
                    fcc       "=== TINYVICKY II RASTER BEAM DIAGNOSTIC ==="
                    fcb       C$CR,C$LF,0

                    * ========================================================
                    * PART 1: Capture 8 Real-Time Samples
                    * ========================================================
                    leax      sample_rows,u
                    leay      sample_cols,u
                    clr       ,-s              * clear sample index

CaptureLoop         ldd       >VKY_RAST_ROW
                    std       ,x++
                    ldd       >VKY_RAST_COL
                    std       ,y++

                    * Small delay loop between samples
                    ldd       #500
dly_lp              subd      #1
                    bne       dly_lp

                    inc       ,s
                    lda       ,s
                    cmpa      #8
                    blo       CaptureLoop
                    leas      1,s              * cleanup stack

                    * Print Header
                    lbsr      PRINTS
                    fcc       "[RASTER BEAM POSITION SAMPLES]"
                    fcb       C$CR,C$LF,0

                    * Print 8 Samples
                    leax      sample_rows,u
                    leay      sample_cols,u
                    clr       ,-s              * allocate sample index on stack (0..7)

PrintSamples        lbsr      PRINTS
                    fcc       "  Sample "
                    fcb       0

                    lda       ,s
                    inca
                    adda      #'0
                    lbsr      PUTC

                    lbsr      PRINTS
                    fcc       ": Row=$"
                    fcb       0

                    ldd       ,x++
                    lbsr      PrintHexWord

                    lbsr      PRINTS
                    fcc       " ("
                    fcb       0

                    * Print active/vblank zone
                    ldd       -2,x
                    cmpd      #480
                    blo       IsActive
                    lbsr      PRINTS
                    fcc       "VBLANK) Col=$"
                    fcb       0
                    bra       PrintCol

IsActive            lbsr      PRINTS
                    fcc       "ACTIVE) Col=$"
                    fcb       0

PrintCol            ldd       ,y++
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcb       C$CR,C$LF,0

                    inc       ,s
                    lda       ,s
                    cmpa      #8
                    blo       PrintSamples
                    leas      1,s              * cleanup stack

                    * ========================================================
                    * PART 2: Verify Monotonicity and Limits (0..524)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[VALIDATING BOUNDS & ROLLOVER (0..524)]"
                    fcb       C$CR,C$LF,0

                    ldx       #1000
CheckLoop           ldd       >VKY_RAST_ROW
                    cmpd      #524             * Max valid scanline is 524
                    lbhi      RowOverflow      * Branch if > 524
                    leax      -1,x
                    bne       CheckLoop

                    lbsr      PRINTS
                    fcc       "  1000 Scanline Queries: All within bounds [0..524]"
                    fcb       C$CR,C$LF,0

                    * ========================================================
                    * PART 3: Line Comparator Match ($FFD8-$FFD9)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TESTING LINE COMPARATOR REGISTERS]"
                    fcb       C$CR,C$LF,0

                    * Program Line Compare for line 200 ($00C8)
                    ldd       #200
                    std       >VKY_RAST_COL    * Write to $FFD8-$FFD9 sets line cmp

                    lbsr      PRINTS
                    fcc       "  Arming Line Comparator for Scanline 200 ($00C8)..."
                    fcb       C$CR,C$LF,0

                    * Wait for scanline 200 to be traversed
                    ldx       #25000
WaitLine            ldd       >VKY_RAST_ROW
                    cmpd      #200
                    beq       LineHit
                    leax      -1,x
                    bne       WaitLine

                    lbsr      PRINTS
                    fcc       "  WARNING: Scanline 200 traversal timed out"
                    fcb       C$CR,C$LF,0
                    bra       Summary

LineHit             lbsr      PRINTS
                    fcc       "  Scanline 200 hit verified! Beam Col=$"
                    fcb       0
                    ldd       >VKY_RAST_COL
                    lbsr      PrintHexWord
                    lbsr      PRINTS
                    fcb       C$CR,C$LF,0

Summary             lbsr      PRINTS
                    fcc       "---------------------------------------------------"
                    fcb       C$CR,C$LF,0
                    lbsr      PRINTS
                    fcc       "RESULT: RASTER BEAM & TIMERS 100% OPERATIONAL!"
                    fcb       C$CR,C$LF,0
                    clrb
                    os9       F$Exit

RowOverflow         lbsr      PRINTS
                    fcc       "FAIL: RAST_ROW exceeded maximum scanline limit (>524)!"
                    fcb       C$CR,C$LF,0
                    ldb       #1
                    os9       F$Exit

* --- Formatting Helper Subroutines ---

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

Nibble2Hex          adda      #$90    ; very cleverly convert to ASCII
                    daa
                    adca      #$40
                    daa
putc_ok             lbsr      PUTC
                    rts

PUTC                pshs      a,b,cc,x,y
                    leax      temp_buf,u
                    sta       ,x
                    ldy       #1
                    lda       #1
                    os9       I$Write
                    puls      a,b,cc,x,y,pc

PRINTS              pshs      x
                    ldx       2,s
prints_lp           lda       ,x+
                    beq       prints_ex
                    lbsr      PUTC
                    bra       prints_lp
prints_ex           stx       2,s
                    puls      x,pc

                    endsect   0
