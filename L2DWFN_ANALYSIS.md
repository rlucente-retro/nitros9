# Technical Analysis: NitrOS-9 Level 2 DriveWire over FujiNet (`l2dwfn`)

**Target Directory:** `recipes/wildbits/l2dwfn`  
**Key Scripts & Modules:** `level1/wildbits/scripts/fncon`, `level1/wildbits/cmds/fndiscon.as`, `level1/wildbits/modules/wizfi.asm`, `level1/wildbits/modules/dwread_wildbits_wizfi.asm`, `level1/wildbits/modules/dwwrite_wildbits_wizfi.asm`

---

## Executive Summary

This document captures the technical architecture, operational lifecycle, failure modes, and post-disconnection terminal lag observed in the **NitrOS-9 Level 2 DriveWire over FujiNet (`l2dwfn`)** configuration on Wildbits hardware (Jr2 / K2).

The investigation reveals two distinct mechanisms causing severe system freezes and terminal input lag after running `scripts/fncon` followed by `fndiscon`:

1. **DriveWire Polling on a Dead Socket (Primary Freeze):** When `fndiscon` closes the TCP socket via `AT+CIPCLOSE`, the underlying transport for mounted DriveWire filesystems (`/dd`, `/x0`, etc.) is severed. Any subsequent disk activity causes `DWRead` in `dwread_wildbits_wizfi.asm` to spin in a **1.0-second timeout loop with CPU interrupts completely masked (`orcc #IntMasks`)**. Repeated retry loops lock the CPU, preventing PS/2 keyboard, mouse, and system timer interrupts from being serviced.
2. **Asynchronous AT Response Pollution (Secondary Retries):** When transitioning from transparent streaming mode back to AT command mode, the WizFi360 module asynchronously outputs ASCII status strings (`"\r\nCLOSED\r\n\r\nOK\r\n"`). If these bytes linger in the FPGA hardware FIFO, `DWRead` attempts to parse ASCII characters as binary DriveWire frame headers, triggering checksum failures and repeated 1-second timeout retries.

---

## 1. Recipe Architecture (`recipes/wildbits/l2dwfn`)

In `recipes/wildbits/l2dwfn/recipe.mak`:

```makefile
RECIPE = wildbits_dwfn
OS9FORMAT_CMD = $(OS9FORMAT_DW)
RBF_EXTRA += $(DRIVEWIRE_RBF)
SCF_EXTRA += $(DRIVEWIRE_SCF) wizfi wizfidesc
BOOTMODS_EXTRA += dwio_wizfi $(PIPE)
FUJINET = 1
```

### Key Components:
* **`dwio_wizfi` Transport:** Implements low-level DriveWire block transport (`DWRead`, `DWWrite`, `DWInit`) directly over the WizFi360 hardware FIFO registers (`$FF20`–`$FF2F`).
* **`wizfi` / `wizfidesc` (`/wz`):** Provides the serial character device driver used for modem AT commands, network configuration, and socket establishment.
* **Storage Devices Mounted via DriveWire:** The system storage descriptors (`/dd`, `/x0`, `/x1`, `/x2`, `/x3`) run RBF over `dwio_wizfi`.

---

## 2. Connection Lifecycle (`fncon`)

In `level1/wildbits/scripts/fncon`:

```bash
echo * Connecting to FujiNet bridge at 192.168.1.100:65504
echo AT+CIPMUX=0>/wz
modem /wz
echo AT+CIPMODE=1>/wz
modem /wz
echo AT+CIPSTART="TCP","192.168.1.100",65504>/wz
sleep 180
modem /wz
sleep 60
echo AT+CIPSEND>/wz
sleep 60
deiniz wz
echo * Connected. Checking FujiNet status...
fnstatus
```

### Execution Steps:
1. **Initialize `/wz` (`wizfi.asm:Init`):**
   * On Jr2 (`SYS0_MACHINE_ID == $1A`), programs FPGA **Timer 0** to reload every 350 clock ticks (~72 kHz) to handle WizFi polling, unmasking `INT_TIMER_0` in `INT_MASK_0` and installing `T0IRQ_Pckt` into the OS-9 polling table (`D.PolTbl`).
2. **Open Socket:** Connects to the FujiNet bridge at port 65504 (`AT+CIPSTART="TCP",...`).
3. **Transparent Transmission Mode:** Configures `AT+CIPMODE=1` followed by `AT+CIPSEND` so all subsequent bytes sent to `$FF21` flow directly into the TCP stream.
4. **De-initialize `/wz` (`deiniz wz`):** Calls `wizfi.asm:Term`, which masks `INT_TIMER_0` and removes the timer ISR from `D.PolTbl`.
5. **Active DriveWire State:** All OS-9 DriveWire disk operations now directly communicate with the WizFi FIFO via `dwio_wizfi`.

---

## 3. Disconnection Sequence (`fndiscon`)

In `level1/wildbits/cmds/fndiscon.as`:

1. **Escape Sequence:** Sends `+++` with 1-second guard delays to exit transparent transmission mode and enter AT command mode.
2. **Socket Teardown:** Sends `AT+CIPCLOSE\r\n` to close the TCP connection to port 65504.
3. **FIFO Reset:** Attempts to reset the hardware FIFO using the `WizFi_Reset` bit in `$FF20`.
4. **FPGA Interrupt Masking:**
   * Writes `$FF` to `INT_MASK_1` (masking 16550 UART interrupts).
   * Masks `INT_TIMER_0` and `INT_TIMER_1` in `INT_MASK_0`.
   * Clears pending interrupt flags in `$FE20`–`$FE23`.
