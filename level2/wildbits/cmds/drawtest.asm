********************************************************************
* drawtest
* test for mouse
*
* by John Federico
*
*  7       2026/09/24  Antigravity
* Restored full terminal colors and screen on exit by writing ASCII $0C
* (Form Feed / ClrScrn, equivalent to 'cls' / 'display c'), repainting the entire
* text attribute matrix with active theme colors (yellow on purple) instead of
* leaving unwritten lines black.
*
*  6       2026/09/24  Antigravity
* Eliminated video SDRAM bus contention and 60 Hz static dashes by adding
* frame-paced yielding (os9 F$Sleep 1) in the interactive mouse/keyboard loop,
* preventing 100% CPU bus saturation while preserving responsive 60 fps drawing.
*
*  5       2026/09/24  Antigravity
* Eliminated FPGA text raster pipeline static dashes by enabling text overlay
* (FX_BM+FX_GRF+FX_OVR+FX_TXT = $0F) in SS.DScrn, keeping the Vicky text pipeline
* synchronized with blanked text buffers ($C2/$C3) as proven in dmashowtest.
* Separated pxlblk_active flag from 16-bit pxlblk_mapped block tracker in writepixel.
*
*  4       2026/09/24  Antigravity
* Eliminated vertical squish on exit by preserving MASTER_CTRL_REG_H ($FFC1 /
* DBL_Y) with FT_OMIT instead of clearing it to 0. Eliminated static dashes by
* zeroing graphics background color ($FFCD-$FFCF), disabling text cursor ($FFD0),
* explicitly disabling BM1/BM2/TL0..2/128 Sprites in Vicky Block $C0, clearing
* text buffers ($C2/$C3), and setting Layer Control 0/1 to disable unused layers.
********************************************************************


                    nam       drawtest
                    ttl       drawtest


                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       7

* Explicit Hardware Register Equates
VKY_BG_B            equ       $FFCD
VKY_BG_G            equ       $FFCE
VKY_BG_R            equ       $FFCF
VKY_TXT_CRSR_CTRL   equ       $FFD0
VKY_BRDR_CTRL       equ       $FFC4

                    mod       eom,name,tylg,atrv,start,size

pxlblk_active       rmb       1         0 = no pixel block mapped, 1 = mapped
pxlblk_mapped       rmb       2         16-bit block number currently mapped
pxlblkaddr          rmb       2
currPath            rmb       1         current path for file read
bmblock0            rmb       2         16-bit starting block# of bitmap
mapaddr             rmb       2         Address for mapped block
currBlk             rmb       2         current mapped in block, (need to read into X)
blkCnt              rmb       1         Counter for block loop
clutheader          rmb       2
clutdata            rmb       2
currColor           rmb       1
saved_eko           rmb       1         saved PD.EKO
saved_int           rmb       1         saved PD.INT
saved_qut           rmb       1         saved PD.QUT
popts               rmb       32        terminal option buffer (SS.Opt)
tmpb                rmb       1
tmpg                rmb       1
                    rmb       250       stack space
size                equ       .

name                fcs       /drawtest/
                    fcb       edition


start
*                   **** initialize vars
                    ldx       #0
                    stx       <clutheader
                    stx       <clutdata
                    clr       <pxlblk_active
                    ldx       #$FFFF
                    stx       <pxlblk_mapped
                    ldx       #0
                    stx       <bmblock0
                    lda       #10                 default color = 10 (bright green)
                    sta       <currColor

*                   **** install signal intercept handler
                    leax      sighandler,pcr
                    os9       F$Icpt

*                   **** determine screen path (default to 0, use 1 if 0 not screen)
                    clr       <currPath
                    lda       #0
                    ldb       #SS.ScTyp
                    os9       I$GetStt
                    bcc       @pathok
                    inc       <currPath
@pathok
*                   **** save terminal options and set raw input (echo off, break off)
                    leax      <popts,u
                    lda       <currPath
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       @optsdone
                    lda       4,x                 save original echo
                    sta       <saved_eko
                    clr       4,x                 echo off
                    lda       16,x                save original interrupt char (Ctrl-C)
                    sta       <saved_int
                    clr       16,x                interrupt char off (deliver as $03)
                    lda       17,x                save original quit char (Ctrl-E / ESC)
                    sta       <saved_qut
                    clr       17,x                quit char off (deliver as $05)
                    lda       <currPath
                    ldb       #SS.Opt
                    os9       I$SetStt
