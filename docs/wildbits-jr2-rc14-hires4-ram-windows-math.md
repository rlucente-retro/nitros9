# WildBits Jr2 core v8_rc14 (built 2026-09-12 14:37)

rc14 = rc13 + the same three things the K2 rc14 carries; both machines are on rc14 now.

## 1. HIRES4: 640 x 240 at 16 colours
A new GFX MODE register at $FFCB (VICKY master control block index 11, fixed I/O, pokeable from any
task): bit 0 = HIRES4 makes every bitmap plane read as 640 x 240 with two 4-bit dots per byte, the
high nibble on the left; bits 3:1 pick which 16-entry slice of the plane's CLUT the nibbles index
(colour = group x 16 + nibble). One plane alone can ask for it with bit 4 of its bitmap control byte
(group in bits 7:5); the two are OR'd. Same frame RAM and fetch bandwidth as 320 x 240 x 8. Sprites,
tiles and text are untouched: they still draw at 320 dots doubled and composite with the 640-wide
bitmap dots in the usual layer order; a sprite or tile dot covers a pair of bitmap dots. Bitmap
transparency is per 640 dot. wildbits.d: VKY_GFX_MODE, GFX_HIRES4, GFX_GROUP, BM0_HIRES4, BM0_GROUP.

The dot order inside a byte pair is deterministic: the pixel encoder derives the pair phase from a
blanking-aligned toggle instead of sampling the 12.5 MHz clock as data (which made the order a
per-build lottery - mirrored pairs on some builds, clean on others, from identical RTL).

## 2. RAM windows: 1 MB for NitrOS-9 (Foenix memory map Revision E)
The SRAM is 1M x 16 (2 MB); OS-9 used 512 KB of it. Two 256 KB windows are decoded now, at the
absolute addresses of the Revision E map: LUT entries $A0-$BF = $14_0000-$17_FFFF and $D0-$EF =
$20_0000-$23_FFFF, for the CPU, VICKY, DMA and the debug port alike (window A is a native chip
address; window B is folded onto chip bytes $18_0000-$1B_FFFF inside the MMU). The kernel side is
the wb/1mb_ram_upgrade branch (block map grown to 256 entries, the gaps marked NotRAM, vtio's
Blk2Addr adds $30 blocks for $D0-$EF), built for both machines since 2026-09-12. mfree then shows
blocks A0 and D0 free: 928 KB in total after boot.

## 3. Math coprocessor: the remainder
MATH_DIV_REM ($FEF6) returned a 17-bit slice of the divider's result (bit 15 lost, bit 8 doubled),
so remainders of 256 and more read roughly doubled. It reads the true 16-bit remainder now
(tests/math: 512 as a remainder reads $0200, not $0400). Still open in the math block: the write
decode ignores address bit 4 (a write to a result register lands in an operand); two FP status bits
(multiply zero, divide-by-zero) are never driven.

## Timing
All constraints met: WNS +0.060 ns, WHS +0.046 ns, 0 failing endpoints (34,189 setup endpoints).
Block RAM 36 of 50. Scheduler and SRAM constraints unchanged from rc13 (the Jr2's own 3-tick
address setup, FASTWR_LATE2, is untouched).
