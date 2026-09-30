RC20 (Jr2, core built 2026-09-28 12:24, WNS +0.016 / WHS +0.027): DMA logic operations fixed.

Also in rc20: no byte dropped at the vertical-blank hand-off, the first byte of a transfer no longer stale, op fills reach their last byte, byte copies between even and odd addresses land on the right SRAM lane. Same DMA sources as the K2 rc20; proven with dmaxfer ed.4 (UME/dmaxfer on the ume disk) and the engine simulation in wildbits-buildkit/fpga/sim/dma.

Everything else is rc19: 12 Mhz turbo mode, the rc16 MMU register-window RAM inhibit, the rc17 line drawer and DMA handshake.