@optsdone
*                   **** get a new bitmap 0
                    ldy       #$0                 bitmap #
                    ldx       #$0                 screentype = 320x240 (1=320x200)
                    lda       <currPath           path #
                    ldb       #SS.AScrn           assign and create bitmap
                    os9       I$SetStt
                    bcc       storeblk            no error, store block#
                    cmpb      #E$WADef            check if window already defined
                    lbne      error               if other error, then end else continue
storeblk            stx       <bmblock0           store 16-bit starting block#

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
*                   **** disarm unused planes, text cursor, and blank text buffer
                    lbsr      disarm_planes

*                   **** assign bm0 to layer0               
                    lda       #$70                Layer 1 = 7 (disabled), Layer 0 = 0 (BM0)
                    sta       >VKY_LAYER_CTRL_0
                    lda       #$07                Layer 2 = 7 (disabled)
                    sta       >VKY_LAYER_CTRL_1
                    clr       >VKY_BRDR_CTRL      border off

                    ldx       #0                  layer #
                    ldy       #0                  bitmap #
                    lda       <currPath           path # 
                    ldb       #SS.PScrn           position bitmap # on layer #
                    os9       I$SetStt

		    lbsr      clearbitmap

main                
*                    **** turn on graphics with synchronized text overlay
                    ldx       #FX_BM+FX_GRF+FX_OVR+FX_TXT turn on bitmap with synchronized text overlay
                    ldy       #FT_OMIT            preserve MASTER_CTRL_REG_H ($FFC1 / DBL_Y)
                    lda       <currPath           path #
                    ldb       #SS.DScrn           display screen with new settings 
                    os9       I$SetStt            
                    lbcs      error                 

pollkeyboard        lbsr      INKEY
                    tsta
                    beq       pollmouse
                    cmpa      #'q'                'q'
                    beq       exit
                    cmpa      #'Q'                'Q'
                    beq       exit
                    cmpa      #$1B                ASCII ESC (27)
                    beq       exit
                    cmpa      #$05                PS/2 ESC (scancode $76 mapped to $05 in keydrv)
                    beq       exit
                    cmpa      #$03                Ctrl-C ($03)
                    beq       exit
                    cmpa      #'c'                'c'
                    beq       clearsub
                    cmpa      #'C'                'C'
                    beq       clearsub
                    cmpa      #'e'                'e' = eraser (color 0)
                    beq       seteraser@
                    cmpa      #'E'                'E' = eraser (color 0)
                    beq       seteraser@
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
seteraser@          clr       <currColor
                    bra       pollmouse
nextcol@            inc       <currColor
                    bra       pollmouse
prevcol@            dec       <currColor
                    bra       pollmouse
clearsub	    lbsr      clearbitmap
                    bra       pollmouse

pollmouse	    ldb	      #SS.Mouse
		    clra
		    os9	      I$GetStt
		    bita      #$01                left button: draw with current color
		    bne	      drawleft@
		    bita      #$02                right button: erase (color 0)
		    bne	      drawright@
		    bra	      pause@
drawleft@	    lda	      <currColor
		    lbsr      drawpixel
		    bra	      pause@
drawright@	    clra                          color 0 (black / eraser)
		    lbsr      drawpixel
pause@              ldx       #1                  sleep 1 tick (60 Hz frame pacing)
                    os9       F$Sleep
		    lbra      pollkeyboard

sighandler          lbra      exit

*                   **** turn off graphics
exit                tst       <pxlblk_active
                    beq       @nomap
                    lbsr      fclrblk
                    clr       <pxlblk_active
                    ldx       #$FFFF
                    stx       <pxlblk_mapped
@nomap              clr       >VKY_LAYER_CTRL_0   clear layer 0/1 registers
                    clr       >VKY_LAYER_CTRL_1   clear layer 2 register
*                   **** restore terminal options
                    leax      <popts,u
                    lda       <currPath
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       @restoredone
                    lda       <saved_eko
                    sta       4,x
                    lda       <saved_int
                    sta       16,x
                    lda       <saved_qut
                    sta       17,x
                    lda       <currPath
                    ldb       #SS.Opt
                    os9       I$SetStt
