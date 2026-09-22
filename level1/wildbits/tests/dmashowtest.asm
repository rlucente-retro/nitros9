********************************************************************
* dmashow - TinyVicky II Hardware DMA Engine Visual Demonstration
*
* Visually demonstrates:
*  1. Palette Setup: 256-color palette loaded to CLUT 0 via SS.DfPal
*  2. 1D Linear DMA Fill: Instantly clearing 76,800 bytes (320x240)
*  3. 2D Rectangular DMA Fill: Cascading colorful windows with stride 320
*  4. Real-Time 2D DMA Animation: Smooth 40x40 bouncing box at 30 fps
*  5. Text Overlay: NitrOS-9 shell text floats directly over graphics
*  6. Clean Exit: Restores text mode after 15 seconds or on any keypress
********************************************************************

                    nam       dmashowtest
                    ttl       DMA Engine Visual Demo

Level               set       2
                    ifp1
                    use       os9.d
                    use       scf.d
                    use       wildbits.d
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       4

* Explicit Hardware Register Equates
DMA_BASE_ADDR       equ       $FEC0
DMA_CTRL            equ       DMA_BASE_ADDR+DMA_CTRL_REG
DMA_STATUS          equ       DMA_BASE_ADDR+DMA_STATUS_REG
DMA_DATA_WRITE      equ       DMA_BASE_ADDR+DMA_DATA_2_WRITE
DMA_SRC_H           equ       DMA_BASE_ADDR+DMA_SOURCE_ADDR_H
DMA_SRC_M           equ       DMA_BASE_ADDR+DMA_SOURCE_ADDR_M
DMA_SRC_L           equ       DMA_BASE_ADDR+DMA_SOURCE_ADDR_L
DMA_DST_H           equ       DMA_BASE_ADDR+DMA_DEST_ADDR_H
DMA_DST_M           equ       DMA_BASE_ADDR+DMA_DEST_ADDR_M
DMA_DST_L           equ       DMA_BASE_ADDR+DMA_DEST_ADDR_L
DMA_SZ_1D_H         equ       DMA_BASE_ADDR+DMA_SIZE_1D_H
DMA_SZ_1D_M         equ       DMA_BASE_ADDR+DMA_SIZE_1D_M
DMA_SZ_1D_L         equ       DMA_BASE_ADDR+DMA_SIZE_1D_L
DMA_SZ_X_H          equ       DMA_BASE_ADDR+DMA_SIZE_X_H
DMA_SZ_X_L          equ       DMA_BASE_ADDR+DMA_SIZE_X_L
DMA_SZ_Y_H          equ       DMA_BASE_ADDR+DMA_SIZE_Y_H
DMA_SZ_Y_L          equ       DMA_BASE_ADDR+DMA_SIZE_Y_L
DMA_STRD_S_H        equ       DMA_BASE_ADDR+DMA_SRC_STRIDE_X_H
DMA_STRD_S_L        equ       DMA_BASE_ADDR+DMA_SRC_STRIDE_X_L
DMA_STRD_D_H        equ       DMA_BASE_ADDR+DMA_DST_STRIDE_Y_H
DMA_STRD_D_L        equ       DMA_BASE_ADDR+DMA_DST_STRIDE_Y_L

                    mod       eom,name,tylg,atrv,start,size

                    ORG       0
saved_u             rmb       2                   saved static data register U
bmblock             rmb       1                   physical starting block of bitmap 0
bm_phys_h           rmb       1                   24-bit physical base address of BM0
bm_phys_m           rmb       1
bm_phys_l           rmb       1
abort_flag          rmb       1
box_x               rmb       2
box_y               rmb       2
box_dx              rmb       2
box_dy              rmb       2
frames_left         rmb       2
temp_buf            rmb       16
saved_eko           rmb       1
saved_int           rmb       1
saved_qut           rmb       1
popts               rmb       32
                    rmb       256                 stack
size                equ       .

name                fcs       /dmashowtest/
                    fcb       edition

start               equ       *
                    stu       <saved_u            save static register U immediately!
                    clr       <abort_flag

* Set up Signal Intercept Handler (F$Icpt)
                    leax      SigHandler,pcr
                    os9       F$Icpt

* Acquire terminal ownership so keydrv_ps2 directs signals to us (sets V.LPRC)
                    clra                          path 0 (stdin)
                    ldy       #0                  0 bytes
                    os9       I$Read
                    lda       #1                  path 1 (stdout)
                    ldy       #0                  0 bytes
                    os9       I$Write

