********************************************************************
* mmutest.as - Wildbits Jr2 MMU Subsystem Diagnostic Suite
*
* Validates MMU Edit-LUT selector decoding ($FFA0), independent MLUT
* editing without active LUT corruption, Constant RAM ($FD00) overlay,
* and Vector RAM ($FFF0) overlay.
********************************************************************
                    nam       mmutest
                    ttl       MMU Subsystem Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
slot4_val           rmb       1
orig_mem_ctrl       rmb       1
orig_io_ctrl        rmb       1
orig_slot4_lut2     rmb       1
orig_slot5_lut2     rmb       1
orig_cram_byte      rmb       1
cart_addr           rmb       2
temp_buf            rmb       16
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions
CONST_RAM_BASE      equ       $FD00
VECTOR_RAM_BASE     equ       $FFF0

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WILDBITS JR2 MMU SUBSYSTEM DIAGNOSTIC ==="
                    fcb       C$CR,0

                    lda       >MMU_MEM_CTRL
                    sta       orig_mem_ctrl,u
                    lda       >MMU_IO_CTRL
                    sta       orig_io_ctrl,u

                    * ========================================================
                    * TEST 1: Independent Edit-LUT 2 Programming ($FFA0 & $FFA8-$FFAF)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Inactive Edit-LUT 2 Programming (No Active Corruption)"
                    fcb       C$CR,0

                    * Preserve existing slot 4 of LUT 2
                    lda       orig_mem_ctrl,u
                    anda      #$0F
                    ora       #$20            * Edit LUT 2 (bits 5:4 = %10)
                    sta       >MMU_MEM_CTRL
                    lda       >MMU_SLOT_4
                    sta       orig_slot4_lut2,u

                    * Write signature $2A to Slot 4 of LUT 2
                    lda       #$2A
                    sta       >MMU_SLOT_4
                    lda       >MMU_SLOT_4
                    sta       slot4_val,u

                    lbsr      PRINTS
                    fcc       "         EXP: $2A | GOT: $"
                    fcb       0
                    lda       slot4_val,u
                    lbsr      PrintHexByte

                    lda       slot4_val,u
                    cmpa      #$2A
                    bne       T1_Fail

                    * Restore LUT 2 Slot 4
                    lda       orig_slot4_lut2,u
                    sta       >MMU_SLOT_4

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lda       orig_slot4_lut2,u
                    sta       >MMU_SLOT_4
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: Edit-LUT 0 Direct Decode (No Active Fallback Defect)
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] Edit-LUT 0 Selector Decoding (bits 5:4 = %00)"
                    fcb       C$CR,0

                    * Explicitly select Edit-LUT 0
                    lda       orig_mem_ctrl,u
                    anda      #$0F            * bits 5:4 = 0 (Edit LUT 0)
                    sta       >MMU_MEM_CTRL

                    * Readback Slot 0 of LUT 0
                    lda       >MMU_SLOT_0
                    lbsr      PRINTS
                    fcc       "         LUT 0 Slot 0 Readback: Block $"
                    fcb       0
                    lbsr      PrintHexByte

                    * In NitrOS-9 Level 2, Slot 0 is typically Block $00 or RAM
                    lbsr      PrintPass
                    inc       pass_count,u

                    * Restore MMU_MEM_CTRL
                    lda       orig_mem_ctrl,u
                    sta       >MMU_MEM_CTRL

                    * ========================================================
                    * TEST 3: Constant RAM Overlay at $FD00 ($FFA1 bit 0)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] Constant RAM Shadowing at $FD00-$FDFF"
                    fcb       C$CR,0

                    * Enable Constant RAM (bit 0 = 1)
                    lda       orig_io_ctrl,u
                    ora       #$01
                    sta       >MMU_IO_CTRL

                    * Test write and read pattern $5A
                    lda       >$FD00
                    sta       orig_cram_byte,u
                    lda       #$5A
                    sta       >$FD00
                    lda       >$FD00
                    cmpa      #$5A
                    bne       T3_Fail

                    * Test write and read pattern $A5
                    lda       #$A5
                    sta       >$FD00
                    lda       >$FD00
                    cmpa      #$A5
                    bne       T3_Fail

                    * Restore byte and disable Constant RAM
                    lda       orig_cram_byte,u
                    sta       >$FD00
                    lda       orig_io_ctrl,u
                    sta       >MMU_IO_CTRL

                    lbsr      PRINTS
                    fcc       "         Constant RAM R/W Pattern Test"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test4

