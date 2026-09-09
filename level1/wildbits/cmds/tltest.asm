********************************************************************
* TLTest - TinyVicky Hardware Tilemap Test
*
* Demonstrates and tests the TinyVicky II hardware scrolling tilemap
* engine on Wildbits Jr2 (FNX6809 core).
*
* Allocates and initializes:
*  - Two 16x16 pixel tiles (tile 0 = empty/transparent, tile 1 = cyan box with
*    red border, tile 2 = red box with grey lattice).
*  - A 20x15 virtual tile matrix of 16-bit entries in system SRAM.
*  - Sets Tile Set 0 base address at $F180 (Page $C0 $1180).
*  - Configures Tilemap 0 (TL0) at $F100 (Page $C0 $1100) with 20x15 dimensions.
*  - Routes TL0 to Layer 0 via $FFC2 (bits 3:0 = 4).
*  - Enables graphics + text overlay + tilemap ($FFC0 = $17).
*  - Smoothly scrolls the playfield diagonally for ~5 seconds (or until key/ESC).
*  - Catches signals (ESC/abort) via F$Icpt for a clean, error-free shutdown.
*  - Restores all registers and exits cleanly to the NitrOS-9 shell.
********************************************************************

                    nam       tltest
                    ttl       TinyVicky Tilemap Test

                    ifp1
                    use       os9.d
                    use       wildbits.d
                    endc

MAPSLOT             equ       MMU_SLOT_5          slot register we borrow ($A000)
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000

TILE_SIZE_PX        equ       16                  16x16 tiles
TILE_BYTES          equ       TILE_SIZE_PX*TILE_SIZE_PX
MAP_W               equ       20                  20 columns
MAP_H               equ       15                  15 rows
MAP_CELLS           equ       MAP_W*MAP_H
AUTO_FRAMES         equ       150                 ~5 seconds at ~30 fps

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       2

                    mod       eom,name,tylg,atrv,start,size

                    ORG       0
saveffa0            rmb       1
saveslot            rmb       1
savemcr             rmb       1
savelayer0          rmb       1
blk0                rmb       1                   physical block of our process memory
scroll_x            rmb       2
scroll_y            rmb       2
frames_left         rmb       2                   countdown to auto-exit
sig_flag            rmb       1                   signal received flag
scratch             rmb       1
* Tile pixel data: Tile 0 (empty), Tile 1 (256 bytes), Tile 2 (256 bytes)
tile0_pix           rmb       TILE_BYTES
tile1_pix           rmb       TILE_BYTES
tile2_pix           rmb       TILE_BYTES
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

* Set auto-exit countdown (~5 seconds at ~30 fps)
                    ldd       #AUTO_FRAMES
                    std       <frames_left

* Clear Tile 0 pixels (16x16 transparent: all 0)
                    ldx       #tile0_pix
                    ldb       #0
clr0@               clr       ,x+
                    decb
                    bne       clr0@

* ---- 1. Initialize Tile 1 pixels (16x16: Red border, Cyan interior) ----
                    ldx       #tile1_pix
                    clr       <scratch            scratch = row
row1@               clrb                          B = col
col1@               tst       <scratch            top edge?
                    beq       border1@
                    lda       <scratch
                    cmpa      #15                 bottom edge?
                    beq       border1@
                    tstb                          left edge?
                    beq       border1@
                    cmpb      #15                 right edge?
                    beq       border1@
                    lda       #$FF                cyan interior
                    bra       pix1_st@
border1@            lda       #$30                warm red border
pix1_st@            sta       ,x+
                    incb
                    cmpb      #16
                    bne       col1@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #16
                    bne       row1@

* ---- 2. Initialize Tile 2 pixels (16x16: Warm red lattice pattern) ----
                    ldx       #tile2_pix
                    clr       <scratch            scratch = row
row2@               clrb                          B = col
col2@               lda       <scratch
                    pshs      b
                    cmpa      ,s+                 row == col (main diagonal)?
                    beq       diag2@
                    lda       <scratch
                    pshs      b
                    adda      ,s+                 row + col == 15 (anti-diagonal)?
                    cmpa      #15
                    beq       diag2@
                    lda       #$30                warm red background
                    bra       pix2_st@
diag2@              lda       #$80                grey diagonal lattice
pix2_st@            sta       ,x+
                    incb
                    cmpb      #16
                    bne       col2@
                    inc       <scratch
                    lda       <scratch
                    cmpa      #16
                    bne       row2@

* ---- 3. Fill the 20x15 Tilemap Matrix ----
* Alternate Tile 1 and Tile 2 in a checkerboard pattern.
* Each entry: Byte 0 = tile index, Byte 1 = attribute (0 = TS0, LUT0).
                    ldx       #map_matrix
                    clr       <scratch            scratch = row
mrow@               clrb                          B = col
mcol@               lda       <scratch
                    pshs      b
                    adda      ,s+                 (row + col) & 1
                    anda      #1
                    bne       use_t2@
                    lda       #1                  Tile 1
                    bra       mst@
use_t2@             lda       #2                  Tile 2
mst@                sta       ,x+                 Byte 0: tile index
                    clr       ,x+                 Byte 1: attr (TS0, LUT0)
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

* ---- 4. Configure VICKY Page $C0 Registers ----
                    lbsr      MapVky
                    lda       >MMU_SLOT_0         physical block of process
                    sta       <blk0