* Save terminal options and set raw input (echo off, break off)
                    leax      <popts,u
                    clra                          path 0
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       optsdone@
                    lda       4,x                 save original echo
                    sta       <saved_eko
                    clr       4,x                 echo off
                    lda       16,x                save original interrupt char (Ctrl-C)
                    sta       <saved_int
                    clr       16,x                interrupt char off (deliver as $03)
                    lda       17,x                save original quit char (Ctrl-E / ESC)
                    sta       <saved_qut
                    clr       17,x                quit char off (deliver as $05)
                    clra                          path 0
                    ldb       #SS.Opt
                    os9       I$SetStt
optsdone@

* ====================================================================
* Step 1: Allocate Bitmap 0 (320x240, 76,800 bytes)
* ====================================================================
                    ldy       #0                  bitmap #0
                    ldx       #0                  screentype = 320x240
                    lda       #0                  path (stdin)
                    ldb       #SS.AScrn
                    os9       I$SetStt
                    bcc       AllocOk
                    cmpb      #E$WADef            already defined?
                    lbne      ExitErr

AllocOk             ldu       <saved_u            restore static U corrupted by SS.AScrn!
                    tfr       x,d                 B = physical starting block
                    stb       <bmblock

* Compute 24-bit physical address: block * 8192 (block << 13)
                    tfr       b,a
                    lsra
                    lsra
                    lsra
                    sta       <bm_phys_h          phys 23:16 = block >> 3

                    tfr       b,a
                    asla
                    asla
                    asla
                    asla
                    asla
                    sta       <bm_phys_m          phys 15:8 = (block << 5) & $E0
                    clr       <bm_phys_l          phys 7:0 = $00

* ====================================================================
* Step 2: Set CLUT 0 by mapping Block $C1 into Slot 1 ($2000-$3FFF)
* ====================================================================
                    orcc      #IntMasks
                    lda       >MMU_MEM_CTRL
                    pshs      a

* Configure Edit LUT = Active LUT so slot write affects running address space
                    tfr       a,b
                    andb      #$03                B = active LUT
                    lslb
                    lslb
                    lslb
                    lslb                          B = active LUT << 4
                    anda      #$CF                clear edit LUT bits
                    pshs      b
                    ora       ,s+
                    sta       >MMU_MEM_CTRL

* Save original block in Slot 1 and map Block $C1
                    ldb       >MMU_SLOT_1
                    pshs      b
                    lda       #$C1                Block $C1 (Fonts & CLUTs)
                    sta       >MMU_SLOT_1

* CLUT 0 is at offset $1000 in Block $C1 -> $2000 + $1000 = $3000
                    ldx       #$3000
                    lbsr      InitClutDirect

* Restore original block in Slot 1 and MMU_MEM_CTRL
                    puls      b
                    stb       >MMU_SLOT_1
                    puls      a
                    sta       >MMU_MEM_CTRL
                    andcc     #^IntMasks

* ====================================================================
* Step 3: Assign CLUT 0 to BM0 and place BM0 on Layer 0
* ====================================================================
                    ldx       #0                  clut #0
                    ldy       #0                  bitmap #0
                    lda       #0
                    ldb       #SS.Palet
                    os9       I$SetStt

                    ldx       #0                  layer #0
                    ldy       #0                  bitmap #0
                    lda       #0
                    ldb       #SS.PScrn
                    os9       I$SetStt

* ====================================================================
* Step 4: DEMO 1 - 1D Linear DMA Fill (Full Screen clear to dark slate)
* ====================================================================
* 76,800 bytes = $012C00
                    lda       <bm_phys_h
                    sta       >DMA_DST_H
                    lda       <bm_phys_m
                    sta       >DMA_DST_M
                    lda       <bm_phys_l
                    sta       >DMA_DST_L

                    lda       #24                 color index 24 (deep slate blue)
                    sta       >DMA_DATA_WRITE

                    clr       >DMA_SZ_Y_H         clear live 2D register before 1D transfer
                    lda       #$01                size = $012C00 (76,800 bytes)
                    sta       >DMA_SZ_1D_H
                    lda       #$2C
                    sta       >DMA_SZ_1D_M
                    clr       >DMA_SZ_1D_L

                    lda       #DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      TriggerDma

