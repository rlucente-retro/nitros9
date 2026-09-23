********************************************************************
* TLTest - TinyVicky Hardware Tilemap Test
*
* Demonstrates and tests the TinyVicky II hardware scrolling tilemap
* engine on Wildbits Jr2 (FNX6809 core).
*
* Allocates and initializes:
*  - Two 16x16 pixel tiles in a page-aligned buffer in system SRAM
*    (Tile 0 = transparent, Tile 1 = cyan box with red border,
*     Tile 2 = navy box with gold diagonal lattice).
*  - Dedicated 5-color palette loaded into GRPH_LUT1 (leaving shell
*    palette in LUT0 undisturbed).
*  - A 20x15 virtual tile matrix of 16-bit entries in system SRAM.
*  - Dynamically calculates 24-bit physical addresses using the process's
*    active MMU slot mapping.
*  - Sets Tile Set 0 base address at $F180 (Page $C0 $1180).
*  - Configures Tilemap 0 (TL0) at $F100 (Page $C0 $1100) with 20x15 dimensions.
*  - Routes TL0 to Layer 0 via $FFC2 (bits 3:0 = 4).
*  - Enables graphics + text overlay + tilemap ($FFC0 = $17).
*  - Smoothly scrolls the playfield diagonally for ~10 seconds (or until key/ESC).
*  - Catches signals (ESC/abort/break) via F$Icpt for a clean, error-free shutdown.
*  - Restores all registers and exits cleanly to the NitrOS-9 text shell.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* ------------------------------------------------------------------
*   1      2026/09/08  Antigravity
* Created initial tilemap test.
*   2      2026/09/20  Antigravity
* Renamed and integrated into test suite.
*   3      2026/09/23  Antigravity
* Fixed logical buffer addressing (leax ,u instead of immediate #offset),
* aligned tile buffer to 256-byte page boundary, switched palette from
* LUT0 to LUT1 to preserve shell palette, fixed 24-bit PhysAddr translation
* using active MMU slot register, and hardened clean exit with SS.DScrn.
********************************************************************

                    nam       tltest
                    ttl       TinyVicky Tilemap Test

                    ifp1
                    use       defsfile
                    endc

MAPSLOT             equ       MMU_SLOT_2          slot register we borrow ($4000)
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000
GRPH_LUT1_OFF       equ       GRPH_LUT0_OFF+$400  graphics LUT1 (LUTn at +$400*n)

TILE_SIZE_PX        equ       16                  16x16 tiles
TILE_BYTES          equ       TILE_SIZE_PX*TILE_SIZE_PX
MAP_W               equ       20                  20 columns
MAP_H               equ       15                  15 rows
MAP_CELLS           equ       MAP_W*MAP_H
AUTO_FRAMES         equ       300                 ~10 seconds at ~30 fps

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       6

                    mod       eom,name,tylg,atrv,start,size

                    ORG       0
saveffa0            rmb       1
saveslot            rmb       1
savemcr             rmb       1
savelayer0          rmb       1
scroll_x            rmb       2
scroll_y            rmb       2
frames_left         rmb       2                   countdown to auto-exit
sig_flag            rmb       1                   signal received flag
scratch             rmb       1
tilebase            rmb       2                   page-aligned logical base address of tile set
matbase             rmb       2                   logical base address of tilemap matrix
tile_phys_h         rmb       1
tile_phys_m         rmb       1
tile_phys_l         rmb       1
mat_phys_h          rmb       1
mat_phys_m          rmb       1
mat_phys_l          rmb       1
* Raw buffer for 3 tiles (3 * 256 = 768 bytes), page-aligned inside 1024 bytes
tileraw             rmb       1024
* Tilemap matrix (20x15 = 300 words = 600 bytes)
map_matrix          rmb       MAP_CELLS*2
                    rmb       256                 stack
size                equ       .

name                fcs       /tltest/
                    fcb       edition

start               equ       *
* ---- 0. Set up Signal Intercept Handler (F$Icpt) ----
                    clr       <sig_flag
                    leax      SigHandler,pcr      pointer to signal intercept handler
                    os9       F$Icpt              register handler (U already points to data area)

* Acquire terminal device ownership so keydrv_ps2 directs S$Abort to us (sets V.LPRC)
                    clra                          path 0 (stdin)
                    ldy       #0                  0 bytes
                    os9       I$Read
                    lda       #1                  path 1 (stdout)
                    ldy       #0                  0 bytes
                    os9       I$Write

* Flush residual input from stdin before starting
FlushInit           clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       FlushDone
                    clra
                    leax      <scratch,u
                    ldy       #1
                    os9       I$Read
                    bcc       FlushInit
FlushDone           equ       *

* Set auto-exit countdown (~10 seconds at ~30 fps)
                    ldd       #AUTO_FRAMES
                    std       <frames_left

* ---- 1. Compute Page-Aligned Tile Base and Matrix Base ----
* Align tile base to 256-byte page boundary inside tileraw
                    leax      tileraw+255,u
                    tfr       x,d
                    clrb                          round down to page boundary (low byte = 0)
                    std       <tilebase

* Matrix base address
                    leax      map_matrix,u
                    stx       <matbase

* Compute 24-bit physical addresses BEFORE mapping VRAM windows
                    ldd       <tilebase
                    lbsr      PhysAddr            returns A=H, B=M, scratch=L
                    sta       <tile_phys_h
                    stb       <tile_phys_m
                    lda       <scratch
                    sta       <tile_phys_l

                    ldd       <matbase
                    lbsr      PhysAddr
                    sta       <mat_phys_h
                    stb       <mat_phys_m
                    lda       <scratch
                    sta       <mat_phys_l

* ---- 2. Initialize Tile 0 (16x16: Transparent: all 0) ----
                    ldx       <tilebase
                    ldd       #0
                    ldy       #TILE_BYTES/2
clr0@               std       ,x++
                    leay      -1,y
                    bne       clr0@

* ---- 3. Initialize Tile 1 (16x16: Red border = Color 1, Cyan interior = Color 2) ----
                    ldx       <tilebase
                    leax      TILE_BYTES,x        Tile 1 starts at +256
                    clr       <scratch            scratch = row (0..15)
row1@               clrb                          B = col (0..15)
col1@               tst       <scratch            top edge?
                    beq       border1@
                    lda       <scratch
                    cmpa      #15                 bottom edge?
                    beq       border1@
                    tstb                          left edge?
                    beq       border1@
                    cmpb      #15                 right edge?
                    beq       border1@
                    lda       #2                  Color 2: Cyan interior
                    bra       pix1_st@
border1@            lda       #1                  Color 1: Red border
pix1_st@            sta       ,x+
                    incb
                    cmpb      #16
                    bne       col1@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #16
                    bne       row1@

* ---- 4. Initialize Tile 2 (16x16: Gold diagonal lattice = Color 3, Navy bg = Color 4) ----
                    ldx       <tilebase
                    leax      TILE_BYTES*2,x      Tile 2 starts at +512
                    clr       <scratch            scratch = row (0..15)
row2@               clrb                          B = col (0..15)
col2@               lda       <scratch
                    pshs      b
                    cmpa      ,s+                 row == col (main diagonal)?
                    beq       diag2@
                    lda       <scratch
                    pshs      b
                    adda      ,s+                 row + col == 15 (anti-diagonal)?
                    cmpa      #15
                    beq       diag2@
                    lda       #4                  Color 4: Navy background
                    bra       pix2_st@
diag2@              lda       #3                  Color 3: Gold lattice
pix2_st@            sta       ,x+
                    incb
                    cmpb      #16
                    bne       col2@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #16
                    bne       row2@

* ---- 5. Fill the 20x15 Tilemap Matrix ----
* Checkerboard alternation of Tile 1 and Tile 2.
* Each cell: Byte 0 = tile index (1 or 2), Byte 1 = attribute (0 = TS0, LUT1).
                    ldx       <matbase
                    clr       <scratch            scratch = row (0..14)
mrow@               clrb                          B = col (0..19)
mcol@               lda       <scratch
                    pshs      b
                    adda      ,s+                 (row + col) & 1
                    anda      #1
                    bne       use_t2@
                    lda       #1                  Tile 1
                    bra       mst@
use_t2@             lda       #2                  Tile 2
mst@                sta       ,x+                 Byte 0: tile index
                    clr       ,x+                 Byte 1: attr (TS0, LUT1)
                    incb
                    cmpb      #MAP_W
                    bne       mcol@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #MAP_H
                    bne       mrow@

* Initial scroll positions
                    ldd       #0
                    std       scroll_x
                    std       scroll_y

* ---- 6. Load Graphics LUT1 in Page $C1 (Leave Shell LUT0 Alone!) ----
                    lbsr      MapVky
                    lda       #FONT_BLK           Block $C1
                    sta       >MAPSLOT
                    ldx       #MAPADDR+GRPH_LUT1_OFF

* Color 0: Transparent (Blue=0, Green=0, Red=0, Alpha=0)
                    clr       ,x+
                    clr       ,x+
                    clr       ,x+
                    clr       ,x+

* Color 1: Bright Red Border (B=32, G=32, R=255, A=0)
                    lda       #32
                    sta       ,x+                 Blue
                    sta       ,x+                 Green
                    lda       #255
                    sta       ,x+                 Red
                    clr       ,x+                 Alpha

* Color 2: Bright Cyan Interior (B=240, G=224, R=32, A=0)
                    lda       #240
                    sta       ,x+                 Blue
                    lda       #224
                    sta       ,x+                 Green
                    lda       #32
                    sta       ,x+                 Red
                    clr       ,x+                 Alpha

* Color 3: Bright Amber-Gold Lattice (B=32, G=200, R=255, A=0)
                    lda       #32
                    sta       ,x+                 Blue
                    lda       #200
                    sta       ,x+                 Green
                    lda       #255
                    sta       ,x+                 Red
                    clr       ,x+                 Alpha

* Color 4: Deep Navy Background (B=160, G=48, R=32, A=0)
                    lda       #160
                    sta       ,x+                 Blue
                    lda       #48
                    sta       ,x+                 Green
                    lda       #32
                    sta       ,x+                 Red
                    clr       ,x+                 Alpha

* Clear remaining 251 entries of LUT1
                    ldy       #251*4/2
clr_lut@            clr       ,x+
                    clr       ,x+
                    leay      -1,y
                    bne       clr_lut@

* ---- 7. Configure Vicky Tile Registers in Page $C0 ----
                    lda       #SPRITE_BLK         Block $C0
                    sta       >MAPSLOT

* Point Tile Set 0 ($1180) to tilebase (Little-Endian: L, M, H, CFG per wildbits.d)
                    ldx       #MAPADDR+$1180
                    lda       <tile_phys_l
                    sta       ,x                  TS0 Addr L ($1180)
                    lda       <tile_phys_m
                    sta       1,x                 TS0 Addr M ($1181)
                    lda       <tile_phys_h
                    sta       2,x                 TS0 Addr H ($1182)
                    clr       3,x                 TS0 CFG ($1183, 0 = Linear)

* Configure Tilemap 0 (TL0 at $1100): Enable=1, 16x16 (bit 4=0), LUT1 (bit 1=1)
                    ldx       #MAPADDR+$1100
                    lda       #TILE_Enable+TILE_LUT0  $01 + $02 = $03 (LUT1)
                    sta       ,x                  TL0 CTRL ($1100)
                    lda       <mat_phys_l
                    sta       1,x                 TL0 Addr L ($1101)
                    lda       <mat_phys_m
                    sta       2,x                 TL0 Addr M ($1102)
                    lda       <mat_phys_h
                    sta       3,x                 TL0 Addr H ($1103)

* Map Size: 20x15 ($1104-$1107, Little-Endian: L, H per wildbits.d)
                    lda       #MAP_W
                    sta       4,x                 TL0 MAP_X_SIZE_L ($1104)
                    clr       5,x                 TL0 MAP_X_SIZE_H ($1105)
                    lda       #MAP_H
                    sta       6,x                 TL0 MAP_Y_SIZE_L ($1106)
                    clr       7,x                 TL0 MAP_Y_SIZE_H ($1107)

* Initial Scroll: (0, 0) ($1108-$110B, Little-Endian: L, H per wildbits.d)
                    clr       8,x                 TL0 MAP_X_POS_L ($1108)
                    clr       9,x                 TL0 MAP_X_POS_H ($1109)
                    clr       10,x                TL0 MAP_Y_POS_L ($110A)
                    clr       11,x                TL0 MAP_Y_POS_H ($110B)

                    lbsr      UnMap

* ---- 8. Configure VICKY Master Video Registers ----
                    ldy       #TXT.Base
                    lda       VKY_LAYER_CTRL_L,y
                    sta       <savelayer0
                    anda      #$F0                preserve Layer 1
                    ora       #$04                Layer 0 Source = 4 (Tilemap 0)
                    sta       VKY_LAYER_CTRL_L,y

                    lda       MASTER_CTRL_REG_L,y
                    sta       <savemcr
                    ora       #Mstr_Ctrl_Graph_Mode_En+Mstr_Ctrl_Text_Overlay+Mstr_Ctrl_TileMap_En
                    sta       MASTER_CTRL_REG_L,y

* ---- 9. Scrolling Animation Loop ----
MainLoop            equ       *
* Check if signal was caught (ESC / Ctrl-C)
                    tst       <sig_flag
                    lbne      ExitClean

* Check auto-exit countdown (~10 seconds)
                    ldd       <frames_left
                    subd      #1
                    std       <frames_left
                    lble      ExitClean

* Poll stdin for keypress
                    clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       ScrollFrame         no key pending -> continue scrolling

* Key pending: consume it and filter out residual CR/LF
                    clra
                    leax      <scratch,u
                    ldy       #1
                    os9       I$Read
                    bcs       ScrollFrame
                    lda       <scratch
                    cmpa      #C$CR
                    beq       ScrollFrame
                    cmpa      #C$LF
                    beq       ScrollFrame
                    lbra      ExitClean

* Update scroll coordinates
ScrollFrame         ldd       scroll_x
                    addd      #1
                    cmpd      #MAP_W*TILE_SIZE_PX
                    blt       ScrollXOk
                    clra
                    clrb
ScrollXOk           std       scroll_x

                    ldd       scroll_y
                    addd      #1
                    cmpd      #MAP_H*TILE_SIZE_PX
                    blt       ScrollYOk
                    clra
                    clrb
ScrollYOk           std       scroll_y

* Update scroll registers in Page $C0 (Little-Endian: L, H per wildbits.d)
                    lbsr      MapVky
                    ldx       #MAPADDR+$1100
                    lda       scroll_x+1
                    sta       8,x                 TL0 MAP_X_POS_L ($1108)
                    lda       scroll_x
                    sta       9,x                 TL0 MAP_X_POS_H ($1109)
                    lda       scroll_y+1
                    sta       10,x                TL0 MAP_Y_POS_L ($110A)
                    lda       scroll_y
                    sta       11,x                TL0 MAP_Y_POS_H ($110B)
                    lbsr      UnMap

                    ldx       #2                  ~30 fps pacing
                    os9       F$Sleep

                    lbra      MainLoop

* ---- 10. Clean Exit: restore registers and quit with status 0 ----
ExitClean           equ       *
* Remove signal intercept routine
                    ldx       #0
                    ldu       #0
                    os9       F$Icpt

* Flush any pending keys from stdin so nothing leaks to shell
FlushKeys           clra                          path 0 (stdin)
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       DoneFlush
                    clra
                    leax      <scratch,u
                    ldy       #1
                    os9       I$Read
                    bra       FlushKeys
DoneFlush           equ       *

* Disable Tilemap 0 in Page $C0
                    lbsr      MapVky
                    ldx       #MAPADDR+$1100
                    clr       ,x                  TL0 disable
                    lbsr      UnMap

* Clear layer controls
                    ldy       #TXT.Base
                    clr       VKY_LAYER_CTRL_L,y
                    clr       VKY_LAYER_CTRL_H,y

* Explicitly restore pure text mode in Vicky Master Control Register
                    lda       #Mstr_Ctrl_Text_Mode_En
                    sta       MASTER_CTRL_REG_L,y

* Notify vtio screen driver of text mode return
                    ldx       #FX_TXT
                    ldy       #FT_OMIT
                    lda       #0
                    ldb       #SS.DScrn
                    os9       I$SetStt

                    clrb                          Status 0 = Success
                    os9       F$Exit

* ---- Signal Intercept Routine ----
* Called by OS-9 kernel when a signal (e.g. S$Abort / ESC) arrives.
* U = data area pointer, B = signal code.
SigHandler          stb       <sig_flag,u         record signal code
                    rti                           return to resume / wake up

* ---- PhysAddr: D = process logical address
* Queries MMU to translate D to 24-bit physical address.
* Preserves X.
* Returns A = Phys[23:16], B = Phys[15:8], scratch = Phys[7:0]
PhysAddr            pshs      x
                    stb       <scratch            scratch = Phys[7:0] (low byte)
                    tfr       a,b
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    lsrb                          B = slot index (0..7)
                    anda      #$1F                A = Off_H & $1F
                    pshs      d                   stack: 0,s=A (Off_H & $1F), 1,s=B (slot), 2,s=X_H, 3,s=X_L

* Query MMU for active physical block of slot B
                    orcc      #IntMasks
                    lda       >MMU_MEM_CTRL
                    sta       <saveffa0
                    tfr       a,b
                    andb      #$03                active map (bits 1:0)
                    lslb
                    lslb
                    lslb
                    lslb
                    anda      #$CF                clear edit bits
                    pshs      b
                    ora       ,s+
                    sta       >MMU_MEM_CTRL       edit = active

                    ldb       1,s                 B = slot index (0..7)
                    ldx       #MMU_SLOT_0
                    lda       b,x                 A = physical 8KB block number

                    ldb       <saveffa0
                    stb       >MMU_MEM_CTRL       restore original MMU_MEM_CTRL
                    andcc     #^IntMasks

* Now A = physical block number
* Compute Phys[23:16] = block >> 3
                    tfr       a,b
                    lsrb
                    lsrb
                    lsrb                          B = block >> 3 (Phys[23:16])
* Compute Phys[15:8] = (block << 5) | (Off_H & $1F)
                    asla
                    asla
                    asla
                    asla
                    asla                          A = block << 5
                    ora       ,s                  A = (block << 5) | (Off_H & $1F) (Phys[15:8])
                    exg       a,b                 A = Phys[23:16], B = Phys[15:8]
                    leas      2,s                 pop saved D
                    puls      x                   restore X
                    rts

* ---- MapVky: map Block $C0 into MAPSLOT ($A000) with IRQs masked
MapVky              orcc      #IntMasks
                    lda       >MMU_MEM_CTRL
                    sta       <saveffa0
                    tfr       a,b
                    andb      #$03                active map
                    lslb
                    lslb
                    lslb
                    lslb
                    anda      #$CF                clear edit bits
                    pshs      b
                    ora       ,s+
                    sta       >MMU_MEM_CTRL       edit = active
                    lda       >MAPSLOT
                    sta       <saveslot
                    lda       #SPRITE_BLK         Block $C0
                    sta       >MAPSLOT
                    rts

* ---- UnMap: restore slot and MLUT control, unmask IRQs
UnMap               lda       <saveslot
                    sta       >MAPSLOT
                    lda       <saveffa0
                    sta       >MMU_MEM_CTRL
                    andcc     #^IntMasks
                    rts

                    emod
eom                 equ       *
                    end
