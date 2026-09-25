********************************************************************
* rc16test - Wildbits Jr2 RC16 verification probe
*
* Validates the core hardware updates of Wildbits Jr2 v8_rc16:
*   1. FLASHDIS implementation flag ($FFA1 bit 7 = 1, read-only).
*   2. MMU register window isolation ($FFA0-$FFAF writes do not leak
*      into physical Slot 7 RAM at $1FA0-$1FAF).
*   3. FLASHDIS enable ($FFA1 bit 2 = 1 remaps $40-$9F to SRAM).
*   4. Block $40 is read/write SRAM when FLASHDIS is active.
*   5. Block $80 is read/write SRAM when FLASHDIS is active.
*   6. FLASHDIS disable ($FFA1 bit 2 = 0 restores flash/cartridge).
*   7. Block $40 is protected flash ROM when FLASHDIS is inactive.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* ------------------------------------------------------------------
*   1      2026/09/20  Antigravity
* Created.

                    nam       rc16test
                    ttl       Wildbits Jr2 RC16 verification probe

                    ifp1
                    use       defsfile
                    endc

LBLEN               equ       14                  every label is 14 wide

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

                    org       0
got                 rmb       4
expv                rmb       4
cnt                 rmb       1
oldval              rmb       1
saveffa0            rmb       1
saveffa1            rmb       1
line                rmb       80
stack               rmb       200
size                equ       .

name                fcs       /rc16test/
                    fcb       edition

hexch               fcc       /0123456789ABCDEF/

t0                  fcc       /rc16test ed.1: Wildbits Jr2 RC16 verification suite/
                    fcb       C$CR
t0l                 equ       *-t0
t1                  fcc       /check          got  exp/
                    fcb       C$CR
t1l                 equ       *-t1
texp                fcc       / exp /
texpl               equ       *-texp
tok                 fcc       / OK/
                    fcb       C$CR
tokl                equ       *-tok
tbad                fcc       / BAD/
                    fcb       C$CR
tbadl               equ       *-tbad

lb1                 fcc       /FLASHDIS impl /
lb2                 fcc       /MMU reg isol  /
lb3                 fcc       /FLASHDIS bit2 /
lb4                 fcc       /Block $40 RAM /
lb5                 fcc       /Block $80 RAM /
lb6                 fcc       /FLASHDIS off  /
lb7                 fcc       /Block $40 ROM /

start               leax      t0,pcr
                    ldy       #t0l
                    lbsr      PutLine
                    leax      t1,pcr
                    ldy       #t1l
                    lbsr      PutLine

                    * Preserve MMU control registers
                    lda       >MMU_MEM_CTRL
                    sta       <saveffa0
                    lda       >MMU_IO_CTRL
                    sta       <saveffa1

* ---- 1. FLASHDIS implementation flag ($FFA1 bit 7 = 1, read-only)
                    lda       >MMU_IO_CTRL
                    anda      #FLASHDIS.OK
                    sta       <got
                    lda       #FLASHDIS.OK
                    sta       <expv
                    leax      lb1,pcr
                    lbsr      Rpt8

* ---- 2. MMU register window isolation ($FFA0-$FFAF write inhibit)
* Find the physical block mapped in Slot 7 of the active LUT
                    lda       <saveffa0
                    anda      #$03                * active LUT
                    tfr       a,b
                    aslb
                    aslb
                    aslb
                    aslb                          * B = active LUT << 4
                    lda       <saveffa0
                    anda      #$CF                * clear bits 5:4, keep bits 1:0!
                    pshs      b
                    ora       ,s+                 * EDIT_LUT = ACT_LUT, ACT_LUT unchanged!
                    sta       >MMU_MEM_CTRL
                    lda       >MMU_SLOT_7         * read block mapped in Slot 7
                    sta       <oldval             * temporary store for block number
                    lda       <saveffa0
                    sta       >MMU_MEM_CTRL       * restore original MMU_MEM_CTRL

                    * Map Slot 7's block into user space
                    ldb       <oldval
                    clra
                    tfr       d,x
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,y
                    puls      u
                    lbcs      T2_MapErr

                    * Offset $1FA0 in this block corresponds to $FFA0 in Slot 7
                    leax      $1FA0,y
                    lda       ,x
                    sta       <oldval
                    lda       #$5A
                    sta       ,x                  * write test signature to RAM

                    * Now perform writes to MMU registers at $FFA0-$FFAF
                    lda       <saveffa0
                    sta       >MMU_MEM_CTRL       * write $FFA0
                    lda       <saveffa1
                    sta       >MMU_IO_CTRL        * write $FFA1

                    * Verify physical RAM was NOT overwritten by MMU register write
                    lda       ,x
                    sta       <got
                    lda       #$5A
                    sta       <expv
                    lda       <oldval
                    sta       ,x                  * restore original RAM value

                    * Unmap block
                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    leax      lb2,pcr
                    lbsr      Rpt8
                    bra       Check3

