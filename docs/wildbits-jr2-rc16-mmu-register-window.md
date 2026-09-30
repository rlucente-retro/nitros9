# WildBits Jr2 core v8_rc16 (built 2026-09-13)

rc16 = rc15 with two changes in the shared MMU register block, both machines alike.

**1. MMU register writes no longer leak into RAM.** A CPU write to the task or LUT registers ($FFA0-$FFAF)
was also going down the memory path, translated like any other address: slot 7's block x $2000 + $1FA0-$1FAF
received the task number on every system call and interrupt taken from user state (the register window sat
outside the fixed-I/O decode that inhibits RAM for the rest of the $FFxx page). It was harmless while slot 7 held
a program or a data page whose top three pages are unused - the kernel's 3-page rule keeps them so - and showed
up as one wrong byte whenever slot 7 held a graphics block. Caught with an in-core logic analyser on the K2:
the SWI2 entry's `sta >DAT.Task` at $FDAA writing task 0 into physical RAM. rc16 inhibits RAM, flash and
expansion memory for the whole $FFA0-$FFAF window; reads are unchanged.

**2. FLASHDIS, MMU_IO_CTRL $FFA1 bit 2** (reset 0): 0 = LUT blocks $40-$7F are the flash and $80-$9F the
expansion connector, as before; 1 = those 96 blocks are RAM at chip bytes $08_0000-$13_FFFF (768 KB more of
the 2 MB SRAM). Read-only bit 7 = 1 says the bit is implemented (earlier cores read back what was written).
Nothing in this kit's kernel sets it yet; the bit is for the coming max-RAM kernel, which probes bit 7 first.
Any code that writes $FFA1 must read-modify-write it - an absolute store clears FLASHDIS and pulls the RAM
out from under whatever runs in those blocks.

Everything else - the identity RAM windows ($A0-$BF at $14_0000, $D0-$EF at $1A_0000), HIRES4, the 1 MB
kernel pairing (vtio Blk2Addr = block x $2000) - is unchanged from rc15; an rc15 disk runs on rc16.

## Timing
All constraints met: WNS +0.173 ns, WHS +0.004 ns, 0 failing endpoints; built 2026-09-13 21:36. Scheduler and SRAM constraints unchanged from rc13.
