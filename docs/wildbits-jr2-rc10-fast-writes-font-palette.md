# WildBits Jr2 v8_rc10 — turbo fast RAM writes, OS-9 font and palette in the core

Built 2026-09-04 from the shared turbo MMU (`TyVKy2K2turbo_MMU_FNX6809.v`) with `TURBO_FASTWRITE` enabled,
the same proven write-slot geometry the K2 rc10 ships: data latched at t6, WEn low t7 to t9, slot released t10,
24-tick write frames. This brings the Jr2 to the K2's fix level (rc8 typematic and rc9 shaped strobes did not
apply to the Jr2: no optical scanner, and the shaped flash/cartridge strobes were in the Jr2 since rc6).

## Also in this core
- Text colour LUTs (TEXT_CLR_LUT) initialised with the OS-9 palette (`mif/Text_LUT_OS9_palette.coe`).
- Text font RAM (FONT_CPU_Memory, 4,096 bytes) initialised with the OS-9 bannerfont in BOTH font sets
  (`mif/Font_OS9_bannerfont.coe`). The OS9Boot and FEU bootfiles no longer carry font or palette modules.

## What to expect
- Screen shows the OS-9 font and colours from power-on, including in the FEU.
- Faster RAM writes under turbo (wildspeed should move up from the rc7 figure); reads unchanged.

## Verification to do on hardware (not yet done for this build)
1. FEU "Loading Sector" and a normal boot from the served disk (the failure mode of the early K2 fast-write attempts).
2. `sprtest2`, `format /f1`, a DriveWire copy and `wizi` — the write-path exercisers.
3. `wildspeed` before/after.

## Build notes
Timing report: two setup violations, both on the external SRAM address outputs MEM_A_o[12]/[13]
(-0.218 ns and -1.055 ns against a 1.000 ns output-delay constraint). The K2 constraint file relaxes exactly
these ports with `set_multicycle_path 2 -setup` because the address is held for several 100 MHz cycles before
any strobe; the Jr2 constraint file was never given that relaxation, so the report is stricter than the
hardware needs. Hold slack +0.030 ns. Flash image: MT25QL128, SPIx4, `write_cfgmem -size 16`.

## Write-slot revision (2026-09-04, FASTWR_LATE)
The first rc10 build used the K2's write geometry unchanged: slot claimed at t6, write strobe low t7 to t9,
slot released at t10. On the Jr2 that leaves the SRAM address only one 200 MHz tick (5 ns) to settle, and the
board's slowest path is the MMU map register reaching the address pins. Right after the kernel writes a map
slot, a write could therefore strobe on an address that had not finished settling. The reported symptom was a
shell that stopped responding while the cursor kept blinking, which is what a wedged CPU looks like: the cursor
blink is generated in the core and continues regardless of what the 6809 is doing.

This core moves the write one tick later: strobe low t8 to t10, slot released at t11. Address setup doubles to
two ticks (10 ns); pulse width and address hold are unchanged. The MMU-map-to-address path no longer appears in
the timing violations. The K2 is unaffected: the change is behind a build define the K2 does not set.