T2_MapErr           clr       <got
                    lda       #$5A
                    sta       <expv
                    leax      lb2,pcr
                    lbsr      Rpt8

* ---- 3. FLASHDIS bit 2 enable
Check3              lda       >MMU_IO_CTRL
                    ora       #FLASHDIS
                    sta       >MMU_IO_CTRL
                    lda       >MMU_IO_CTRL
                    anda      #FLASHDIS
                    sta       <got
                    lda       #FLASHDIS
                    sta       <expv
                    leax      lb3,pcr
                    lbsr      Rpt8

* ---- 4. Block $40 is writable RAM when FLASHDIS is active
                    ldx       #$0040
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,y
                    puls      u
                    bcs       T4_MapErr

                    lda       #$5A
                    sta       ,y
                    lda       ,y
                    sta       <got
                    lda       #$5A
                    sta       <expv

                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    leax      lb4,pcr
                    lbsr      Rpt8
                    bra       Check5

T4_MapErr           clr       <got
                    lda       #$5A
                    sta       <expv
                    leax      lb4,pcr
                    lbsr      Rpt8

* ---- 5. Block $80 is writable RAM when FLASHDIS is active
Check5              ldx       #$0080
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,y
                    puls      u
                    bcs       T5_MapErr

                    lda       #$3C
                    sta       ,y
                    lda       ,y
                    sta       <got
                    lda       #$3C
                    sta       <expv

                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    leax      lb5,pcr
                    lbsr      Rpt8
                    bra       Check6

T5_MapErr           clr       <got
                    lda       #$3C
                    sta       <expv
                    leax      lb5,pcr
                    lbsr      Rpt8

* ---- 6. FLASHDIS disable
Check6              lda       >MMU_IO_CTRL
                    anda      #~FLASHDIS
                    sta       >MMU_IO_CTRL
                    lda       >MMU_IO_CTRL
                    anda      #FLASHDIS
                    sta       <got
                    clr       <expv
                    leax      lb6,pcr
                    lbsr      Rpt8

* ---- 7. Block $40 is Flash ROM when FLASHDIS is inactive (writes ignored)
                    ldx       #$0040
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,y
                    puls      u
                    bcs       T7_MapErr

                    lda       ,y                  * read flash byte
                    sta       <oldval
                    coma
                    sta       ,y                  * try writing inverted byte
                    lda       ,y                  * read back (should be unchanged)
                    sta       <got
                    lda       <oldval
                    sta       <expv

                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    leax      lb7,pcr
                    lbsr      Rpt8
                    bra       Done

T7_MapErr           stb       <got
                    lda       #$00
                    sta       <expv
                    leax      lb7,pcr
                    lbsr      Rpt8

Done                lda       <saveffa0
                    sta       >MMU_MEM_CTRL
                    lda       <saveffa1
                    sta       >MMU_IO_CTRL
                    clrb
                    os9       F$Exit

* ---- Rpt8: X -> a 14-char label, got and expv hold one byte each
Rpt8                ldy       #line
                    ldb       #LBLEN
                    lbsr      Copy
                    lda       <got
                    lbsr      Hex2
                    leax      texp,pcr
                    ldb       #texpl
                    lbsr      Copy
                    lda       <expv
                    lbsr      Hex2
                    lda       <got
                    cmpa      <expv
                    bra       Verdict

* ---- Verdict: Z set on entry means the check matched
Verdict             beq       VOK
                    leax      tbad,pcr
                    ldb       #tbadl
                    bra       VPut
VOK                 leax      tok,pcr
                    ldb       #tokl
VPut                lbsr      Copy
                    tfr       y,d
                    subd      #line
                    tfr       d,y
                    ldx       #line
                    bra       PutLine

* ---- Copy: B bytes from X to Y, both advance
Copy                stb       <cnt
CopyLoop            lda       ,x+
                    sta       ,y+
                    dec       <cnt
                    bne       CopyLoop
                    rts

* ---- PutLine: X -> text with its CR, Y = length
PutLine             lda       #1
                    os9       I$WritLn
                    rts

* ---- Hex2: A -> two ASCII hex digits at ,y++ (X preserved)
Hex2                pshs      a,x
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nib
                    lda       ,s
                    anda      #$0F
                    bsr       Nib
                    puls      a,x,pc
Nib                 leax      hexch,pcr
                    lda       a,x
                    sta       ,y+
                    rts

                    emod
eom                 equ       *
                    end
