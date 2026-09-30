# WildBits Jr2 v8_rc11 — bitmap/sprite layers back, turbo sparklies fixed, MIDI control register

Built 2026-09-05 10:14 from the shared turbo MMU (`TyVKy2K2turbo_MMU_FNX6809.v`) with
`TURBO_FASTWRITE FASTWR_LATE FASTWR_LATE2`. Verified on hardware the same morning: bitmaps and
sprites present, DriveWire working, no sparklies in turbo while the SD writes RAM under a bitmap.

## Fix 1 — bitmap and sprite layers missing (build-to-build lottery)
The Jr2 constraints file declared the three clock crossings the graphics engine runs on as false
paths (video->200 MHz fetch request, 200->video and 100 MHz->video data returns). They were never
timed, so whether the fetch handoff worked depended on placement luck: rc10 was a lucky build.
Ported the K2's rc6/rc8 "video-lottery" constraints: `set_max_delay -datapath_only` bounds
(39.721 / 9.930 / 9.930 ns) in place of the false paths, `ASYNC_REG` on the resync flops, output
delays on the five SRAM strobes (CSn/OEn/WEn/LBn/UBn) and hold delays on every SRAM pin.
Result: timing closes on the Jr2 for the first time (rc10: 24 failing endpoints, WNS -1.203 ns;
rc11: 0 failing, WNS +0.046 / WHS +0.061).

## Fix 2 — sparklies on a displayed bitmap while the SD writes RAM (turbo)
Address setup before WE on the fast write. Measured on this board with otherwise identical cores:
1 tick (the K2's t7 slot) = layers gone / shell freeze; 2 ticks (`FASTWR_LATE`, the rc10 slot) =
occasional stray write; 3 ticks = clean. An early WE strobes the address still on the bus from the
graphics engine's last fetch, so the stray write lands on the pixel just displayed.
`FASTWR_LATE2`: WEn t9..t11, slot released t12, 15 ns address setup, pulse and hold unchanged.
The Jr2's SRAM is an ISSI IS61WV102416FBLL-8BLI (1M x 16, 8 ns); its own address-setup
requirement is zero, so the extra tick is margin for the FPGA's address-output path.
Nested inside `FASTWR_LATE`, so the K2 core is unaffected.

## Also in this core
- Mouse pointer pixel gated on the enable bit: no more solid block after a reset with the mouse
  unplugged; vtio no longer has to park the pointer off-screen.
- MIDI control register ($FF30) edition 2: offset 0 reads Tx-FIFO-empty in bit 3 and Rx-FIFO-empty
  in bit 2; bit 1 resets both FIFOs (write it back to 0 to release). Full address decode, FIFO
  reset-busy gating, resynchronised flags.
- No ILA. OS-9 palette and bannerfont in the core as in rc10.

## Not changed
Fast-write data path, 24-tick frames, DriveWire, SD, WizFi. The K2 stays on rc10.
