********************************************************************
* sprtest - TinyVicky 128 hardware sprite probe
*
* Validates sprite register decoding, attribute memory in Page $C0
* ($1300-$16FF), 16-bit coordinate writes, and master video sprite enable.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* ------------------------------------------------------------------
*   1      2026/09/20  Antigravity
* Created.

                    nam       sprtest
                    ttl       TinyVicky 128 hardware sprite probe

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
oldmcr              rmb       1
line                rmb       80
stack               rmb       200
size                equ       .

name                fcs       /sprtest/
                    fcb       edition

hexch               fcc       /0123456789ABCDEF/

t0                  fcc       /sprtest ed.1: TinyVicky 128 hardware sprite probe/
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

lb1                 fcc       /mstr sprite en/
lb2                 fcc       /spr0 ctrl     /
lb3                 fcc       /spr0 coords   /
lb4                 fcc       /spr127 ctrl   /
lb5                 fcc       /spr127 coords /

start               leax      t0,pcr
                    ldy       #t0l
                    lbsr      PutLine
                    leax      t1,pcr
                    ldy       #t1l
                    lbsr      PutLine

* ---- 1. Master Control Register sprite enable ($FFC0 bit 5)
                    lda       >MASTER_CTRL_REG_L
                    sta       <oldmcr
                    ora       #Mstr_Ctrl_Sprite_En
                    sta       >MASTER_CTRL_REG_L
                    lda       >MASTER_CTRL_REG_L
                    anda      #Mstr_Ctrl_Sprite_En
                    sta       <got
                    lda       #Mstr_Ctrl_Sprite_En
                    sta       <expv
                    leax      lb1,pcr
                    lbsr      Rpt8
                    lda       <oldmcr
                    sta       >MASTER_CTRL_REG_L

* ---- Map Page $C0 (contains sprite records at $1300-$16FF)
                    ldx       #SPRITE_BLK
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    tfr       u,y
                    puls      u
                    lbcs      MapErr

* ---- 2. Sprite 0 attribute record ($1300)
                    leax      SPRITE_REC_OFF,y
                    * Write test pattern: Enable + 16x16 + Depth 1 + LUT 1
                    lda       #(SPRITE_Ctrl_Enable|SPRITE_SIZE1|SPRITE_DEPTH0|SPRITE_LUT0)
                    sta       SPR_CTRL,x
                    lda       SPR_CTRL,x
                    sta       <got
                    lda       #(SPRITE_Ctrl_Enable|SPRITE_SIZE1|SPRITE_DEPTH0|SPRITE_LUT0)
                    sta       <expv
                    leax      lb2,pcr
                    lbsr      Rpt8

* ---- 3. Sprite 0 coordinate registers (X=$0064, Y=$0050)
                    leax      SPRITE_REC_OFF,y
                    ldd       #$0064
                    std       SPR_X_H,x
                    ldd       #$0050
                    std       SPR_Y_H,x
                    ldd       SPR_X_H,x
                    std       <got
                    ldd       SPR_Y_H,x
                    std       <got+2
                    ldd       #$0064
                    std       <expv
                    ldd       #$0050
                    std       <expv+2
                    leax      lb3,pcr
                    lbsr      Rpt32

* ---- 4. Sprite 127 attribute record ($1300 + 127*8 = $16F8)
                    leax      SPRITE_REC_OFF+(127*8),y
                    lda       #(SPRITE_Ctrl_Enable|SPRITE_SIZE0|SPRITE_DEPTH1)
                    sta       SPR_CTRL,x
                    lda       SPR_CTRL,x
                    sta       <got
                    lda       #(SPRITE_Ctrl_Enable|SPRITE_SIZE0|SPRITE_DEPTH1)
                    sta       <expv
                    leax      lb4,pcr
                    lbsr      Rpt8

* ---- 5. Sprite 127 coordinate registers (X=$00C8, Y=$0096)
                    leax      SPRITE_REC_OFF+(127*8),y
                    ldd       #$00C8
                    std       SPR_X_H,x
                    ldd       #$0096
                    std       SPR_Y_H,x
                    ldd       SPR_X_H,x
                    std       <got
                    ldd       SPR_Y_H,x
                    std       <got+2
                    ldd       #$00C8
                    std       <expv
                    ldd       #$0096
                    std       <expv+2
                    leax      lb5,pcr
                    lbsr      Rpt32

* Clean up: zero out test sprite records
                    leax      SPRITE_REC_OFF,y
                    clr       SPR_CTRL,x
                    leax      SPRITE_REC_OFF+(127*8),y
                    clr       SPR_CTRL,x

                    * Unmap Page $C0
                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u

                    clrb
                    os9       F$Exit

MapErr              clr       <got
                    lda       #$FF
                    sta       <expv
                    leax      lb2,pcr
                    lbsr      Rpt8
                    ldb       #1
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

* ---- Rpt32: the same for a 32-bit value
Rpt32               ldy       #line
                    ldb       #LBLEN
                    lbsr      Copy
                    ldd       <got
                    lbsr      Hex4
                    ldd       <got+2
                    lbsr      Hex4
                    leax      texp,pcr
                    ldb       #texpl
                    lbsr      Copy
                    ldd       <expv
                    lbsr      Hex4
                    ldd       <expv+2
                    lbsr      Hex4
                    ldd       <got
                    cmpd      <expv
                    bne       Verdict
                    ldd       <got+2
                    cmpd      <expv+2

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

* ---- Hex4: D -> four ASCII hex digits at ,y (X preserved)
Hex4                pshs      b
                    bsr       Hex2
                    puls      a
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