5. **Advisory Warning:** Displays `* Please cycle power or reset system to restore full performance.`

---

## 4. Root Causes of Terminal Lag and System Freezes

### A. The 1.0-Second Interrupt-Masked Spin in `DWRead`

In `level1/wildbits/modules/dwread_wildbits_wizfi.asm` (lines 26–39):

```6809
DWRead              orcc      #IntMasks           ; *** MASKS ALL CPU INTERRUPTS ***
loop@               clra
                    clrb
                    std       1,s                 ; Reset 16-bit timeout counter
loop2@              ldd       >WizFi.Base+WizFi_RxD_WR_Cnt
                    bne       getbyte@            ; Bytes in FIFO? (0 when disconnected)
                    ldb       #70                 ; Delay loop (~14 µs @ 25MHz)
dly@                decb
                    bne       dly@
                    ldd       1,s
                    addd      #1                  ; Advance 16-bit counter
                    std       1,s
                    bne       loop2@              ; Loops 65,536 times = ~1.0 SECOND!
```

#### The Mechanism:
1. In `l2dwfn`, the active filesystem (`/dd`, `/x0`) is hosted over DriveWire.
2. Once `fndiscon` closes the TCP socket, the DriveWire server is unreachable.
3. Any subsequent command execution, shell path search (e.g. searching `/dd/cmds`), directory listing, or dirty buffer flush causes the RBF file manager to issue DriveWire read requests.
4. Because the server is disconnected, `WizFi_RxD_WR_Cnt` remains `0`.
5. `DWRead` spins in `loop2@` for **1.0 second per read attempt**.
6. Because `DWRead` executes with **`orcc #IntMasks` (all CPU interrupts disabled)**:
   * **PS/2 Keyboard interrupts (`INT_PS2_KBD`) are blocked.**
   * **Mouse interrupts (`INT_PS2_MOUSE`) are blocked.**
   * **VSYNC 60Hz scheduler ticks (`INT_VKY_SOF`) are blocked.**
7. When the OS retries failed disk operations (typically 2 to 4 retries per sector/block request), the CPU is held in a hard spin for **2 to 4+ continuous seconds**, producing the severe terminal lag and unresponsive keyboard behavior.

---

### B. ASCII AT Response Contamination

1. When `fndiscon` transmits `+++` and `AT+CIPCLOSE\r\n`, the WizFi360 firmware asynchronously emits response text:
   ```text
   \r\nCLOSED\r\n\r\nOK\r\n
   ```
2. The simple reset toggle in `fndiscon` (`WizFi_Reset`) only clears bytes currently buffered in the FPGA. If the WizFi360 transmits trailing status bytes *after* the toggle, those characters remain in the RX FIFO.
3. When `DWRead` executes, it reads these ASCII characters (`'C'`, `'L'`, `'O'`, `'S'`, `'E'`, `'D'`) as DriveWire binary packet headers.
4. The checksum validation fails immediately, forcing DriveWire into repeated retry loops, each compounding the 1-second interrupt-masked delay.

---

## 5. FIFO Draining: Analysis and Implementation

### Can the FIFO Be Drained Reliably?
**Yes.** The WizFi360 produces a bounded response to `AT+CIPCLOSE`. Once the socket is closed and the module emits its final `OK` or `ERROR`, the stream falls silent.

### Reliable Silence-Bounded Drain Loop
Instead of a blind reset pulse, software can poll and drain `WizFi_DataReg` ($FF21) until the hardware reports empty for a continuous quiet period (e.g. ~50ms of sustained silence):

```6809
* Drain FIFO until empty and quiescent
DrainFIFO           ldx       #5000               ; Silence timeout counter (~50ms)
drain_chk@          lda       >WizFi_CtrlReg      ; Read control register ($FF20)
                    bita      #WizFi.RxEmpty      ; Bit 2: RX FIFO empty?
                    bne       quiet_tick@         ; If empty, decrement silence counter
                    lda       >WizFi_DataReg      ; Byte present: read & discard
                    ldx       #5000               ; Reset silence counter
                    bra       drain_chk@
quiet_tick@         leax      -1,x
                    bne       drain_chk@          ; Loop until quiet counter expires
                    rts
```

---

## 6. Why Draining Alone Cannot Prevent the Freezes

While reliably draining the FIFO prevents garbage byte pollution, it **does not prevent `DWRead` from timing out**:

* If the system's root or execution directory (`/dd`, `/x0`) remains bound to DriveWire, any shell activity will continue issuing DriveWire requests to a dead socket.
* An empty FIFO causes `DWRead` to hit its 1-second timeout loop with `orcc #IntMasks` every time a read is attempted.

### Requirements for a Clean Disconnection:
1. **Dismount Active Storage:** Before disconnecting the TCP socket, the user/script must rebind default data and execution directories (`chd` and `chx`) to local physical storage (such as the SD card `/s0` or RAM disk `/r0`).
2. **De-initialize Descriptors:** De-initialize all active DriveWire descriptors (`deiniz x0`, `deiniz dd`, etc.) to prevent OS-9 from polling severed RBF devices.
3. **Drain the FIFO:** Execute the silence-bounded drain loop to clear all residual AT responses.
4. **Close Socket:** Terminate the TCP connection via `AT+CIPCLOSE`.

---

## 7. Conclusion

The `recipes/wildbits/l2dwfn` recipe tightly couples NitrOS-9 storage to a user-space transparent Wi-Fi socket. Because the operating system does not have dynamic hot-plug/unmount handling for DriveWire RBF descriptors, tearing down the bridge with `fndiscon` leaves the storage subsystem stranded in blocking, interrupt-disabled timeout loops.
