# WildBits Jr2 core v8 rc17 - line engine and DMA

Built 2026-09-23 17:51 (recipe `fpga/build_jr2_rc17_line_fast_2.tcl`, WNS +0.019 ns). Shipped as
`wildbits_jr2_6809_v8_rc17.bit` / `.bin` / `.mcs`.

What changed since rc16:

- **Line drawer no longer drops pixels.** Every pop of the Bresenham FIFO now lands in an SRAM slot the CPU does
  not own: the engine is held off around the CPU's read slot, the fast-write hold and the stock late write, and
  the address/pixel FIFO was rebuilt (LINEDRAW_AddyPixel_FIFO) so a pop never straddles the CPU's claim. Diagonal,
  shallow and steep lines read back complete (linetest, tests folder).
- **DMA logic operations.** New register DMA_OP ($FED4): bits 2:0 select COPY, OR, AND, XOR or MASK (nibble),
  bit 3 inverts the result, bit 7 reads 1 on a core that implements it. Defined in `defs/wildbits.d`; exercised by
  `dmaxfer` (step 6 and the 6a-6h tests) in the level 2 CMDS.
- **DMA handshake.** Bus grant / DMA active / drain are sequenced so a transfer and the CPU never write the same
  SRAM slot.
- **Faster I/O writes** (TURBO_FASTIOWRITE): a CPU write to the $Cx / VICKY register pages completes in a fast
  frame like a RAM write.

An rc16 disk runs on rc17. The Jr2's SRAM write-slot geometry (three ticks of address setup) is unchanged.
