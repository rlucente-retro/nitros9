# WildBits Jr2 core v8_rc15 (built 2026-09-12)

rc15 = rc14 with one correction: **RAM window B (LUT entries $D0-$EF) sits at its identity address,
$1A_0000-$1D_FFFF**, like every other block (absolute address = block x $2000). rc14 had placed it at
$20_0000-$23_FFFF after a mis-edited row of the memory-map sheet - one bit past the SRAM's A19 - which
needed a "block + $30" in the MMU register block and a bit-20 fold onto the chip in the memory manager,
plus a special case in vtio's Blk2Addr. All three are gone: every RAM block is block x $2000 for the CPU,
VICKY, DMA and the debug port alike, and the SRAM pins simply carry the absolute address / 2.

The map, rc15 and later: $00-$3F system RAM ($00_0000-$07_FFFF), $40-$7F flash, $80-$9F expansion,
$A0-$BF RAM window A ($14_0000-$17_FFFF), $C0-$C7 sectored I/O ($18_xxxx), $D0-$EF RAM window B
($1A_0000-$1D_FFFF), $F0-$FF undecoded. 1 MB of the 2 MB SRAM in use.

Pairing: this core needs the kit's disks from 2026-09-12 19:43 on (vtio Blk2Addr = block x $2000). A
disk built for rc14 (Blk2Addr with the +$30) puts graphics screens allocated in window B at the wrong
address on rc15, and this kit's disk does the same on an rc14 core. HIRES4 (640 x 240 x 16, GFX MODE
$FFCB), the math remainder fix and everything from rc13 are unchanged from rc14.

## Timing
All constraints met: WNS +0.045 ns, WHS +0.028 ns, 0 failing endpoints (34,183 setup endpoints), block RAM 36 of 50; built 2026-09-12 20:55. Scheduler and SRAM constraints unchanged from rc13.
