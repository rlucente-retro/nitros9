# WildBits WizFi Driver Hardening — Remote Shell over /wz0–/wz3

**Date:** 2026-08-31 (branch `wb/wizfi_tx_packets`)
**File changed:** `level1/wildbits/modules/wizfi.asm`
**Field verdict:** no dropped keystrokes and no protocol leaks after
heavy interactive + bulk (`dir` loop) testing over a PuTTY session.

## Background

The 2026-08-26 rework removed the Timer0 machinery and left packet-mode
TX kicking a CIPSEND on every CR/LF — one packet per output line, and
interactive echo traffic produced tiny packets with no coalescing. The
goal was to re-employ the old Timer0 behavior (dump the TX buffer
periodically so packet sizes track shell activity) **without giving
Timer0 back**. The batching itself was straightforward; making it
survive a real remote shell exposed four stacked defects, each found by
field symptoms and fixed in sequence.

## The batching design (what Timer0 became)

A repeating 1-tick **F$VIRQ** on the 60Hz clock (installed vrn.asm
style: an F$IRQ entry polls the packet's own `Vi.Stat` byte; `TickSvc`
clears `Vi.IFlag`, keeping the $80 repeat marker) drains the output
ring. Socket bytes on `/wz0–/wz3` coalesce for up to 16.7ms and leave
as **one CIPSEND sized by activity**. `Write`'s packet-mode per-CR kick
is replaced by a nearly-full early flush (`TXTHRESH` = 192 of the
256-byte ring) so bulk streams aren't throttled to tick pace. Raw
`/wz` (the AT command channel) keeps its per-byte drain untouched.
Install failure degrades soft — threshold kick and the WizFi-edge drain
still flush; no interrupt is load-bearing. `Term` removes the VIRQ and
both poll-table entries (IOMan removal matches on the static pointer,
one entry per call).

## Root cause 1: handshake loops destroyed interleaved receive

**Symptom:** shell missed typed characters; typing had to be slow.

The CIPSEND handshake's `"> "` prompt-wait and "SEND OK" purge popped
the RX FIFO indiscriminately — any `+IPD` keystroke data arriving
during a handshake was consumed as if it were response text. The flaw
predates the batching, but per-CR kicks only handshook at line ends;
the tick flush handshakes *while the user is typing*, sixty times a
second.

**Fix — `HsPop`:** every byte popped during a handshake runs through
`PktByte` (the existing +IPD state machine) first. Payload bytes are
parked for their socket; header-in-progress bytes are consumed; only
genuine response noise reaches the prompt/purge matchers.

## Root cause 2: the parking lot was one byte deep

**Symptom:** still missing characters; output corrupted during `dir`.

`ParkOther` parked a **single byte** per channel (`vpr_data`) — every
multi-byte `+IPD` run arriving mid-handshake overwrote the slot byte by
byte, keeping only the last. Worse, `GetVpPtr` used a 4-byte stride for
5-byte slot records, so adjacent channels' slots **overlapped by one
byte**. And the documented gap remained: direct-pop readers never
retrieved parked bytes at all.

**Fix — per-channel receive queues:** the `D.WZStatTbl` page now holds
8-byte slot records (stride fixed, no overlap) plus four **32-byte
rings** (`$20 + chan*32`; depth is one equate, `vpq_size`). `ParkOther`
enqueues (overwriting oldest on overflow); `Read` **dequeues before
polling the FIFO** — which also closes the old multi-socket hand-off
gap. `vpr_stat` bit 7 now means "queue non-empty" and stays compatible
with the SS.Ready pollers.

## Root cause 3: the tick flush launched into incoming traffic

**Symptom:** unnecessary handshake/traffic collisions at the worst
moments.

**Fix:** `TickSvc` checks `RxFCheck` and defers its flush one tick when
inbound bytes are waiting. With `HsPop`, collisions are *safe*; this
makes them *rare*. `Write`'s threshold kick still bounds output latency
when the ring fills.

## Root cause 4: prompt timeout sent payload blind — stream desync

**Symptom (rare, under sustained bulk output):** the literal text
`AT+CIPSEND=0,1` printed at the remote terminal; truncated `dir`
output.

Under load the module sometimes answers a CIPSEND with `busy p...`
instead of `"> "`. The old path "no prompt: send anyway" pushed payload
into **command mode**, desynchronizing the handshake stream — a later
command line then rode out inside a stale `">"` data-collection phase
and appeared on the wire as socket data.

**Fix — abort and retry:** if the prompt never arrives, the burst is
**aborted**. `OutPktPickup` has not advanced at that point, so the ring
is intact and the identical bytes retry cleanly on the next tick or
threshold kick. A busy module now costs one invisible tick instead of a
desync cascade.

## Module CRC lineage (`ident wizfi`)

| CRC | Revision |
|---|---|
| `$A36AC6` | plain post-Timer0 driver (main) |
| `$B25259` | + tick batching |
| `$7387BB` | + HsPop, receive queues, stride fix, Read dequeue |
| `$E1BEA2` | + abort-on-no-prompt — **field-verified good** |

## Notes for future work

- `vpq_size equ 32` is the tuning knob if extreme input bursts during
  heavy output ever shed oldest bytes; the stat page has room for 64.
- The handshake waits still run IRQ-masked (bounded, ~hundreds of ms
  worst case per timeout). If bulk throughput needs another step,
  moving the prompt/purge waits out of masked context is the next
  lever.