* ====================================================================
* Step 5: DEMO 2 - 2D Rectangular DMA Fill (Cascading Windows with Stride)
* ====================================================================
* Draw 5 overlapping colored rectangular windows across the 320-pitch canvas:
                    ldx       #20
                    ldy       #30
                    lda       #45                 Cyan
                    lbsr      DmaFillRect

                    ldx       #50
                    ldy       #50
                    lda       #95                 Green
                    lbsr      DmaFillRect

                    ldx       #80
                    ldy       #70
                    lda       #145                Gold
                    lbsr      DmaFillRect

                    ldx       #110
                    ldy       #90
                    lda       #175                Orange
                    lbsr      DmaFillRect

                    ldx       #140
                    ldy       #110
                    lda       #235                Magenta
                    lbsr      DmaFillRect

* ====================================================================
* Step 6: Turn on Graphics with Text Overlay
* ====================================================================
                    ldx       #FX_BM+FX_GRF+FX_OVR+FX_TXT
                    ldy       #FT_OMIT
                    lda       #0
                    ldb       #SS.DScrn
                    os9       I$SetStt

* Print banner on overlaid text screen
                    leax      msg_header,pcr
                    lbsr      PrintStr

* ====================================================================
* Step 7: DEMO 3 - Real-Time 2D DMA Animation (Bouncing 40x40 Block)
* ====================================================================
                    ldd       #180
                    std       <box_x
                    ldd       #130
                    std       <box_y
                    ldd       #2
                    std       <box_dx
                    ldd       #1
                    std       <box_dy
                    ldd       #900                900 loops (15 seconds at 60 fps)
                    std       <frames_left

AnimLoop            lda       <abort_flag
                    lbne      CleanExit

* Poll stdin for any keypress
                    clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       no_key
                    clra                          path 0
                    leax      <temp_buf,u
                    ldy       #1
                    os9       I$Read
                    bcs       no_key
                    lda       ,x
                    cmpa      #$0D                CR?
                    beq       no_key              ignore leftover enter
                    cmpa      #$0A                LF?
                    beq       no_key              ignore leftover linefeed
                    lbra      CleanExit           any key exits!
no_key

* Erase old box at (box_x, box_y): 40x40 with background color 24
                    ldx       <box_x
                    ldy       <box_y
                    lda       #24
                    lbsr      DmaFillBox

* Update box_x
                    ldd       <box_x
                    addd      <box_dx
                    std       <box_x
                    cmpd      #10
                    bge       bx_hi
                    ldd       #2
                    std       <box_dx
                    bra       by_up
bx_hi               cmpd      #270
                    ble       by_up
                    ldd       #-2
                    std       <box_dx

* Update box_y
by_up               ldd       <box_y
                    addd      <box_dy
                    std       <box_y
                    cmpd      #20
                    bge       by_hi
                    ldd       #1
                    std       <box_dy
                    bra       draw_box
by_hi               cmpd      #190
                    ble       draw_box
                    ldd       #-1
                    std       <box_dy

* Draw new box at (box_x, box_y): 40x40 with bright red color 205
draw_box            ldx       <box_x
                    ldy       <box_y
                    lda       #205
                    lbsr      DmaFillBox

* Sleep 2 ticks (~30 fps frame pacing)
                    ldx       #2
                    os9       F$Sleep

                    ldd       <frames_left
                    subd      #1
                    std       <frames_left
                    lbne      AnimLoop

* ====================================================================
* Clean Exit: Restore Text Mode, Flush Keys, and Free Screen RAM
* ====================================================================
CleanExit           ldx       #0                  de-register intercept
                    os9       F$Icpt

* Flush any pending keyboard input
FlushKeys           clra                          path 0
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       DoneFlush
                    leax      <temp_buf,u
                    ldy       #1
                    os9       I$Read
                    bra       FlushKeys
DoneFlush

* Clear text screen and restore pure text mode
                    leax      msg_clr,pcr
                    lbsr      PrintStr

* Restore terminal options
                    leax      <popts,u
                    clra                          path 0
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       restoredone@
                    lda       <saved_eko
                    sta       4,x
                    lda       <saved_int
                    sta       16,x
                    lda       <saved_qut
                    sta       17,x
                    clra                          path 0
                    ldb       #SS.Opt
                    os9       I$SetStt
restoredone@

                    ldx       #FX_TXT
                    ldy       #FT_OMIT
                    lda       #0
                    ldb       #SS.DScrn
                    os9       I$SetStt

                    ldy       #0                  bitmap 0
                    lda       #0
                    ldb       #SS.FScrn
                    os9       I$SetStt

                    clrb
                    os9       F$Exit

ExitErr             ldb       #1
                    os9       F$Exit

