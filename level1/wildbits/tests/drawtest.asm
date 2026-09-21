********************************************************************
* drawtest
* test for mouse
*
* by John Federico
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------


                    nam       drawtest
                    ttl       drawtest


                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

pxlblk0		    rmb	      1
pxlblk		    rmb	      1
pxlblkaddr	    rmb	      2
currPath            rmb       1         current path for file read
bmblock0	    rmb	      1
bmblock             rmb       1         bitmap block#
mapaddr             rmb       2         Address for mapped block
currBlk             rmb       2         current mapped in block, (need to read into X)
blkCnt              rmb       1         Counter for block loop
clutheader          rmb       2
clutdata            rmb       2
currColor           rmb       1
tmpb                rmb       1
tmpg                rmb       1
tmpr                rmb       1
tmpclut             rmb       1024      
                    rmb       250       stack space
size                equ       .

name                fcs       /drawtest/
                    fcb       edition


start
*                   **** initialize vars
                    ldx       #0
                    stx       <clutheader
                    stx       <clutdata
		    stx	      <pxlblk0
		    stx	      <bmblock0
                    lda       #10                 default color = 10 (bright green)
                    sta       <currColor

*                   **** determine screen path (default to 0, use 1 if 0 not screen)
                    clr       <currPath
                    lda       #0
                    ldb       #SS.ScTyp
                    os9       I$GetStt
                    bcc       @pathok
                    inc       <currPath
@pathok
*                   **** get a new bitmap 0
                    ldy       #$0                 bitmap #
                    ldx       #$0                 screentype = 320x240 (1=320x200)
                    lda       <currPath           path #
                    ldb       #SS.AScrn           assign and create bitmap
                    os9       I$SetStt
                    bcc       storeblk            no error, store block#
                    cmpb      #E$WADef            check if window already defined
                    lbne      error               if other error, then end else continue
storeblk            tfr       x,d
                    stb       <bmblock            store bitmap block# for later use

setBMClut
*                   **** assign clut0 to bm0
                    ldx       #0                  clut #
                    ldy       #0                  bitmap #
                    lda       <currPath           path #
                    ldb       #SS.Palet           assign clut # to bitmap #
                    os9       I$SetStt
		    lbsr      clutload
		    lbsr      clutcopy
setlayer
*                   **** assign bm0 to layer0               
                    ldx       #0                  layer #
                    ldy       #0                  bitmap #
                    lda       <currPath           path # 
                    ldb       #SS.PScrn           position bitmap # on layer #
                    os9       I$SetStt

		    lbsr      clearbitmap

main                
*                    **** turn on graphics
                    ldx       #FX_BM+FX_GRF       turn on bitmaps and graphics
                    ldy       #FT_OMIT            don't change $FFC1
                    lda       <currPath           path #
                    ldb       #SS.DScrn           display screen with new settings 
                    os9       I$SetStt            
                    lbcs      error                 

pollkeyboard        lbsr      INKEY
                    tsta
                    beq       pollmouse
                    cmpa      #113                'q'
                    beq       exit
                    cmpa      #'Q'
                    beq       exit
                    cmpa      #$1B                ESC
                    beq       exit
                    cmpa      #99                 'c'
                    beq       clearsub
                    cmpa      #'C'
                    beq       clearsub
                    cmpa      #'+'
                    beq       nextcol@
                    cmpa      #'='
                    beq       nextcol@
                    cmpa      #'-'
                    beq       prevcol@
                    cmpa      #'_'
                    beq       prevcol@
                    cmpa      #'0'
                    blo       pollmouse
                    cmpa      #'9'
                    bhi       pollmouse
                    suba      #'0'
                    leax      colortbl,pcr
                    lda       a,x
                    sta       <currColor
                    bra       pollmouse
nextcol@            inc       <currColor
                    bra       pollmouse
prevcol@            dec       <currColor
                    bra       pollmouse
clearsub	    lbsr      clearbitmap

pollmouse	    ldb	      #SS.Mouse
		    clra
		    os9	      I$GetStt
		    bita      #$01                left button: draw with current color
		    bne	      drawleft@
		    bita      #$02                right button: erase (color 0)
		    bne	      drawright@
		    bra	      pollkeyboard
