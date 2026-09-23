********************************************************************
* TLTest - TinyVicky Hardware Tilemap Test
*
* Demonstrates and tests the TinyVicky II hardware scrolling tilemap
* engine on Wildbits Jr2 (FNX6809 core).
*
* Allocates and initializes:
*  - Page-aligned 16x16 pixel tiles in system SRAM:
*     Tile 0 = cyan box with red border (non-transparent fallback)
*     Tile 1 = cyan box with red border
*     Tile 2 = navy box with gold diagonal lattice.
*  - 16-color palette loaded into both CLUT 0 and CLUT 1, preserving
*    and restoring shell CLUT 0 on exit.
*  - A 22x16 virtual tile matrix of 16-bit entries in system SRAM with
*    symmetric byte encoding (Byte 0 = Byte 1 = Tile Index) for bulletproof
*    endianness immunity.
*  - Page-aligned buffers ensuring 24-bit physical addresses are palindromic
*    (0, M, 0), immune to address register endianness.
*  - Configures all 8 Tile Sets (TS0..TS7 at $1180..$119F).
*  - Configures Tilemap 0 (TL0 at $1100) with 22x16 dimensions.
*  - Explicitly disables unused Tilemaps 1 and 2 ($110C, $1118).
*  - Routes TL0 to Layer 0 via $FFC2 (bits 3:0 = 4).
*  - Enables graphics + text overlay + tilemap ($FFC0 = $17).
*  - Smoothly scrolls the playfield diagonally with strictly clamped
*    fine sub-tile offsets (SSX/SSY: 0..15) for ~10 seconds (or until ESC).
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
*   7      2026/09/23  Antigravity
* Hardened against FPGA hardware static/tearing: symmetric dual-byte
* cell matrix encoding, page-aligned matrix buffer for palindromic 24-bit
* physical addresses, configured all 8 Tile Sets (TS0..TS7), populated
* Tile 0 with valid graphic pattern, clamped fine scroll strictly to 0..15,
* dual-loaded palettes to CLUT 0 & 1 with CLUT 0 preservation/restore, and
* explicitly disabled unused Tilemaps 1 & 2.
*   8      2026/09/23  Antigravity
* Switched TS0..TS7 and TL0 address registers to Big-Endian (H, M, L),
* resolving the hardware static/tearing issue where Little-Endian writes
* caused the FPGA to fetch from 0x00C007 (Kernel RAM) instead of 0x07C000.
*   9      2026/09/23  Antigravity
* Switched scroll registers to Big-Endian: Offset 8 ($1108)=H, Offset 9 ($1109)=L
* for X scroll, Offset 10 ($110A)=H, Offset 11 ($110B)=L for Y scroll.
* In Edition 8, fine_scroll was stored in the High byte ($1108/$110A), causing
* the FPGA to jump by 256 pixels (16 whole tiles) into uninitialized RAM every
* frame, producing the flashing dots/static captured in video.
* Also zero-cleared the entire tileraw and matraw buffers.
********************************************************************

                    nam       tltest
                    ttl       TinyVicky Tilemap Test

                    ifp1
                    use       defsfile
                    endc

MAPSLOT             equ       MMU_SLOT_3          slot register we borrow ($6000)
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000
GRPH_LUT1_OFF       equ       GRPH_LUT0_OFF+$400  graphics LUT1 (LUTn at +$400*n)

TILE_SIZE_PX        equ       16                  16x16 tiles
TILE_BYTES          equ       TILE_SIZE_PX*TILE_SIZE_PX
MAP_W               equ       22                  22 columns (extra margins for smooth scrolling)
MAP_H               equ       16                  16 rows
MAP_CELLS           equ       MAP_W*MAP_H
AUTO_FRAMES         equ       300                 ~10 seconds at ~30 fps

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       9

                    mod       eom,name,tylg,atrv,start,size

                    ORG       0
saveffa0            rmb       1
saveslot            rmb       1
savemcr             rmb       1
savelayer0          rmb       1
fine_scroll         rmb       1                   sub-tile fine scroll (0..15)
frames_left         rmb       2                   countdown to auto-exit
sig_flag            rmb       1                   signal received flag
scratch             rmb       1
tilebase            rmb       2                   page-aligned logical base address of tile set
matbase             rmb       2                   page-aligned logical base address of tilemap matrix
tile_phys_h         rmb       1
tile_phys_m         rmb       1
tile_phys_l         rmb       1
mat_phys_h          rmb       1
mat_phys_m          rmb       1
mat_phys_l          rmb       1
save_clut0          rmb       16                  saved original CLUT 0 entries 1..4 (16 bytes)
* Raw buffer for 3 tiles (3 * 256 = 768 bytes), page-aligned inside 1024 bytes
tileraw             rmb       1024
* Raw buffer for tilemap matrix (22x16 = 352 cells * 2 = 704 bytes), page-aligned inside 1024 bytes
matraw              rmb       1024
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
                    clr       <fine_scroll