* Load graphics LUT0 with color ramp
                    lda       #FONT_BLK           Block $C1
                    sta       >MAPSLOT
                    ldx       #MAPADDR+GRPH_LUT0_OFF
                    clrb
lut@                stb       ,x                  Blue  = index
                    stb       1,x                 Green = index
                    tfr       b,a
                    coma
                    sta       2,x                 Red   = 255-index
                    clr       3,x                 Alpha
                    leax      4,x
                    incb
                    bne       lut@

* Window back to Page $C0 (Block $C0)
                    lda       #SPRITE_BLK         Block $C0
                    sta       >MAPSLOT

* Point Tile Set 0 ($1180) to tile0_pix (Little-Endian: L, M, H, CFG per wildbits.d)
                    ldd       #tile0_pix
                    lbsr      PhysAddr            returns A=H, B=M, scratch=L
                    pshs      a                   save H
                    ldx       #MAPADDR+$1180
                    lda       <scratch
                    sta       ,x                  TS0 Addr L ($1180)
                    stb       1,x                 TS0 Addr M ($1181)
                    puls      a
                    sta       2,x                 TS0 Addr H ($1182)
                    clr       3,x                 TS0 CFG ($1183, 0 = Linear)

* Configure Tilemap 0 (TL0 at $1100)
                    ldx       #MAPADDR+$1100
                    lda       #$01                TILE_Enable=1, 16x16 (bit 4=0), LUT0
                    sta       ,x

* Map Matrix pointer ($1101-$1103, Little-Endian: L, M, H per wildbits.d)
                    ldd       #map_matrix
                    lbsr      PhysAddr
                    pshs      a                   save H
                    lda       <scratch
                    sta       1,x                 TL0 Addr L ($1101)
                    stb       2,x                 TL0 Addr M ($1102)
                    puls      a
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

* ---- 5. Configure VICKY Master Video Registers ----
                    ldy       #TXT.Base
                    lda       VKY_LAYER_CTRL_0
                    sta       <savelayer0
                    anda      #$F0                preserve Layer 1
                    ora       #$04                Layer 0 Source = 4 (Tilemap 0)
                    sta       VKY_LAYER_CTRL_0

                    lda       MASTER_CTRL_REG_L,y
                    sta       <savemcr
                    ora       #Mstr_Ctrl_Graph_Mode_En+Mstr_Ctrl_Text_Overlay+Mstr_Ctrl_TileMap_En
                    sta       MASTER_CTRL_REG_L,y

* ---- 6. Scrolling Animation Loop ----
MainLoop            equ       *
* Check if signal was caught
                    tst       <sig_flag
                    lbne      ExitClean

* Check auto-exit countdown (~5 seconds)
                    ldd       <frames_left
                    subd      #1
                    std       <frames_left
                    lble      ExitClean

* Poll stdin for keypress
                    clra
                    ldb       #SS.Ready
                    os9       I$GetStt
                    lbcc      EatKeyAndExit

* Update scroll coordinates
                    ldd       scroll_x
                    addd      #1
                    cmpd      #MAP_W*TILE_SIZE_PX
                    blt       sx_ok@
                    clra
                    clrb
sx_ok@              std       scroll_x

                    ldd       scroll_y
                    addd      #1
                    cmpd      #MAP_H*TILE_SIZE_PX
                    blt       sy_ok@
                    clra
                    clrb
sy_ok@              std       scroll_y

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

EatKeyAndExit       equ       ExitClean

* ---- 7. Clean Exit: restore registers and quit with status 0 ----
ExitClean           equ       *
* Remove signal intercept routine
                    ldx       #0
                    ldu       #0
                    os9       F$Icpt

* Flush any pending keys from stdin so nothing leaks to shell
flush@              clra
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       fl_done@
                    clra
                    ldx       #scratch
                    ldy       #1
                    os9       I$Read
                    bra       flush@
fl_done@

* Disable Tilemap 0
                    lbsr      MapVky
                    ldx       #MAPADDR+$1100
                    clr       ,x                  TL0 disable
                    lbsr      UnMap

* Restore Layer 0 and Master Control
                    lda       <savelayer0
                    sta       VKY_LAYER_CTRL_0
                    ldy       #TXT.Base
                    lda       <savemcr
                    sta       MASTER_CTRL_REG_L,y

                    clrb                          Status 0 = Success
                    os9       F$Exit

* ---- Signal Intercept Routine ----
* Called by OS-9 kernel when a signal (e.g. S$Abort / ESC) arrives.
* U = data area pointer, B = signal code.
SigHandler          stb       <sig_flag,u         record signal code
                    rti                           return to resume / wake up

* ---- PhysAddr: D = process logical address (slot 0).
* Returns A = phys 23:16, B = phys 15:8, scratch = phys 7:0.
PhysAddr            pshs      d
                    lda       <blk0
                    lsra
                    lsra
                    lsra
                    pshs      a                   phys 23:16
                    lda       <blk0
                    asla
                    asla
                    asla
                    asla
                    asla
                    ora       1,s                 | (offset >> 8)
                    tfr       a,b                 B = phys 15:8
                    lda       2,s                 A = offset low byte
                    sta       <scratch
                    puls      a                   A = phys 23:16
                    leas      2,s                 clean stack
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