drawleft@	    lda	      <currColor
		    lbsr      drawpixel
		    bra	      pollkeyboard
drawright@	    clra                          color 0 (black / eraser)
		    lbsr      drawpixel
		    bra	      pollkeyboard


*                   **** turn off graphics
exit                tst       <pxlblk
                    beq       @nomap
                    lbsr      fclrblk
                    clr       <pxlblk
@nomap              ldx       #FX_TXT             turn on text, all else off
                    ldy       #FT_OMIT            don't change $FFC1
                    lda       <currPath           path #
                    ldb       #SS.DScrn           display screen with new settings 
                    os9       I$SetStt            
                    lbcs      error

*                   **** unlink clut
                    lbsr      unlinkclut

*                   **** deallocate bitmap memory
                    ldy       #$0                 bitmap 0
                    lda       <currPath           path #
                    ldb       #SS.FScrn           free screen ram
                    os9       I$SetStt
                    lbcs      error
                    clrb

error               os9       F$Exit

colortbl            fcb       0,9,10,11,12,13,14,15,7,3
clutmod             fcs       /xtclut/
clutpath            fcc       "/dd/cmds/xtclut"
                    fcb       $0D


clearbitmap         tst       <pxlblk
                    beq       @nomap
                    lbsr      fclrblk
                    clr       <pxlblk
@nomap              lda	      #10	          loop through 10 blocks
                    ldx	      <bmblock0		  block#
		    pshs      u		          preserve u
clrloop@            ldb       #1                  map 1 block
                    os9       F$MapBlk            map the block
		    pshs      u			  preserve start addr of block
		    ldy	      #$2000		  set up clear loop
loop@		    clr	      ,u+		  clear 8K
		    leay      -1,y		  decrement counter
		    bne	      loop@		  
		    puls      u			  puls start addr to clear block
		    ldb	      #1
		    os9	      F$ClrBlk	          clear block
		    leax      1,x		  incrment block number 
		    deca      			  decrement block counter
		    bne	      clrloop@
		    puls      u
		    rts
		    

INKEY               clra                          std in
                    ldb       #SS.Ready
                    os9       I$GetStt            see if key ready
                    bcc       getit
                    cmpb      #E$NotRdy           no keys ready=no error
                    bne       exit@               other error, report it
                    clra                          no error
                    bra       exit@
getit               lbsr      FGETC               go get the key
                    tsta
exit@               rts

FGETC               pshs      a,x,y
                    ldy       #1                  number of char to print
                    tfr       s,x                 point x at 1 char buffer
                    os9       I$Read
                    puls      a,x,y,pc


drawpixel	    pshs      a                   ; 0,s = color
		    tfr	      x,d
		    lsra
		    rorb
		    cmpd      #318
		    bls       @xok
		    ldd       #318
@xok		    pshs      d                   ; 0,1,s = base X; 2,s = color
		    tfr	      y,d
		    lsra
		    rorb
		    cmpd      #238
		    bls       @yok
		    ldd       #238
@yok		    pshs      d                   ; 0,1,s = base Y; 2,3,s = base X; 4,s = color

		    ; Pixel (X, Y)
		    ldx       2,s
		    ldb       1,s
		    lda       4,s
		    lbsr      writepixel

		    ; Pixel (X+1, Y)
		    ldx       2,s
		    leax      1,x
		    ldb       1,s
		    lda       4,s
		    lbsr      writepixel

		    ; Pixel (X, Y+1)
		    ldx       2,s
		    ldb       1,s
		    incb
		    lda       4,s
		    lbsr      writepixel

		    ; Pixel (X+1, Y+1)
		    ldx       2,s
		    leax      1,x
		    ldb       1,s
		    incb
		    lda       4,s
		    lbsr      writepixel

		    leas      5,s
		    rts
		    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; clut Load
; Loads CLUT from link, file, or fallback
clutload            pshs      a,b,x,y,u
                    lda       #0                  F$Load a=language, 0=any
                    leax      clutmod,pcr         try linking module
                    os9       F$Link
                    bcc       cont@
                    lda       #0
                    leax      clutpath,pcr        try loading /dd/cmds/xtclut
                    os9       F$Load
                    bcc       cont@
                    lda       #0
                    leax      clutmod,pcr         try loading xtclut from exec dir
                    os9       F$Load
                    bcc       cont@