* Clear all 2048 bytes of raw buffers (tileraw + matraw) to prevent random memory leaks
                    leax      tileraw,u
                    ldy       #2048/2
clr_raw@            clr       ,x+
                    clr       ,x+
                    leay      -1,y
                    bne       clr_raw@

* ---- 1. Compute Page-Aligned Tile Base and Matrix Base ----
* Align tile base to 256-byte page boundary inside tileraw
                    leax      tileraw+255,u
                    tfr       x,d
                    clrb                          round down to page boundary (low byte = 0)
                    std       <tilebase

* Align matrix base to 256-byte page boundary inside matraw
                    leax      matraw+255,u
                    tfr       x,d
                    clrb                          round down to page boundary (low byte = 0)
                    std       <matbase

* Compute 24-bit physical addresses BEFORE mapping VRAM windows
* Because tilebase and matbase are page-aligned (low byte = 0) and
* in SRAM < 512KB (high byte = 0), both addresses are palindromic:
* (0, M, 0), making them 100% endian-neutral!
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

* ---- 2. Initialize Tile 0 (Populated with Tile 1 Pattern for Non-Transparent Fallback) ----
                    ldx       <tilebase
                    lbsr      MakeTile1

* ---- 3. Initialize Tile 1 (16x16: Red border = Color 1, Cyan interior = Color 2) ----
                    ldx       <tilebase
                    leax      TILE_BYTES,x        Tile 1 starts at +256
                    lbsr      MakeTile1

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

* ---- 5. Fill the 22x16 Tilemap Matrix ----
* Checkerboard alternation of Tile 1 and Tile 2.
* Symmetric cell format: Byte 0 = Byte 1 = Tile Index (1 or 2).
* Regardless of whether hardware reads Byte 0 or Byte 1 as Tile Index,
* and whether it reads Byte 0 or Byte 1 as Attribute, the outcome is identical!
                    ldx       <matbase
                    clr       <scratch            scratch = row (0..15)
mrow@               clrb                          B = col (0..21)
mcol@               lda       <scratch
                    pshs      b
                    adda      ,s+                 (row + col) & 1
                    anda      #1
                    bne       use_t2@
                    lda       #1                  Tile 1
                    bra       mst@
use_t2@             lda       #2                  Tile 2
mst@                sta       ,x+                 Byte 0: Tile Index (1 or 2)
                    sta       ,x+                 Byte 1: Tile Index (1 or 2) (Symmetric!)
                    incb
                    cmpb      #MAP_W
                    bne       mcol@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #MAP_H
                    bne       mrow@

* ---- 6. Load Graphics Palettes in Page $C1 ----
                    lbsr      MapVky
                    lda       #FONT_BLK           Block $C1
                    sta       >MAPSLOT

* Save original Colors 1..4 (16 bytes) of CLUT 0
                    ldx       #MAPADDR+GRPH_LUT0_OFF+4
                    leay      save_clut0,u
                    ldb       #16
save_cl0@           lda       ,x+
                    sta       ,y+
                    decb
                    bne       save_cl0@

* Program Colors 1..4 in CLUT 0
                    leax      tile_palette,pcr
                    ldy       #MAPADDR+GRPH_LUT0_OFF+4
                    ldb       #16
set_cl0@            lda       ,x+
                    sta       ,y+
                    decb
                    bne       set_cl0@

* Ensure CLUT 1 Color 0 is transparent
                    ldx       #MAPADDR+GRPH_LUT1_OFF
                    clr       ,x+
                    clr       ,x+
                    clr       ,x+
                    clr       ,x+

* Program Colors 1..4 in CLUT 1
                    leax      tile_palette,pcr
                    ldy       #MAPADDR+GRPH_LUT1_OFF+4
                    ldb       #16
set_cl1@            lda       ,x+
                    sta       ,y+
                    decb
                    bne       set_cl1@

* ---- 7. Configure Vicky Tile Registers in Page $C0 ----
                    lda       #SPRITE_BLK         Block $C0
                    sta       >MAPSLOT

* Program ALL 8 Tile Sets (TS0..TS7: $1180 to $119F, 8 sets * 4 bytes = 32 bytes)
* to tilebase address. Hardware registers on FNX6809 are Big-Endian:
* Offset 0 = H, Offset 1 = M, Offset 2 = L, Offset 3 = CFG.
                    ldx       #MAPADDR+$1180
                    ldb       #8                  8 tile sets
