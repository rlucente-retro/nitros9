# WildBits Jr2 core v8 rc13 (2026-09-08)

rc13 is rc11/rc12's write slot with four fixes in the video path and one new register window.
Built 2026-09-08 16:03 (Vivado 2025.2, Performance_ExplorePostRoutePhysOpt): WNS +0.161 ns, WHS +0.051 ns,
0 failing endpoints. Verified on the Jr2 the same afternoon: bitmap and sprite layers present at boot, the
128-sprite demo running clean, bitmaps loading without sparklies.

## What changed

1. **Write slot back on FASTWR_LATE2** (3 ticks of address setup, WEn ticks 9 to 11, release at 12), the geometry
   rc11 and rc12 ran on. An intermediate roll with a 4-tick slot (LATE3) put sparklies on every CPU write and killed
   the bitmap layer on the second load; it was withdrawn.
2. **Bus-grant crossing timed.** The MMU's bus grant to the video engine (Read_Valid, 200 MHz) is sampled by the
   engine on the 100 MHz A clock and decides whether a fetch lands inside the CPU's slot. The XDC had declared both
   directions of that crossing false paths, so every build placed it with a different, untimed skew: "bitmaps and
   sprites gone at boot" on some builds, sparklies on others. rc13 bounds both directions to 4.5 ns (datapath-only)
   and leaves the SRAM pins on their previous constraints. The paths close with more than 0.7 ns to spare.
3. **Fetch timeouts in the sprite and bitmap engines.** A fetch whose address counter never reports "reached" used
   to park the state machine for ever (sprite layer collapsing into bars, bitmap layer black until reset). Both
   machines now abandon such a fetch after about 10 to 20 microseconds: one line is lost, the frame goes on.
4. **Text colour LUTs readable.** The two text colour tables (foreground at $1700, background at $1740 of VICKY
   page $C0) were write-only block RAM. rc13 keeps a shadow of each and returns it on CPU reads, pre-loaded with
   the same OS-9 palette the block RAM starts with. Byte order per entry is blue, green, red, alpha.
   The `lutrd` command on the kit disk dumps every LUT.

## Notes

- The graphics LUTs (four of 256 entries) were always readable; they start empty at power-up.
- The `sprites` demo on this kit is edition 8: an earlier loop bug in the demo itself (not the core) wrote past the
  128 sprite records into the text colour tables every frame, which is what the text-LUT read-back caught.
- K2 rc12 does not carry items 2 to 4 yet.
