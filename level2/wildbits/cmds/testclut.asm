
    nam testclut
    ifp1
    use defsfile
    endc
tylg set Prgrm+Objct
atrv set ReEnt+rev
rev set 0
edition set 1
    mod eom,name,tylg,atrv,start,size
clutheader rmb 2
clutdata rmb 2
    rmb 200
size equ .
name fcs /testclut/
    fcb edition

start
    leax clut0,pcr
    lbsr clutload
    ldd <clutdata
    bne ok@
    ; clutdata is 0! clutload failed!
    leax fail_msg,pcr
    lda #1
    ldy #11
    os9 I$WritLn
    clrb
    os9 F$Exit
ok@
    leax ok_msg,pcr
    lda #1
    ldy #9
    os9 I$WritLn
    clrb
    os9 F$Exit

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

clut0 fcs /xtclut/
      fcb $0D
fail_msg fcc /CLUT FAILED/
         fcb $0D
ok_msg fcc /CLUT OK/
       fcb $0D
    emod
eom equ *
    end