@restoredone
*                   **** restore text cursor
                    lda       #Vky_Cursor_Enable|Vky_Cursor_Flash_Rate0|Vky_Cursor_Flash_Rate1
                    sta       >VKY_TXT_CRSR_CTRL
*                   **** turn on text, all else off
                    ldx       #FX_TXT             turn on text, all else off
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

*                   **** clear screen and restore full terminal colors (matches 'cls' / 'display c')
                    leas      -1,s
                    lda       #$0C                $0C = Form Feed / ClrScrn (restores active theme colors across entire screen)
                    sta       ,s
                    lda       <currPath
                    ldy       #1
                    leax      ,s
                    os9       I$Write
                    leas      1,s

                    clrb
error               os9       F$Exit

colortbl            fcb       15,9,10,11,14,13,214,75,207,82
clutmod             fcs       /xtclut/
clutpath            fcc       "/dd/cmds/xtclut"
                    fcb       $0D


* --------------------------------------------------------------------
* clearbitmap: Clear 10 blocks (81,920 bytes) using CPU F$MapBlk loop
* --------------------------------------------------------------------
clearbitmap         pshs      cc,d,x,y,u
                    tst       <pxlblk_active      is a pixel block mapped?
                    beq       cb_start
                    lbsr      fclrblk             unmap it
                    clr       <pxlblk_active
                    ldx       #$FFFF
                    stx       <pxlblk_mapped

cb_start            orcc      #IntMasks           mask IRQs during block mapping
                    ldd       <bmblock0           load 16-bit starting block#
                    std       <currBlk
                    lda       #10                 10 blocks to clear
                    sta       <blkCnt

cb_loop             ldx       <currBlk            X = 16-bit block number
                    ldb       #1                  B = 1 block
                    pshs      u                   preserve U (process data)
                    os9       F$MapBlk            returns mapped addr in U ($C000)
                    bcs       cb_map_err          branch on mapping error
                    tfr       u,y                 Y = mapped buffer ($C000)
                    puls      u                   restore U immediately
                    pshs      y                   save block start address ($C000)

* Fast CPU clear: 4096 words = 8192 bytes (~2.6ms per block)
                    ldd       #0
                    ldx       #$1000
cb_clrlp            std       ,y++
                    leax      -1,x
                    bne       cb_clrlp

* Unmap the block
                    puls      y                   restore Y ($C000)
                    pshs      u                   preserve U
                    tfr       y,u                 U = mapped address
                    ldb       #1                  1 block
                    os9       F$ClrBlk            release block
                    puls      u                   restore U

cb_next             ldd       <currBlk
                    addd      #1
                    std       <currBlk
                    dec       <blkCnt
                    bne       cb_loop
                    bra       cb_done

cb_map_err          puls      u                   restore U on error
cb_done             puls      cc,d,x,y,u,pc


* --------------------------------------------------------------------
* disarm_planes: Explicitly disarm BM1, BM2, TL0..TL2, and 128 Sprites
* in Vicky Block $C0, zero background color, disable text cursor,
* and blank the text screen buffers (Blocks $C2 & $C3).
* --------------------------------------------------------------------
disarm_planes       pshs      cc,d,x,y,u
                    orcc      #IntMasks           mask IRQs
* 1. Set background color to solid black
                    clr       >VKY_BG_B
                    clr       >VKY_BG_G
                    clr       >VKY_BG_R
* 2. Disable text cursor
                    clr       >VKY_TXT_CRSR_CTRL

* 3. Disarm unmapped planes in Vicky Block $C0
                    ldx       #$C0                Vicky internal register block
                    ldb       #1                  1 block
                    pshs      u                   preserve U (process data)
                    os9       F$MapBlk
                    bcs       dp_err1
                    tfr       u,y                 Y = mapped $C0 registers
                    puls      u                   restore U immediately
                    pshs      y                   save Y
* Disable Bitmap 1 ($1008) and Bitmap 2 ($1010)
                    clr       $1008,y
                    clr       $1010,y
* Disable Tilemaps 0..2 ($1100, $110C, $1118)
                    clr       $1100,y
                    clr       $110C,y
                    clr       $1118,y
* Disable all 128 Sprites ($1300 + s*8)
                    leay      $1300,y
                    clra
                    ldb       #128
dp_sprlp            sta       ,y
                    leay      8,y
                    decb
                    bne       dp_sprlp
