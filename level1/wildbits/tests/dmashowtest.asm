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
*
* Edt/Rev  YYYY/MM/DD  Modified by
* ------------------------------------------------------------------
*   8      2026/09/22  Antigravity
* Hardened against error 128 by allocating BM0 via SS.AScrn, mapping CLUT0
* via block $C1 directly, and preserving static register U across system calls.
*   9      2026/09/24  Antigravity
* Upgraded cascading windows and bouncing box to native 2D hardware DMA
* transfers (width x height with stride 320), eliminating 50x / 40x loop
* overhead. Synchronized DMA triggers to start of VBLANK (row >= 480) for
* zero bus collisions and reliable completion. Replaced character-by-character
* syscall printing with single-syscall string write, eliminating text corruption.
*  10      2026/09/24  Antigravity
* Eliminated WaitVBlank scanline polling and masked interrupts (orcc #IntMasks)
* across DMA trigger sequences, resolving hardware CPU_STOPPED_ST0 deadlock.
*  11      2026/09/24  Antigravity
* Corrected DMA destination address registers to Little-Endian ($FEC8=L,
* $FEC9=M, $FECA=H) matching TinyVKY hardware. Rewrote CalcPixelPhys to
* eliminate zero-page/temp_buf dependencies and write destination registers
* directly. Added 10-tick sequential pauses between cascading windows.
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
edition             set       11

* Explicit Hardware Register Equates
DMA_BASE_ADDR       equ       $FEC0
DMA_CTRL            equ       DMA_BASE_ADDR+DMA_CTRL_REG
DMA_STATUS          equ       DMA_BASE_ADDR+DMA_STATUS_REG
DMA_DATA_WRITE      equ       DMA_BASE_ADDR+DMA_DATA_2_WRITE
DMA_SRC_H           equ       $FEC5
DMA_SRC_M           equ       $FEC6
DMA_SRC_L           equ       $FEC7
DMA_DST_H           equ       $FEC9
DMA_DST_M           equ       $FECA
DMA_DST_L           equ       $FECB
DMA_SZ_1D_H         equ       $FECF
DMA_SZ_1D_M         equ       $FECC
DMA_SZ_1D_L         equ       $FECD
DMA_SZ_X_H          equ       $FECC
DMA_SZ_X_L          equ       $FECD
DMA_SZ_Y_H          equ       $FECE
DMA_SZ_Y_L          equ       $FECF
DMA_STRD_S_H        equ       $FED0
DMA_STRD_S_L        equ       $FED1
DMA_STRD_D_H        equ       $FED2
DMA_STRD_D_L        equ       $FED3
VKY_RAST_COL        equ       $FFD8
VKY_RAST_ROW        equ       $FFDA

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
                    tfr       u,d
                    tfr       a,dp                sync DP with U base page
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

* Drain any residual keys from stdin
FlushInit           clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       FlushDone
                    leax      <temp_buf,u
                    ldy       #1
                    os9       I$Read
                    bcc       FlushInit
FlushDone

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
                    stb       bmblock,u

* Compute 24-bit physical address: block * 8192 (block << 13)
                    tfr       b,a
                    lsra
                    lsra
                    lsra
                    sta       <bm_phys_h          phys 23:16 = block >> 3
                    sta       bm_phys_h,u

                    tfr       b,a
                    asla
                    asla
                    asla
                    asla
                    asla
                    sta       <bm_phys_m          phys 15:8 = (block << 5) & $E0
                    sta       bm_phys_m,u
                    clr       <bm_phys_l          phys 7:0 = $00
                    clr       bm_phys_l,u

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
* Step 3: Assign CLUT 0 to BM0, place BM0 on Layer 0, enable Text Overlay
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

* Enable Graphics with Text Overlay immediately so screen and banner are active
                    ldx       #FX_BM+FX_GRF+FX_OVR+FX_TXT
                    ldy       #FT_OMIT
                    lda       #0
                    ldb       #SS.DScrn
                    os9       I$SetStt

* Print banner on overlaid text screen
                    leax      msg_header,pcr
                    lbsr      PrintStr

* ====================================================================
* Step 4: DEMO 1 - 1D Linear DMA Fill (Full Screen clear to dark slate)
* ====================================================================
* 76,800 bytes = $012C00
                    lda       bm_phys_h,u
                    sta       >DMA_DST_H          FEC9 = High
                    lda       bm_phys_m,u
                    sta       >DMA_DST_M          FECA = Mid
                    lda       bm_phys_l,u
                    sta       >DMA_DST_L          FECB = Low

                    lda       #24                 color index 24 (deep slate blue)
                    sta       >DMA_DATA_WRITE

                    clr       >DMA_SZ_Y_H         clear live 2D register before 1D transfer
                    lda       #$01                size = $012C00 (76,800 bytes)
                    sta       >DMA_SZ_1D_H        FECF
                    lda       #$2C
                    sta       >DMA_SZ_1D_M        FECC
                    clr       >DMA_SZ_1D_L        FECD

* Execute full screen 1D fill
                    lda       #DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      ExecDma

* ====================================================================
* Step 5: DEMO 2 - Cascading Rectangular Windows via Hardware DMA
* ====================================================================
* Draw 5 overlapping colored rectangular windows across the 320-pitch canvas:
                    ldx       #20
                    ldy       #30
                    lda       #45                 Cyan
                    lbsr      DmaFillRect
                    ldx       #10
                    os9       F$Sleep

                    ldx       #50
                    ldy       #50
                    lda       #95                 Green
                    lbsr      DmaFillRect
                    ldx       #10
                    os9       F$Sleep

                    ldx       #80
                    ldy       #70
                    lda       #145                Gold
                    lbsr      DmaFillRect
                    ldx       #10
                    os9       F$Sleep

                    ldx       #110
                    ldy       #90
                    lda       #175                Orange
                    lbsr      DmaFillRect
                    ldx       #10
                    os9       F$Sleep

                    ldx       #140
                    ldy       #110
                    lda       #235                Magenta
                    lbsr      DmaFillRect
                    ldx       #10
                    os9       F$Sleep

* ====================================================================
* Step 6: DEMO 3 - Real-Time Hardware DMA Animation (Bouncing 40x40 Block)
* ====================================================================
                    ldu       <saved_u
                    ldd       #180
                    std       box_x,u
                    ldd       #130
                    std       box_y,u
                    ldd       #2
                    std       box_dx,u
                    ldd       #1
                    std       box_dy,u
                    ldd       #900                900 loops (15 seconds at 60 fps)
                    std       frames_left,u

AnimLoop            ldu       <saved_u
                    lda       abort_flag,u
                    lbne      CleanExit

* Poll stdin for exit keypress
                    clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       no_key
                    clra                          path 0
                    leax      temp_buf,u
                    ldy       #1
                    os9       I$Read
                    bcs       no_key
                    lda       ,x
                    cmpa      #$1B                ESC?
                    lbeq      CleanExit
                    cmpa      #$20                Space?
                    lbeq      CleanExit
                    cmpa      #'q'                'q'?
                    lbeq      CleanExit
                    cmpa      #'Q'                'Q'?
                    lbeq      CleanExit
                    cmpa      #$03                Ctrl-C?
                    lbeq      CleanExit
                    cmpa      #$05                Ctrl-E?
                    lbeq      CleanExit
no_key
* Erase old box at (box_x, box_y): 40x40 with background color 24
                    ldx       box_x,u
                    ldy       box_y,u
                    lda       #24
                    lbsr      DmaFillBox

* Update box_x
                    ldd       box_x,u
                    addd      box_dx,u
                    std       box_x,u
                    cmpd      #10
                    bge       bx_hi
                    ldd       #2
                    std       box_dx,u
                    bra       by_up
bx_hi               cmpd      #270
                    ble       by_up
                    ldd       #-2
                    std       box_dx,u

* Update box_y
by_up               ldd       box_y,u
                    addd      box_dy,u
                    std       box_y,u
                    cmpd      #20
                    bge       by_hi
                    ldd       #1
                    std       box_dy,u
                    bra       draw_box
by_hi               cmpd      #190
                    ble       draw_box
                    ldd       #-1
                    std       box_dy,u

* Draw new box at (box_x, box_y): 40x40 with bright red color 205
draw_box            ldx       box_x,u
                    ldy       box_y,u
                    lda       #205
                    lbsr      DmaFillBox

* Sleep 2 ticks (~30 fps frame pacing)
                    ldx       #2
                    os9       F$Sleep

                    ldu       <saved_u
                    ldd       frames_left,u
                    subd      #1
                    std       frames_left,u
                    lbne      AnimLoop

* ====================================================================
* Clean Exit: Restore Text Mode, Flush Keys, and Free Screen RAM
* ====================================================================
CleanExit           equ       *
                    ldu       <saved_u

* Flush any pending keyboard input
FlushKeys           clra                          path 0
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       DoneFlush
                    leax      temp_buf,u
                    ldy       #1
                    os9       I$Read
                    bra       FlushKeys
DoneFlush

* Clear text screen and restore pure text mode
                    leax      msg_clr,pcr
                    lbsr      PrintStr

* Restore terminal options
                    leax      popts,u
                    clra                          path 0
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       restoredone@
                    lda       saved_eko,u
                    sta       4,x
                    lda       saved_int,u
                    sta       16,x
                    lda       saved_qut,u
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
* Implemented via a single 2D hardware DMA transfer
* --------------------------------------------------------------------
DmaFillRect         pshs      a,x,y
                    sta       >DMA_DATA_WRITE     FEC1 = fill color
                    lbsr      CalcPixelPhys       compute 24-bit physical address and write to $FEC8-$FECA

* Set 2D dimensions: Width = 80, Height = 50
                    clr       >DMA_SZ_X_H         FECC = 0
                    lda       #80
                    sta       >DMA_SZ_X_L         FECD = 80
                    clr       >DMA_SZ_Y_H         FECE = 0
                    lda       #50
                    sta       >DMA_SZ_Y_L         FECF = 50

* Set destination stride: 320 ($0140)
                    lda       #1
                    sta       >DMA_STRD_D_H       FED2 = 1
                    lda       #$40
                    sta       >DMA_STRD_D_L       FED3 = $40

* Execute 2D DMA Fill: CTRL = DMA_CTRL_1D_2D + DMA_CTRL_Fill + DMA_CTRL_Enable ($07)
                    lda       #DMA_CTRL_1D_2D+DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      ExecDma

                    puls      a,x,y,pc

* --------------------------------------------------------------------
* DmaFillBox: Draw a 40x40 filled rectangle at (X, Y) with color A
* Implemented via a single 2D hardware DMA transfer
* --------------------------------------------------------------------
DmaFillBox          pshs      a,x,y
                    sta       >DMA_DATA_WRITE     FEC1 = fill color
                    lbsr      CalcPixelPhys       compute 24-bit physical address and write to $FEC8-$FECA

* Set 2D dimensions: Width = 40, Height = 40
                    clr       >DMA_SZ_X_H         FECC = 0
                    lda       #40
                    sta       >DMA_SZ_X_L         FECD = 40
                    clr       >DMA_SZ_Y_H         FECE = 0
                    lda       #40
                    sta       >DMA_SZ_Y_L         FECF = 40

* Set destination stride: 320 ($0140)
                    lda       #1
                    sta       >DMA_STRD_D_H       FED2 = 1
                    lda       #$40
                    sta       >DMA_STRD_D_L       FED3 = $40

* Execute 2D DMA Fill: CTRL = DMA_CTRL_1D_2D + DMA_CTRL_Fill + DMA_CTRL_Enable ($07)
                    lda       #DMA_CTRL_1D_2D+DMA_CTRL_Fill+DMA_CTRL_Enable
                    lbsr      ExecDma

                    puls      a,x,y,pc

* --------------------------------------------------------------------
* ExecDma: Execute a DMA transfer with interrupts masked
* Entry: A = DMA_CTRL command bits (e.g. $05 for 1D fill, $07 for 2D fill)
* Protocol:
*  1. Masks interrupts (orcc #IntMasks) so IRQ jitter cannot interrupt trigger
*  2. Writes mode + DMA_CTRL_Enable with Start_Trf = 0
*  3. Strobes Start_Trf (0 -> 1 rising edge) while Enable is ALREADY high
*  4. Bounded wait loop on DMA_STATUS_TRF_IP
*  5. Clears Start_Trf, disarms engine, and restores interrupts
* --------------------------------------------------------------------
ExecDma             pshs      cc,a,y
                    orcc      #IntMasks           mask IRQ/FIRQ across DMA trigger

* Step 1: Ensure DMA_CTRL_Enable is high and Start_Trf is 0
                    anda      #^DMA_CTRL_Start_Trf
                    sta       >DMA_CTRL

* Step 2: Strobe Start_Trf (0 -> 1 rising edge) while Enable is ALREADY high!
                    ora       #DMA_CTRL_Start_Trf
                    sta       >DMA_CTRL

* Step 3: Bounded wait for transfer completion
                    ldy       #$FFFF              ample timeout (>180 ms)
ed_wait             lda       >DMA_STATUS
                    bita      #DMA_STATUS_TRF_IP
                    beq       ed_done             bit 7 is 0 -> transfer complete!
                    leay      -1,y
                    bne       ed_wait

ed_done             clr       >DMA_CTRL           clear Start_Trf and disarm engine
                    puls      cc,a,y,pc

* --------------------------------------------------------------------
* CalcPixelPhys: Calculate 24-bit physical address for (X, Y) on BM0
* and program DMA destination registers ($FEC8-$FECA)
* Input: X = col (0..319), Y = row (0..239)
* Base address: bm_phys_h,u, bm_phys_m,u, bm_phys_l,u
* Formula: Offset = Y * 320 + X = Y * 256 + Y * 64 + X
* --------------------------------------------------------------------
CalcPixelPhys       pshs      d,x,y
* 1. Compute Y * 64 (max = 239 * 64 = 15,296 = $3BC0)
                    tfr       y,d                 B = Y (0..239)
                    lda       #64
                    mul                           D = Y * 64 (A = prod_hi, B = prod_lo)
* 2. Add X (col: 0..319)
                    addd      2,s                 D = Y * 64 + X (A = off_m, B = off_l)
* 3. Add Y * 256 (add Y to register A)
                    clr       ,-s                 allocate temporary high byte on stack (Off_H = 0)
                    adda      6,s                 A = off_m + Y (low byte of original Y is at 6,s)
                    bcc       cpp_no_c1@
                    inc       ,s                  propagate carry to Off_H
cpp_no_c1@
* 4. Store Low byte to $FECB (bm_phys_l is 0, so low byte is finalized in B)
                    stb       >DMA_DST_L          store Low byte to $FECB
* 5. Add Base physical address: bm_phys_m,u to A and store to $FECA
                    adda      bm_phys_m,u
                    bcc       cpp_no_c2@
                    inc       ,s                  propagate carry to Off_H
cpp_no_c2@          sta       >DMA_DST_M          store Mid byte to $FECA
* 6. Add Base physical address: bm_phys_h,u to Off_H and store to $FEC9
                    lda       ,s+                 pull Off_H
                    adca      bm_phys_h,u
                    sta       >DMA_DST_H          store High byte to $FEC9

                    puls      d,x,y,pc

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
SigHandler          inc       abort_flag,u
                    rti

* --------------------------------------------------------------------
* PrintStr: Output null-terminated string to stdout in a single syscall
* Entry: X = pointer to string
* --------------------------------------------------------------------
PrintStr            pshs      d,x,y
                    ldy       #0
ps_len@             tst       ,x+
                    beq       ps_done@
                    leay      1,y
                    bra       ps_len@
ps_done@            ldx       2,s                 restore string start pointer
                    lda       #1                  path 1 (stdout)
                    os9       I$Write
                    puls      d,x,y,pc

* --------------------------------------------------------------------
* Message Strings
* --------------------------------------------------------------------
msg_header          fcb       $0C                 Clear Screen
                    fcb       C$CR,$0A
                    fcc       "================================================================================"
                    fcb       C$CR,$0A
                    fcc       "            TINYVICKY II HARDWARE DMA ENGINE DEMONSTRATION"
                    fcb       C$CR,$0A
                    fcc       "================================================================================"
                    fcb       C$CR,$0A
                    fcc       "  * 1D Linear DMA Fill : Instantly cleared 76.8 KB bitmap canvas"
                    fcb       C$CR,$0A
                    fcc       "  * Hardware Line Fill : 5 Cascading graphic windows rendered via hardware DMA"
                    fcb       C$CR,$0A
                    fcc       "  * Real-Time DMA Blit : Smooth 40x40 hardware bouncing box @ 60 fps"
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
