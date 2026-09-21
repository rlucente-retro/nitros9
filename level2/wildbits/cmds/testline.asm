
    nam testline
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
mapaddr     rmb 2
currBlk     rmb 2
blkCnt      rmb 1
clutheader  rmb 2
clutdata    rmb 2
iter_1      rmb 1
tmpb        rmb 1
tmpg        rmb 1
tmpr        rmb 1
tmpclut     rmb 1024
curx        rmb 2
cury        rmb 2
    rmb 250
size equ .
name fcs /testline/
    fcb edition

start
    ldx #0
    stx <clutheader
    stx <clutdata
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
    lbne error
storeblk
    tfr x,d
    stb <bmblock

    ; SS.Palet
    ldx #0
    ldy #0
    lda #0
    ldb #SS.Palet
    os9 I$SetStt

    leax clut0,pcr
    lbsr clutload
    lbsr clutcopy

    ; SS.PScrn
    ldx #0
    ldy #0
    lda #0
    ldb #SS.PScrn
    os9 I$SetStt

    lbsr clearbitmap

    ; SS.DScrn
    ldx #FX_BM+FX_GRF
    ldy #FT_OMIT
    lda #0
    ldb #SS.DScrn
    os9 I$SetStt

    ; Now draw 100 pixels in a diagonal line (x=50..150, y=50..150)
    ldd #50
    std <curx
    std <cury
drawloop
    ldx <curx
    ldb <cury+1
    lda #10
    lbsr writepixel
    ldd <curx
    addd #1
    std <curx
    ldd <cury
    addd #1
    std <cury
    cmpd #150
    bne drawloop

    ; Sleep 2 seconds so we can inspect
    ldx #120
    os9 F$Sleep

    ; Turn off graphics
    ldx #FX_TXT
    ldy #FT_OMIT
    lda #0
    ldb #SS.DScrn
    os9 I$SetStt

    clrb
error
    os9 F$Exit

clut0 fcs /xtclut/
      fcb $0D

clearbitmap
    lda #10
    ldx <bmblock0
    pshs u
clrloop@
    ldb #1
    os9 F$MapBlk
    pshs u
    ldy #$2000
loop@
    clr ,u+
    leay -1,y
    bne loop@
    puls u
    ldb #1
    os9 F$ClrBlk
    leax 1,x
    deca
    bne clrloop@
    puls u
    rts

clutload
    pshs a,b,x,y,u
    lda #0
    os9 F$Link
    beq cont@
    os9 F$Load
    lbcs err@
cont@
    stu <clutheader
    sty <clutdata
err@
    puls u,y,x,b,a
    rts

clutcopy
    pshs a,b,y,u
    ldx #0
    ldy <clutdata
    lda #0
    ldb #SS.DfPal
    os9 I$SetStt
    puls u,y,a,b,pc

writepixel
    pshs a,b,x,y,u
    leas -1,s
    clr ,s
    lda 2,s
    ldb #64
    mul
    adda 2,s
    ror ,s
    addd 3,s
    ror ,s
    pshs a
    anda #31
    tfr d,x
    ldb 1,s
    addb #192
    puls a
    rora
    lsra
    lsra
    lsra
    lsra
    pshs x
    adda <bmblock
    cmpa <pxlblk
    beq storepixel@
    tst <pxlblk
    beq mapit@
    bsr fclrblk
mapit@
    sta <pxlblk
    ldx <pxlblk0
    ldb #1
    pshs u
    os9 F$MapBlk
    lbcc mapgood@
    puls u,x
    bra cleanup@
mapgood@
    stu <pxlblkaddr
    puls u
storepixel@
    ldd <pxlblkaddr
    puls x
    leax d,x
    lda 1,s
    sta ,x
cleanup@
    leas 1,s
    puls a,b,x,y,u,pc

fclrblk
    pshs b,u
    ldu <pxlblkaddr
    ldb #1
    os9 F$ClrBlk
    puls b,u,pc

    emod
eom equ *
    end