* Unmap Block $C0
                    puls      y
                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    bra       dp_txt

dp_err1             puls      u
                    bra       dp_done

* 4. Clear text screen character buffer (Block $C2) to spaces ($20)
dp_txt              ldx       #$C2                Text characters block
                    ldb       #1                  1 block
                    pshs      u
                    os9       F$MapBlk
                    bcs       dp_err2
                    tfr       u,y
                    puls      u
                    pshs      y
                    ldd       #$2020              fill with spaces
                    ldx       #2400               4800 bytes = 2400 words
dp_c2lp             std       ,y++
                    leax      -1,x
                    bne       dp_c2lp
                    puls      y
                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    bra       dp_attr

dp_err2             puls      u
                    bra       dp_done

* 5. Clear text screen attribute buffer (Block $C3) to 0
dp_attr             ldx       #$C3                Text attributes block
                    ldb       #1                  1 block
                    pshs      u
                    os9       F$MapBlk
                    bcs       dp_err3
                    tfr       u,y
                    puls      u
                    pshs      y
                    ldd       #0                  fill with zero attributes
                    ldx       #2400               4800 bytes = 2400 words
dp_c3lp             std       ,y++
                    leax      -1,x
                    bne       dp_c3lp
                    puls      y
                    pshs      u
                    tfr       y,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    bra       dp_done

dp_err3             puls      u
dp_done             puls      cc,d,x,y,u,pc
		    

INKEY               lda       <currPath           path #
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

FGETC               pshs      x,y
                    leas      -1,s
                    lda       <currPath
                    ldy       #1
                    tfr       s,x
                    os9       I$Read
                    lda       ,s
                    leas      1,s
                    puls      x,y,pc


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
; Loads CLUT from link, file, or built-in raw CLUT
clutload            pshs      u
                    lda       #0                  F$Load a=language, 0=any
                    leax      clutmod,pcr         try linking module
                    os9       F$Link
                    lbcc      cont@
                    lda       #0
                    leax      clutpath,pcr        try loading /dd/cmds/xtclut
                    os9       F$Load
                    lbcc      cont@
                    lda       #0
                    leax      clutmod,pcr         try loading xtclut from exec dir
                    os9       F$Load
                    lbcc      cont@
*                   **** All loads failed; use built-in raw CLUT
                    puls      u                   restore caller's original U
                    leay      rawclut,pcr         point to built-in raw CLUT
                    sty       <clutdata
                    rts
cont@               stu       <clutheader         save module header to unlink on exit
                    sty       <clutdata           save module data pointer
                    puls      u                   restore caller's original U
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