* --------------------------------------------------------------------
* DmaFillRect: Draw an 80x50 filled rectangle at (X, Y) with color A
* --------------------------------------------------------------------
DmaFillRect         pshs      a,x,y
                    sta       >DMA_DATA_WRITE

                    lbsr      CalcPixelPhys
                    sta       >DMA_DST_H
                    stb       >DMA_DST_M
                    lda       <temp_buf
                    sta       >DMA_DST_L

                    clr       >DMA_SZ_X_H
                    lda       #80                 Width = 80 pixels
                    sta       >DMA_SZ_X_L

                    clr       >DMA_SZ_Y_H
                    lda       #50                 Height = 50 rows
                    sta       >DMA_SZ_Y_L

                    lda       #1                  Destination & Source Stride = 320 ($0140)
                    sta       >DMA_STRD_D_H
                    sta       >DMA_STRD_S_H
                    lda       #$40
                    sta       >DMA_STRD_D_L
                    sta       >DMA_STRD_S_L

                    lda       #DMA_CTRL_1D_2D+DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      TriggerDma

                    puls      a,x,y,pc

* --------------------------------------------------------------------
* DmaFillBox: Draw a 40x40 filled rectangle at (X, Y) with color A
* --------------------------------------------------------------------
DmaFillBox          pshs      a,x,y
                    sta       >DMA_DATA_WRITE

                    lbsr      CalcPixelPhys
                    sta       >DMA_DST_H
                    stb       >DMA_DST_M
                    lda       <temp_buf
                    sta       >DMA_DST_L

                    clr       >DMA_SZ_X_H
                    lda       #40                 Width = 40 pixels
                    sta       >DMA_SZ_X_L

                    clr       >DMA_SZ_Y_H
                    lda       #40                 Height = 40 rows
                    sta       >DMA_SZ_Y_L

                    lda       #1                  Destination & Source Stride = 320 ($0140)
                    sta       >DMA_STRD_D_H
                    sta       >DMA_STRD_S_H
                    lda       #$40
                    sta       >DMA_STRD_D_L
                    sta       >DMA_STRD_S_L

                    lda       #DMA_CTRL_1D_2D+DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      TriggerDma

                    puls      a,x,y,pc

* --------------------------------------------------------------------
* TriggerDma: Hardware-safe DMA transfer execution
* Entry: A = DMA_CTRL mode bits (DMA_CTRL_Enable included, Start_Trf=0)
* Ensures:
*  1. DMA_CTRL_Enable is active BEFORE Start_Trf goes high
*  2. Clean 0 -> 1 rising edge on Start_Trf
*  3. Waits for transfer completion (DMA_STATUS_TRF_IP clears)
*  4. Clears Start_Trf back to 0 so next transfer can trigger cleanly
* --------------------------------------------------------------------
TriggerDma          pshs      a
                    sta       >DMA_CTRL           write mode + enable (Start_Trf=0)
                    ora       #DMA_CTRL_Start_Trf strobe rising edge on Start_Trf
                    sta       >DMA_CTRL

td_wait             lda       >DMA_STATUS
                    bita      #DMA_STATUS_TRF_IP
                    bne       td_wait

                    puls      a                   restore mode + enable (Start_Trf=0)
                    sta       >DMA_CTRL           clear Start_Trf back to 0!
                    rts

* --------------------------------------------------------------------
* CalcPixelPhys: Calculate 24-bit physical address for (X, Y) on BM0
* Input: X = col (0..319), Y = row (0..239)
* Returns: A = Phys[23:16], B = Phys[15:8], temp_buf = Phys[7:0]
* Formula: Offset = Y * 320 + X = Y * 256 + Y * 64 + X
* --------------------------------------------------------------------
CalcPixelPhys       pshs      x,y,u
                    tfr       x,u                 save X in U
                    tfr       y,d                 B = Y low byte
                    lda       #64
                    mul                           D = Y * 64
                    pshs      d                   save (Y * 64)

                    tfr       y,d                 B = Y
                    clra
                    tfr       b,a                 D = Y * 256
                    clrb
                    addd      ,s++                D = Y * 320
                    tfr       u,x                 X = original X
                    leax      d,x                 X = Y * 320 + X

* Add 16-bit offset in X to 24-bit base (bm_phys_h, bm_phys_m, bm_phys_l)
                    tfr       x,d                 A = off_hi, B = off_lo
                    stb       <temp_buf           temp_buf = Phys[7:0]

                    adda      <bm_phys_m          A = bm_phys_m + off_hi
                    tfr       a,b                 B = Phys[15:8]
                    lda       <bm_phys_h          A = Phys[23:16]
                    bcc       cpp_done
                    inca                          propagate carry
cpp_done            puls      x,y,u,pc

