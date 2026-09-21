
    nam testwp
    ifp1
    use defsfile
    endc
tylg set Prgrm+Objct
atrv set ReEnt+rev
rev set 0
edition set 1
    mod eom,name,tylg,atrv,start,size
pxlblk0     rmb 1
pxlblk      rmb 1
pxlblkaddr  rmb 2
currPath    rmb 1
bmblock0    rmb 1
bmblock     rmb 1
    rmb 200
size equ .
name fcs /testwp/
    fcb edition

start
    ldx #0
    stx <pxlblk0
    stx <bmblock0

    ; SS.AScrn
    ldy #0
    ldx #0
    lda #0
    ldb #SS.AScrn
    os9 I$SetStt
    bcc storeblk
    cmpb #E$WADef
    lbne err_ascrn
storeblk
    tfr x,d
    stb <bmblock

    ; Now test mapping block with F$MapBlk
    lda <bmblock
    sta <pxlblk
    ldx <pxlblk0
    ldb #1
    os9 F$MapBlk
    lbcs err_mapblk
    stu <pxlblkaddr

    ; write a byte
    lda #10
    sta ,u

    leax ok_msg,pcr
    lda #1
    ldy #10
    os9 I$WritLn
    clrb
    os9 F$Exit

err_ascrn
    leax ascrn_msg,pcr
    lda #1
    ldy #10
    os9 I$WritLn
    clrb
    os9 F$Exit

err_mapblk
    leax map_msg,pcr
    lda #1
    ldy #10
    os9 I$WritLn
    clrb
    os9 F$Exit

ok_msg fcc /MAP GOOD!/
       fcb $0D
ascrn_msg fcc /ASCRN ERR/
          fcb $0D
map_msg fcc /MAP ERR! /
        fcb $0D
    emod
eom equ *
    end