rawclut
                    fcb $00,$00,$00,$00,$00,$00,$80,$00,$00,$80,$00,$00,$00,$80,$80,$00
                    fcb $80,$00,$00,$00,$80,$00,$80,$00,$80,$80,$00,$00,$c0,$c0,$c0,$00
                    fcb $80,$80,$80,$00,$00,$00,$ff,$00,$00,$ff,$00,$00,$00,$ff,$ff,$00
                    fcb $ff,$00,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$00,$ff,$ff,$ff,$00
                    fcb $00,$00,$00,$00,$5f,$00,$00,$00,$87,$00,$00,$00,$af,$00,$00,$00
                    fcb $d7,$00,$00,$00,$ff,$00,$00,$00,$00,$5f,$00,$00,$5f,$5f,$00,$00
                    fcb $87,$5f,$00,$00,$af,$5f,$00,$00,$d7,$5f,$00,$00,$ff,$5f,$00,$00
                    fcb $00,$87,$00,$00,$5f,$87,$00,$00,$87,$87,$00,$00,$af,$87,$00,$00
                    fcb $d7,$87,$00,$00,$ff,$87,$00,$00,$00,$af,$00,$00,$5f,$af,$00,$00
                    fcb $87,$af,$00,$00,$af,$af,$00,$00,$d7,$af,$00,$00,$ff,$af,$00,$00
                    fcb $00,$d7,$00,$00,$5f,$d7,$00,$00,$87,$d7,$00,$00,$af,$d7,$00,$00
                    fcb $d7,$d7,$00,$00,$ff,$d7,$00,$00,$00,$ff,$00,$00,$5f,$ff,$00,$00
                    fcb $87,$ff,$00,$00,$af,$ff,$00,$00,$d7,$ff,$00,$00,$ff,$ff,$00,$00
                    fcb $00,$00,$5f,$00,$5f,$00,$5f,$00,$87,$00,$5f,$00,$af,$00,$5f,$00
                    fcb $d7,$00,$5f,$00,$ff,$00,$5f,$00,$00,$5f,$5f,$00,$5f,$5f,$5f,$00
                    fcb $87,$5f,$5f,$00,$af,$5f,$5f,$00,$d7,$5f,$5f,$00,$ff,$5f,$5f,$00
                    fcb $00,$87,$5f,$00,$5f,$87,$5f,$00,$87,$87,$5f,$00,$af,$87,$5f,$00
                    fcb $d7,$87,$5f,$00,$ff,$87,$5f,$00,$00,$af,$5f,$00,$5f,$af,$5f,$00
                    fcb $87,$af,$5f,$00,$af,$af,$5f,$00,$d7,$af,$5f,$00,$ff,$af,$5f,$00
                    fcb $00,$d7,$5f,$00,$5f,$d7,$5f,$00,$87,$d7,$5f,$00,$af,$d7,$5f,$00
                    fcb $d7,$d7,$5f,$00,$ff,$d7,$5f,$00,$00,$ff,$5f,$00,$5f,$ff,$5f,$00
                    fcb $87,$ff,$5f,$00,$af,$ff,$5f,$00,$d7,$ff,$5f,$00,$ff,$ff,$5f,$00
                    fcb $00,$00,$87,$00,$5f,$00,$87,$00,$87,$00,$87,$00,$af,$00,$87,$00
                    fcb $d7,$00,$87,$00,$ff,$00,$87,$00,$00,$5f,$87,$00,$5f,$5f,$87,$00
                    fcb $87,$5f,$87,$00,$af,$5f,$87,$00,$d7,$5f,$87,$00,$ff,$5f,$87,$00
                    fcb $00,$87,$87,$00,$5f,$87,$87,$00,$87,$87,$87,$00,$af,$87,$87,$00
                    fcb $d7,$87,$87,$00,$ff,$87,$87,$00,$00,$af,$87,$00,$5f,$af,$87,$00
                    fcb $87,$af,$87,$00,$af,$af,$87,$00,$d7,$af,$87,$00,$ff,$af,$87,$00
                    fcb $00,$d7,$87,$00,$5f,$d7,$87,$00,$87,$d7,$87,$00,$af,$d7,$87,$00
                    fcb $d7,$d7,$87,$00,$ff,$d7,$87,$00,$00,$ff,$87,$00,$5f,$ff,$87,$00
                    fcb $87,$ff,$87,$00,$af,$ff,$87,$00,$d7,$ff,$87,$00,$ff,$ff,$87,$00
                    fcb $00,$00,$af,$00,$5f,$00,$af,$00,$87,$00,$af,$00,$af,$00,$af,$00
                    fcb $d7,$00,$af,$00,$ff,$00,$af,$00,$00,$5f,$af,$00,$5f,$5f,$af,$00
                    fcb $87,$5f,$af,$00,$af,$5f,$af,$00,$d7,$5f,$af,$00,$ff,$5f,$af,$00
                    fcb $00,$87,$af,$00,$5f,$87,$af,$00,$87,$87,$af,$00,$af,$87,$af,$00
                    fcb $d7,$87,$af,$00,$ff,$87,$af,$00,$00,$af,$af,$00,$5f,$af,$af,$00
                    fcb $87,$af,$af,$00,$af,$af,$af,$00,$d7,$af,$af,$00,$ff,$af,$af,$00
                    fcb $00,$d7,$af,$00,$5f,$d7,$af,$00,$87,$d7,$af,$00,$af,$d7,$af,$00
                    fcb $d7,$d7,$af,$00,$ff,$d7,$af,$00,$00,$ff,$af,$00,$5f,$ff,$af,$00
                    fcb $87,$ff,$af,$00,$af,$ff,$af,$00,$d7,$ff,$af,$00,$ff,$ff,$af,$00
                    fcb $00,$00,$d7,$00,$5f,$00,$d7,$00,$87,$00,$d7,$00,$af,$00,$d7,$00
                    fcb $d7,$00,$d7,$00,$ff,$00,$d7,$00,$00,$5f,$d7,$00,$5f,$5f,$d7,$00
                    fcb $87,$5f,$d7,$00,$af,$5f,$d7,$00,$d7,$5f,$d7,$00,$ff,$5f,$d7,$00
                    fcb $00,$87,$d7,$00,$5f,$87,$d7,$00,$87,$87,$d7,$00,$af,$87,$d7,$00
                    fcb $d7,$87,$d7,$00,$ff,$87,$d7,$00,$00,$af,$d7,$00,$5f,$af,$d7,$00
                    fcb $87,$af,$d7,$00,$af,$af,$d7,$00,$d7,$af,$d7,$00,$ff,$af,$d7,$00
                    fcb $00,$d7,$d7,$00,$5f,$d7,$d7,$00,$87,$d7,$d7,$00,$af,$d7,$d7,$00
                    fcb $d7,$d7,$d7,$00,$ff,$d7,$d7,$00,$00,$ff,$d7,$00,$5f,$ff,$d7,$00
                    fcb $87,$ff,$d7,$00,$af,$ff,$d7,$00,$d7,$ff,$d7,$00,$ff,$ff,$d7,$00
                    fcb $00,$00,$ff,$00,$5f,$00,$ff,$00,$87,$00,$ff,$00,$af,$00,$ff,$00
                    fcb $d7,$00,$ff,$00,$ff,$00,$ff,$00,$00,$5f,$ff,$00,$5f,$5f,$ff,$00
                    fcb $87,$5f,$ff,$00,$af,$5f,$ff,$00,$d7,$5f,$ff,$00,$ff,$5f,$ff,$00
                    fcb $00,$87,$ff,$00,$5f,$87,$ff,$00,$87,$87,$ff,$00,$af,$87,$ff,$00
                    fcb $d7,$87,$ff,$00,$ff,$87,$ff,$00,$00,$af,$ff,$00,$5f,$af,$ff,$00
                    fcb $87,$af,$ff,$00,$af,$af,$ff,$00,$d7,$af,$ff,$00,$ff,$af,$ff,$00
                    fcb $00,$d7,$ff,$00,$5f,$d7,$ff,$00,$87,$d7,$ff,$00,$af,$d7,$ff,$00
                    fcb $d7,$d7,$ff,$00,$ff,$d7,$ff,$00,$00,$ff,$ff,$00,$5f,$ff,$ff,$00
                    fcb $87,$ff,$ff,$00,$af,$ff,$ff,$00,$d7,$ff,$ff,$00,$ff,$ff,$ff,$00
                    fcb $08,$08,$08,$00,$12,$12,$12,$00,$1c,$1c,$1c,$00,$26,$26,$26,$00
                    fcb $30,$30,$30,$00,$3a,$3a,$3a,$00,$44,$44,$44,$00,$4e,$4e,$4e,$00
                    fcb $58,$58,$58,$00,$62,$62,$62,$00,$6c,$6c,$6c,$00,$76,$76,$76,$00
                    fcb $80,$80,$80,$00,$8a,$8a,$8a,$00,$94,$94,$94,$00,$9e,$9e,$9e,$00
                    fcb $a8,$a8,$a8,$00,$b2,$b2,$b2,$00,$bc,$bc,$bc,$00,$c6,$c6,$c6,$00
                    fcb $d0,$d0,$d0,$00,$da,$da,$da,$00,$e4,$e4,$e4,$00,$ee,$ee,$ee,$00


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
                    ldx       <bmblock0           16-bit base block#
                    leax      a,x                 add relative block# (0-9)
                    tst       <pxlblk_active      is a block currently mapped?
                    beq       mapit@              if not, go map it
                    cmpx      <pxlblk_mapped      is this the currently mapped block?
                    beq       storepixel@         if current block, then just write the pixel
                    bsr       fclrblk             have a different mapped block, clear it
mapit@              stx       <pxlblk_mapped      store the new 16-bit block we will map
                    ldb       #1                  map 1 block
                    pshs      u                   push u (F$MapBlk returns address in u)
                    os9       F$MapBlk            Map the block
                    lbcc      mapgood@            if successful, finish
                    puls      u,x                 error, clean up and return
                    clr       <pxlblk_active
                    ldx       #$FFFF
                    stx       <pxlblk_mapped
                    bra       cleanup@            
mapgood@            stu       <pxlblkaddr         store the logical address
                    lda       #1
                    sta       <pxlblk_active      mark block as actively mapped
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
