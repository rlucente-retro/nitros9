# Wildbits Hardware & Emulator Validation Recipe (`emu_val`)

This recipe builds a specialized NitrOS-9 Level 2 SD Card disk image (`l2_wildbits_emu_valjr2.dsk`) designed to validate hardware features, FPGA registers, and emulator (MAME) subsystems specifically for the **Wildbits Jr2** platform (this is only for the Jr2 and not the K2).

---

## Directory Structure

```text
recipes/wildbits/emu_val/
├── makefile             # Standard NitrOS-9 recipe makefile (LEVEL = 2)
├── recipe.mak           # Recipe configuration, vpath setup, and test inclusion
├── padup256             # 256-byte boundary alignment script for bootfile
├── README.md            # This documentation file
├── tests/               # Diagnostic test source modules (.as)
│   ├── mathtest.as      # Hardware Math Coprocessor ($FEE0-$FEFB) test suite
│   ├── beamtest.as      # TinyVicky II Raster Beam & Line Comparator ($FFD8-$FFDB)
│   ├── dmatest.as       # TinyVicky II 1D/2D DMA Engine (planned hardware)
│   ├── wizfitest.as     # WizFi360 Wi-Fi Hardware, AT Commands, and Group 3 IRQs
│   ├── rtctest.as       # bq4802 Real-Time Clock ($FE40-$FE4F) & NVRAM registers
│   ├── diptest.as       # Hardware Machine ID ($FE07), SYS0/1, and DIP Switches ($FF90)
│   ├── mmutest.as       # MMU LUT Selectors, Constant RAM, Vector RAM, Cartridge Decode
│   ├── uarttest.as      # 16550 UART ($FE60-$FE67) & INTC Group 1 UART IRQ line
│   ├── timertest.as     # 24-bit Timers (0 & 1) & INTC 4-Group Registers ($FE20-$FE3F)
│   └── cursortest.as    # TinyVicky II Video Master Controls & Hardware Text Cursor ($FFC0-$FFD7)
└── scripts/             # Automated test scripts installed to /s0/SCRIPTS/
    └── selftest         # Batch script running all diagnostics in sequence
```

---

## Building the Recipe

From the root of the repository:

```bash
export NITROS9DIR=$(pwd)
make -C $NITROS9DIR/recipes/wildbits/emu_val PLATFORM=jr2 clean all
```

The output disk image is generated at:
`recipes/wildbits/emu_val/l2_wildbits_emu_valjr2.dsk` (4MB standard SD card format).

To clean build artifacts:
```bash
make -C $NITROS9DIR/recipes/wildbits/emu_val clean
```

---

## Running Diagnostics in MAME

Launch MAME with the validation disk image:

```bash
cd $MAMEDIR
./mame wbjr2 -window -skip_gameinfo \
  -hard $NITROS9DIR/recipes/wildbits/emu_val/l2_wildbits_emu_valjr2.dsk \
  -autoboot_command "mathtest\nbeamtest\ndmatest\n" \
  -autoboot_delay 3
```

Or run the automated batch script from the NitrOS-9 shell:
```text
OS9: /s0/SCRIPTS/selftest
```

---

## Adding New Validation Tests

To add a new hardware diagnostic:

1. Place your 6809 assembly source file into `tests/<testname>.as`.
2. Add `<testname>` to `CMDS_EXTRA` in `recipe.mak`:
   ```makefile
   CMDS_EXTRA += mathtest beamtest dmatest <testname>
   ```
3. Update `scripts/selftest` to invoke the new command.
4. Run `make` to compile, link, and package the new test onto the disk image.
