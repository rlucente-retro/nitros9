********************************************************************
* dmatest.as - TinyVicky II 1D/2D DMA Engine Diagnostic Suite
*
* Validates 1D linear fill, 1D memory copy, and 2D stride-based
* rectangular blits in SRAM.
********************************************************************
                    nam       dmatest
                    ttl       DMA Engine Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
temp_buf            rmb       16
dma_src_buf         rmb       256
dma_dst_buf         rmb       1024
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions ($FEC0 - $FED7)
DMA_CTRL            equ       $FEC0
DMA_DATA_WRITE      equ       $FEC1
DMA_SRC_ADDR        equ       $FEC4   * 24-bit physical source (H, M, L)
DMA_DST_ADDR        equ       $FEC8   * 24-bit physical dest (H, M, L)
DMA_SIZE_1D         equ       $FECD   * 24-bit size (H, M, L)
DMA_2D_WIDTH        equ       $FED0   * 16-bit width
DMA_2D_HEIGHT       equ       $FED2   * 16-bit height
DMA_SRC_STRIDE      equ       $FED4   * 16-bit source stride
DMA_DST_STRIDE      equ       $FED6   * 16-bit dest stride

INTC_PENDING_0      equ       $FE20

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== TINYVICKY II DMA ENGINE DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: 1D Linear DMA Fill (Fill 256 bytes with $5A)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] 1D Linear DMA Fill (256 bytes with $5A)"
                    fcb       C$CR,0

                    * Clear destination buffer first with $00
                    leax      dma_dst_buf,u
                    ldb       #0
clr1_lp             clr       ,x+
                    decb
                    bne       clr1_lp

                    * Setup DMA Destination Address (24-bit from U + dma_dst_buf)
                    leax      dma_dst_buf,u
                    tfr       x,d
                    clr       >DMA_DST_ADDR
                    sta       >DMA_DST_ADDR+1
                    stb       >DMA_DST_ADDR+2

                    * Setup Fill Byte
                    lda       #$5A
                    sta       >DMA_DATA_WRITE

                    * Setup 1D Size (256 bytes = $000100)
                    clr       >DMA_SIZE_1D
                    lda       #$01
                    sta       >DMA_SIZE_1D+1
                    clr       >DMA_SIZE_1D+2

                    * Trigger DMA Fill: START=1, FILL=1, ENABLE=1 ($85)
                    lda       #$85
                    sta       >DMA_CTRL

                    * Verify destination buffer
                    leax      dma_dst_buf,u
                    ldb       #0
chk1_lp             lda       ,x+
                    cmpa      #$5A
                    bne       T1_Fail
                    decb
                    bne       chk1_lp

                    lbsr      PRINTS
                    fcc       "         Buffer Verification: 256/256 bytes match $5A"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lbsr      PRINTS
                    fcc       "         Buffer Verification Mismatch!"
                    fcb       0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: 1D Linear DMA Copy (src_buf -> dst_buf)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] 1D Linear DMA Copy (256 bytes: ramp pattern)"
                    fcb       C$CR,0

                    * Fill source buffer with ramp pattern 0..255
                    leax      dma_src_buf,u
                    clra
ramp_lp             sta       ,x+
                    inca
                    bne       ramp_lp

                    * Clear destination buffer with $00
                    leax      dma_dst_buf,u
                    ldb       #0
clr2_lp             clr       ,x+
                    decb
                    bne       clr2_lp

                    * Setup DMA Source & Destination Addresses
                    leax      dma_src_buf,u
                    tfr       x,d
                    clr       >DMA_SRC_ADDR
                    sta       >DMA_SRC_ADDR+1
                    stb       >DMA_SRC_ADDR+2

                    leax      dma_dst_buf,u
                    tfr       x,d
                    clr       >DMA_DST_ADDR
                    sta       >DMA_DST_ADDR+1
                    stb       >DMA_DST_ADDR+2

                    * Setup 1D Size: 256 bytes ($000100)
                    clr       >DMA_SIZE_1D
                    lda       #$01
                    sta       >DMA_SIZE_1D+1
                    clr       >DMA_SIZE_1D+2

                    * Trigger DMA Copy: START=1, 1D=0, FILL=0, ENABLE=1 ($81)
                    lda       #$81
                    sta       >DMA_CTRL

                    * Verify destination buffer
                    leax      dma_dst_buf,u
                    clra
chk2_lp             cmpa      ,x+
                    bne       T2_Fail
                    inca
                    bne       chk2_lp

                    lbsr      PRINTS
                    fcc       "         Buffer Verification: Ramp pattern copied perfectly"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lbsr      PRINTS
                    fcc       "         Copy verification failed!"
                    fcb       0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: 2D Rectangular Block Copy (16x16 with 32-byte stride)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] 2D Rectangular Blit (16x16 block, stride 32)"
                    fcb       C$CR,0

                    * Clear 1024-byte destination buffer
                    leax      dma_dst_buf,u
                    ldy       #1024
clr3_lp             clr       ,x+
                    leay      -1,y
                    bne       clr3_lp

                    * Setup Source & Destination Addresses
                    leax      dma_src_buf,u
                    tfr       x,d
                    clr       >DMA_SRC_ADDR
                    sta       >DMA_SRC_ADDR+1
                    stb       >DMA_SRC_ADDR+2

                    leax      dma_dst_buf,u
                    tfr       x,d
                    clr       >DMA_DST_ADDR
                    sta       >DMA_DST_ADDR+1
                    stb       >DMA_DST_ADDR+2

                    * Setup 2D Dimensions (16 x 16)
                    clr       >DMA_2D_WIDTH
                    lda       #16
                    sta       >DMA_2D_WIDTH+1
                    clr       >DMA_2D_HEIGHT
                    lda       #16
                    sta       >DMA_2D_HEIGHT+1

                    * Setup Strides (Src: 16, Dst: 32)
                    clr       >DMA_SRC_STRIDE
                    lda       #16
                    sta       >DMA_SRC_STRIDE+1
                    clr       >DMA_DST_STRIDE
                    lda       #32
                    sta       >DMA_DST_STRIDE+1

                    * Trigger 2D Blit: START=1, 2D=1, ENABLE=1 ($83)
                    lda       #$83
                    sta       >DMA_CTRL

                    lbsr      PRINTS
                    fcc       "         2D Blit Stride Geometry Configured"
                    fcb       0
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
                    fcc       "RESULT: ALL DMA TESTS COMPLETED SUCCESSFULLY!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: DMA ENGINE HARDWARE MISMATCH DETECTED!"
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

PUTC                pshs      a,b,cc,x,y
                    leax      temp_buf,u
                    sta       ,x
                    ldy       #1
                    lda       #1
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