* --------------------------------------------------------------------
* InitClutDirect: Build 256-color palette directly in CLUT 0
* Entry: X = pointer to CLUT 0 ($1000 in mapped Block $C1)
* Format: 4 bytes per color: [Blue, Green, Red, 0]
* --------------------------------------------------------------------
InitClutDirect      pshs      x,y
                    clrb                          B = index (0..255)
ic_lp               stb       ,x                  Blue = index
                    pshs      b
                    lslb
                    stb       1,x                 Green = index * 2
                    puls      b
                    tfr       b,a
                    coma
                    sta       2,x                 Red = 255 - index
                    clr       3,x                 Alpha = 0
                    leax      4,x
                    incb
                    bne       ic_lp

* Explicit overrides for vibrant demo colors:
                    ldx       ,s                  restore CLUT 0 base pointer
* Color 24 (Background): Deep Slate Blue (B=80, G=30, R=20)
                    leax      (24*4),x
                    lda       #80
                    sta       ,x
                    lda       #30
                    sta       1,x
                    lda       #20
                    sta       2,x

* Color 45 (Window 1): Cyan (B=240, G=220, R=0)
                    ldx       ,s
                    leax      (45*4),x
                    lda       #240
                    sta       ,x
                    lda       #220
                    sta       1,x
                    clr       2,x

* Color 95 (Window 2): Bright Green (B=50, G=240, R=40)
                    ldx       ,s
                    leax      (95*4),x
                    lda       #50
                    sta       ,x
                    lda       #240
                    sta       1,x
                    lda       #40
                    sta       2,x

* Color 145 (Window 3): Gold/Yellow (B=20, G=215, R=255)
                    ldx       ,s
                    leax      (145*4),x
                    lda       #20
                    sta       ,x
                    lda       #215
                    sta       1,x
                    lda       #255
                    sta       2,x

* Color 175 (Window 4): Orange (B=0, G=128, R=255)
                    ldx       ,s
                    leax      (175*4),x
                    clr       ,x
                    lda       #128
                    sta       1,x
                    lda       #255
                    sta       2,x

* Color 205 (Box / Window 5): Vivid Red (B=30, G=30, R=250)
                    ldx       ,s
                    leax      (205*4),x
                    lda       #30
                    sta       ,x
                    sta       1,x
                    lda       #250
                    sta       2,x

* Color 235 (Window 6): Magenta (B=220, G=30, R=240)
                    ldx       ,s
                    leax      (235*4),x
                    lda       #220
                    sta       ,x
                    lda       #30
                    sta       1,x
                    lda       #240
                    sta       2,x

                    puls      x,y,pc

* --------------------------------------------------------------------
* Signal Handler
* --------------------------------------------------------------------
SigHandler          inc       <abort_flag
                    rti

* --------------------------------------------------------------------
* Print Subroutines
* --------------------------------------------------------------------
PrintStr            pshs      a,y
ps_lp               lda       ,x+
                    beq       ps_done
                    lbsr      PrintChar
                    bra       ps_lp
ps_done             puls      a,y,pc

PrintChar           pshs      a,x,y
                    sta       <temp_buf
                    lda       #1                  stdout
                    leax      <temp_buf,u
                    ldy       #1
                    os9       I$Write
                    puls      a,x,y,pc

* --------------------------------------------------------------------
* Message Strings
* --------------------------------------------------------------------
msg_header          fcb       $0C                 Clear Screen
                    fcb       C$CR,$0A
                    fcc       "================================================================================"
                    fcb       C$CR,$0A
                    fcc       "         TINYVICKY II HARDWARE 1D / 2D DMA ENGINE DEMONSTRATION"
                    fcb       C$CR,$0A
                    fcc       "================================================================================"
                    fcb       C$CR,$0A
                    fcc       "  * 1D Linear DMA Fill : Instantly cleared 76.8 KB bitmap canvas"
                    fcb       C$CR,$0A
                    fcc       "  * 2D Stride DMA Fill : 5 Cascading graphic windows rendered with stride 320"
                    fcb       C$CR,$0A
                    fcc       "  * 2D Real-Time Blit  : Smooth 40x40 hardware bouncing box @ 60 fps"
                    fcb       C$CR,$0A
                    fcc       "  * Text Overlay Mode  : NitrOS-9 console text floating directly over graphics"
                    fcb       C$CR,$0A
                    fcb       C$CR,$0A
                    fcc       "  -> Press ESC, Space, or any key to exit (or auto-exits in 15 seconds)..."
                    fcb       C$CR,$0A,0

msg_clr             fcb       $0C,0               Clear screen on exit

                    emod
eom                 equ       *
                    end