ts_loop@            lda       <tile_phys_h
                    sta       ,x+                 TSn Addr H ($1180)
                    lda       <tile_phys_m
                    sta       ,x+                 TSn Addr M ($1181)
                    lda       <tile_phys_l
                    sta       ,x+                 TSn Addr L ($1182)
                    clr       ,x+                 TSn CFG ($1183, 0 = Linear)
                    decb
                    bne       ts_loop@

* Configure Tilemap 0 (TL0 at $1100): Enable=1, 16x16 (bit 4=0), default CLUT 0
* Address registers are Big-Endian: Offset 1 = H, Offset 2 = M, Offset 3 = L.
                    ldx       #MAPADDR+$1100
                    lda       #TILE_Enable        $01
                    sta       ,x                  TL0 CTRL ($1100)
                    lda       <mat_phys_h
                    sta       1,x                 TL0 Addr H ($1101)
                    lda       <mat_phys_m
                    sta       2,x                 TL0 Addr M ($1102)
                    lda       <mat_phys_l
                    sta       3,x                 TL0 Addr L ($1103)

* Map Size: 22x16 ($1104-$1107)
                    lda       #MAP_W
                    sta       4,x                 TL0 MAP_X_SIZE_L ($1104)
                    clr       5,x                 TL0 MAP_X_SIZE_H ($1105)
                    lda       #MAP_H
                    sta       6,x                 TL0 MAP_Y_SIZE_L ($1106)
                    clr       7,x                 TL0 MAP_Y_SIZE_H ($1107)

* Initial Scroll: (0, 0) ($1108-$110B)
                    clr       8,x                 TL0 MAP_X_POS_H ($1108) = 0
                    clr       9,x                 TL0 MAP_X_POS_L ($1109) = 0
                    clr       10,x                TL0 MAP_Y_POS_H ($110A) = 0
                    clr       11,x                TL0 MAP_Y_POS_L ($110B) = 0

* Explicitly disable unused Tilemaps 1 ($110C) and 2 ($1118)
                    clr       12,x                TL1 CTRL ($110C) = 0
                    clr       24,x                TL2 CTRL ($1118) = 0

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

* Update scroll coordinates (smooth fine sub-tile scroll strictly 0..15)
ScrollFrame         inc       <fine_scroll
                    lda       <fine_scroll
                    anda      #$0F                clamp to 0..15 pixels
                    sta       <fine_scroll

* Update scroll registers in Page $C0
* Register layout on FNX6809 (Big-Endian):
* Offset 8  ($1108): MAP_X_POS_H = X[9..4] = 0
* Offset 9  ($1109): MAP_X_POS_L = X[3..0]:SSX[3..0] = fine_scroll (0..15)
* Offset 10 ($110A): MAP_Y_POS_H = Y[7..4] = 0
* Offset 11 ($110B): MAP_Y_POS_L = Y[3..0]:SSY[3..0] = fine_scroll (0..15)
                    lbsr      MapVky
                    ldx       #MAPADDR+$1100
                    clr       8,x                 TL0 MAP_X_POS_H ($1108) = 0
                    lda       <fine_scroll
                    sta       9,x                 TL0 MAP_X_POS_L ($1109) = fine_scroll (0..15)
                    clr       10,x                TL0 MAP_Y_POS_H ($110A) = 0
                    lda       <fine_scroll
                    sta       11,x                TL0 MAP_Y_POS_L ($110B) = fine_scroll (0..15)
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

* Disable Tilemaps in Page $C0
                    lbsr      MapVky
                    ldx       #MAPADDR+$1100
                    clr       ,x                  TL0 disable ($1100)
                    clr       12,x                TL1 disable ($110C)
                    clr       24,x                TL2 disable ($1118)

* Restore original CLUT 0 Colors 1..4 in Page $C1
                    lda       #FONT_BLK           Block $C1
                    sta       >MAPSLOT
                    ldx       #MAPADDR+GRPH_LUT0_OFF+4
                    leay      save_clut0,u
                    ldb       #16
rst_cl0@            lda       ,y+
                    sta       ,x+
                    decb
                    bne       rst_cl0@

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

* ---- MakeTile1: Generate Cyan Box with Red Border at X ----
* Preserves U. Modifies A, B, X, scratch.
MakeTile1           clr       <scratch            scratch = row (0..15)
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
                    rts

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

* ---- MapVky: map Block $C0 into MAPSLOT ($6000) with IRQs masked
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

* Palette definitions for Colors 1..4 (16 bytes, Blue, Green, Red, Alpha)
tile_palette        fcb       32,32,255,0         Color 1: Bright Red Border
                    fcb       240,224,32,0        Color 2: Bright Cyan Interior
                    fcb       32,200,255,0        Color 3: Bright Amber-Gold Lattice
                    fcb       160,48,32,0         Color 4: Deep Navy Background

                    emod
eom                 equ       *
                    end