*                   **** All loads failed; use built-in fallback palette
                    leay      tmpclut,u
                    ldx       #1024
@clr                clr       ,y+
                    leax      -1,x
                    bne       @clr
                    lda       #$FF                Green = $FF for entry 10 (offset 40: B=0, G=$FF, R=0, A=0)
                    sta       tmpclut+41,u
                    leay      tmpclut,u
                    sty       <clutdata
                    bra       done@
cont@               stu       <clutheader
                    sty       <clutdata
done@               puls      u,y,x,b,a
                    rts


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; clut copy
; copies clut from loaded module to clut#0
clutcopy            pshs      a,b,x,y,u
                    ldy       <clutdata
                    beq       err@
                    ldx       #0                  CLUT #0
                    lda       <currPath           path #
                    ldb       #SS.DfPal           define palette clut#0 with data y
                    os9       I$SetStt
err@                puls      a,b,x,y,u,pc


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; unlink clut
; unlink the current clut module from memory
unlinkclut          pshs      u
                    ldu       <clutheader
                    beq       @done
                    os9       F$Unlink
@done               puls      u,pc


;;; write pixel
;;; takes X,Y and color and puts it in the bitmap bmblock
;;; x=X
;;; b=Y
;;; a=color
;;; use stack for temp vars
writepixel          pshs      a,b,x,y,u
                    leas      -1,s                  add 1 byte to stack for carry
                    clr       ,s                    0=carry,1=color,2=y,3=X
*                   **** d = 320 * gy.
*                   **** 320 = 256 + 64, so use MUL for the lower byte,
*                   **** and then add gy (gy * 256) to the upper byte.
                    lda       2,s                   py     ; 8 bits.
                    ldb       #64
                    mul
                    adda      2,s                   py
                    ror       ,s                    <pcarry  ; Collect the carry bit.
*                   **** d += gx.
                    addd      3,s                   px     ; 16 bits.
                    ror       ,s                    <pcarry  ; Collect the carry bit.
*                   **** stash the block ID bits.
                    pshs      a

*                   **** move the lower 13 bits (8191) into a pointer.
                    anda      #31
                    tfr       d,x
*                   **** restore the carry.
*                   **** this add will set/clear the carry
*                   **** based on the previously collected carry bits.
                    ldb       1,s                   carry bit 
                    addb      #192
*                   **** ror it into the top of the block bits.
                    puls      a
                    rora
*                   **** shift the block bits to the bottom of A. 
                    lsra
                    lsra
                    lsra
                    lsra
*                   **** a now contains the relative block number,
*                   **** and X contains the block relative offset.xxxxxxxxw
                    pshs      x                   stx pixel offset
                    adda      <bmblock            add start of bitmap to relative to get block#
                    cmpa      <pxlblk              is this the currently mapped block?
                    beq       storepixel@         if current block, then just write the pixel
                    tst       <pxlblk              if not, check if mapped block exists, 0 if none
                    beq       mapit@              no mapped block then branch to map it
                    bsr       fclrblk             have a mapped block, clear it
mapit@              sta       <pxlblk              store the new block we will map
                    ldx       <pxlblk0             load x with mapblock for F$MapBlk
                    ldb       #1                  map 1 block
                    pshs      u                   push u (F$MapBlk returns address in u)
                    os9       F$MapBlk            Map the block
                    lbcc      mapgood@            if successful, finish
                    puls      u,x                 error, clean up and return
                    bra       cleanup@            
mapgood@            stu       <pxlblkaddr         store the logical address
                    puls      u
storepixel@         ldd       <pxlblkaddr
                    puls      x                   pull blk relative offset
                    leax      d,x                 add in logical start of block
                    lda       1,s                 lda with the color
                    sta       ,x                  write the pixel
cleanup@            leas      1,s                 pull carry byte off stack
                    puls      a,b,x,y,u,pc        clean up stack and return

fclrblk             pshs      b,u
                    ldu       <pxlblkaddr
                    ldb       #1
                    os9       F$ClrBlk
                    puls      b,u,pc


                    emod
eom                 equ       *
                    end