- Never level-trigger on this interrupt controller (poller poisoning);
  Timer0 remains free for other uses.
- lwasm gotcha: the `os9` macro breaks `@`-local label scope — loop
  labels that cross an `os9` call must be global.

## WizCon4 — four packet-mode connections (2026-08-31 … 2026-09-02)

The `$E1BEA2` driver handled one remote shell. WizCon4 makes `/wz0`–`/wz3`
four independent packet-mode channels behind the module's `AT+CIPMUX=1`
server (`AT+CIPSERVERMAXCONN=4`), each with its own `tsmon`. What changed,
in the order the field forced it:

### One shared parser, not four

The module delivers one byte stream. With per-device parser state, four
readers popping the same FIFO fragmented `+IPD` headers across each other.
The `+IPD` state machine now lives once in the shared stat page
(`wzp_*`, offsets $A0+), advanced by whichever context pops a byte
(any device's reader, or a writer's `HsPop` during a CIPSEND handshake).
Payload for another channel is parked in that channel's 32-byte ring
(`ParkOther`); a reader always drains its own ring before touching the
FIFO.

### The stat-page pointer collided with the K2 keyboard (the wedge)

`D.WZStatTbl` was `D.SWPage` (DP $03) — a one-byte os9.d slot inside the
K2's `D.RowState` ($00–$08), which `keydrv_k2` rewrites on every keyboard
event. The first keystroke after a listener started zeroed the pointer
and the readers used page $0000 (the kernel DP) as their queue page.
Moved to `D.DbgMem` ($0A–$0B, unused on wildbits). Verify with `9E 0A`
present / `9E 03` absent in the module.

### No interrupt plumbing on the K2

An every-tick `F$VIRQ` opens the clock's poll gate so IOMan walks the
whole IRQ poll table 60×/s — a path an idle K2 never runs, and one it
cannot tolerate (bisect-proven). The driver installs no edge or tick
entries; blocked readers are the TX flush motor instead: every reader
wake (`Sleep1`, ~2 ticks) drains all registered rings (`DrainAll` over
the `wzp_devs` registry). Raw `/wz` still drains per byte in Write.

### Link-gated delivery and hangup emulation

The module's unsolicited `n,CONNECT` / `n,CLOSED` lines are tracked by a
line scanner (`LineWatch`) into `wzp_link` and `wzp_hup` bits. A
packet-mode reader hands bytes to its caller only while its channel is
linked (so `0,CONNECT` can no longer fork logins on `/wz1`–`/wz3`), and a
blocked reader whose channel has a pending hangup returns `E$HangUp`
through the DCD-lost path, so login/shell exit and `tsmon` re-arms —
the connection lifecycle belongs to the driver, not to scripts.

### The first-connection miss

Two causes, both fixed:

1. `LineWatch` only matched at line start; a `> ` prompt or other text
   ahead of the digit made it skip the line. It now matches
   `n,CONNECT`/`n,CLOSED` anywhere in a line.
2. Raw pops (`modem /wz`) bypassed the parser entirely, and the module
   keeps its TCP sessions across a K2 reboot — so a client already
   attached announced `0,CONNECT` while `wiz4up` was still in raw mode,
   nobody set the link bit, and the client's first bytes were dropped.
   The raw pop path now feeds `LineWatch` too (only the line scanner,
   never the `+IPD` framing). Stale prompt/line evidence latched this way
   is harmless: `HsFlags` clears both before each handshake.

Script gotcha found on the way: `modem -t0 /wz` is *wait forever for the
next line* (wizlog1's connect-banner wait). At the end of `wiz4up` it
stalled the script until the first client connected, ate the banner and
the client's first Enter raw, and only then forked the listeners.
Removed from `wiz4up`.

### The remaining "freeze" was not this driver

With four listeners up, the next fork froze the machine after one
character on every driver variant, including `$E1BEA2`. That was the MMU
slot-2 map-window fault in vtio/krn — see `wildbits-mmu-slot-safety.md`.

### Scripts

`wiz4up` (bring-up: CIPMUX=1 server on port 23, four listeners),
`wiz4down`, `wiz4stat` (raw `AT+CIPSTATUS` — only while channels are
quiet), `wiz4mix` (concurrent output stress). They ship on the disks from
`level1/wildbits/scripts`. Do not read `/wz` raw while connections are
active: raw pops bypass the `+IPD` framing.

### Module lineage (continued)

| Bytes / CRC | Revision |
|---|---|
| 56,737-byte source, zlib CRC32 `9FF7A3D5` | the `$E1BEA2` driver re-fingerprinted (the old label came from a different tool) |
| WizCon4L | shared parser + queues, no interrupt plumbing, reader-driven flush |
| + `D.DbgMem` | the K2 keystroke wedge fix |
| WizCon4n | link-gated delivery, hangup emulation, `GetDevChan` null-pointer fix |
| WizCon4p | `LineWatch` matches mid-line |
| WizCon4u — 1,903 bytes, `ident` CRC `$C13ED6` | raw pops feed `LineWatch` — **field-verified: four remote shells, first-connection login** |

### Known cost

Interactive latency. Every output burst — even a single echoed
keystroke — is a full `AT+CIPSEND=n,len` → `>` → data → `SEND OK`
handshake, and rings are flushed on reader wakes. Bulk output streams
fine; a shell feels sluggish. Levers: coalesce flushes, or transparent
mode (`CIPMODE=1`, `wizsv1`/`wizlog1`) for single-connection use.