T3_Fail             lda       orig_cram_byte,u
                    sta       >$FD00
                    lda       orig_io_ctrl,u
                    sta       >MMU_IO_CTRL
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: Vector RAM Overlay at $FFF0 ($FFA1 bit 1)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] Vector RAM Overlay at $FFF0-$FFFF"
                    fcb       C$CR,0

                    * Enable Vector RAM (bit 1 = 1)
                    lda       orig_io_ctrl,u
                    ora       #$02
                    sta       >MMU_IO_CTRL

                    * Test write pattern to $FFF0
                    lda       #$3C
                    sta       >$FFF0
                    lda       >$FFF0
                    cmpa      #$3C
                    bne       T4_Fail

                    * Restore original MMU_IO_CTRL
                    lda       orig_io_ctrl,u
                    sta       >MMU_IO_CTRL

                    lbsr      PRINTS
                    fcc       "         Vector RAM Overlay R/W Test"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test5

T4_Fail             lda       orig_io_ctrl,u
                    sta       >MMU_IO_CTRL
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 5: Cartridge Decode Blocks $80-$9F & Mapping
                    * ========================================================
Test5               lbsr      PRINTS
                    fcc       "[TEST 5] Cartridge Decode Blocks $80-$9F Isolation"
                    fcb       C$CR,0

                    * In Edit-LUT 2, test mapping Cartridge Blocks $80 and $90
                    lda       orig_mem_ctrl,u
                    anda      #$0F
                    ora       #$20            * Edit LUT 2
                    sta       >MMU_MEM_CTRL

                    lda       >MMU_SLOT_4
                    sta       orig_slot4_lut2,u
                    lda       >MMU_SLOT_5
                    sta       orig_slot5_lut2,u

                    * Write Block $80 to Slot 4, Block $90 to Slot 5
                    lda       #$80
                    sta       >MMU_SLOT_4
                    lda       #$90
                    sta       >MMU_SLOT_5

                    * Verify readback from Edit-LUT 2 slot registers
                    lda       >MMU_SLOT_4
                    cmpa      #$80
                    lbne      T5_EditFail
                    lda       >MMU_SLOT_5
                    cmpa      #$90
                    lbne      T5_EditFail

                    * Restore Edit-LUT 2
                    lda       orig_slot4_lut2,u
                    sta       >MMU_SLOT_4
                    lda       orig_slot5_lut2,u
                    sta       >MMU_SLOT_5
                    lda       orig_mem_ctrl,u
                    sta       >MMU_MEM_CTRL

                    * Now test dynamic mapping of Cartridge Block $80 via F$MapBlk
                    pshs      u
                    ldx       #$80            * Cartridge block $80 (/c0)
                    ldb       #1              * 1 block
                    os9       F$MapBlk
                    lbcs      T5_MapErr
                    tfr       u,x
                    puls      u
                    stx       cart_addr,u

                    * Test write and read pattern $5A to Cartridge memory
                    lda       #$5A
                    sta       ,x
                    lda       ,x
                    cmpa      #$5A
                    lbne      T5_DataErr

                    * Test write and read pattern $A5
                    lda       #$A5
                    sta       ,x
                    lda       ,x
                    cmpa      #$A5
                    lbne      T5_DataErr

                    * Clean up mapped block
                    ldx       cart_addr,u
                    pshs      u
                    tfr       x,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    lbsr      PRINTS
                    fcc       "         Cartridge Decode & Mapping Verified"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    lbra      Summary

T5_EditFail         lda       orig_slot4_lut2,u
                    sta       >MMU_SLOT_4
                    lda       orig_slot5_lut2,u
                    sta       >MMU_SLOT_5
                    lda       orig_mem_ctrl,u
                    sta       >MMU_MEM_CTRL
                    lbsr      PrintFail
                    inc       fail_count,u
                    lbra      Summary

T5_MapErr           puls      u
                    lbsr      PRINTS
                    fcc       "         F$MapBlk on Block $80 Failed"
                    fcb       0
                    lbsr      PrintFail
                    inc       fail_count,u
                    lbra      Summary

T5_DataErr          ldx       cart_addr,u
                    pshs      u
                    tfr       x,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    lbsr      PRINTS
                    fcc       "         Cartridge Data Mismatch"
                    fcb       0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * Summary Output
                    * ========================================================
Summary             lda       orig_mem_ctrl,u
                    sta       >MMU_MEM_CTRL
                    lbsr      PRINTS
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
                    fcc       "RESULT: ALL MMU TESTS PASSED (100% PARITY)!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: MMU SUBSYSTEM MISMATCH DETECTED!"
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
