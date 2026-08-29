********************************************************************
* fndiscon - Disconnect from FujiNet bridge
*
* Disconnect sequence:
* 1. Guard delay 1.0s before +++
* 2. Send +++ and wait 1.0s guard delay
* 3. Send AT+CIPCLOSE\r\n, wait 5ms for UART Tx, reset FIFO
* 4. Wait 1.0s for socket teardown
* 5. Mask unused IRQs & clear pending FPGA interrupts ($FE20-$FE23)
* 6. Advise user to power cycle/reset system to restore full performance
********************************************************************

INT_PENDING_0       equ       $FE20
INT_PENDING_1       equ       $FE21
INT_PENDING_2       equ       $FE22
INT_PENDING_3       equ       $FE23

INT_MASK_0          equ       $FE2C
INT_MASK_1          equ       $FE2D
INT_MASK_2          equ       $FE2E
INT_MASK_3          equ       $FE2F

INT_TIMER_0         equ       %00010000
INT_TIMER_1         equ       %00100000

WizFi_Base          equ       $FF20
WizFi_DataReg       equ       $FF21
WizFi_Reset         equ       %00000010

                    section   __os9
type                equ       Prgrm
lang                equ       Objct
attr                equ       ReEnt
rev                 equ       $00
edition             equ       1
stack               equ       200
                    endsect

                    section   bss
timebuf             rmb       6
                    endsect

                    section   code

msg_step1           fcc       "* [1/4] Guard delay 1s..."
                    fcb       C$CR
msg_step1_len       equ       *-msg_step1

msg_step2           fcc       "* [2/4] Sending +++ ..."
                    fcb       C$CR
msg_step2_len       equ       *-msg_step2

msg_step3           fcc       "* [3/4] Sending AT+CIPCLOSE..."
                    fcb       C$CR
msg_step3_len       equ       *-msg_step3

msg_done            fcc       "* [4/4] Disconnected from FujiNet."
                    fcb       C$CR
msg_done_len        equ       *-msg_done

msg_warn            fcc       "* Please cycle power or reset system to restore full performance."
                    fcb       C$CR
msg_warn_len        equ       *-msg_warn

cmd_plus            fcc       "+++"
cmd_plus_len        equ       *-cmd_plus

cmd_close           fcc       "AT+CIPCLOSE"
                    fcb       $0D,$0A
cmd_close_len       equ       *-cmd_close

__start
* Step 1: Initial Guard Delay (1 second quiet time)
                    lda       #1
                    leax      msg_step1,pcr
                    ldy       #msg_step1_len
                    os9       I$WritLn

                    lbsr      Wait1Sec

* Step 2: Send +++ escape sequence
                    lda       #1
                    leax      msg_step2,pcr
                    ldy       #msg_step2_len
                    os9       I$WritLn

                    leax      cmd_plus,pcr
                    ldb       #cmd_plus_len
w_plus@             lda       ,x+
                    sta       >WizFi_DataReg
                    decb
                    bne       w_plus@

* Guard delay after +++ (WizFi switches to AT command mode)
                    lbsr      Wait1Sec

* Step 3: Send AT+CIPCLOSE
                    lda       #1
                    leax      msg_step3,pcr
                    ldy       #msg_step3_len
                    os9       I$WritLn

                    leax      cmd_close,pcr
                    ldb       #cmd_close_len
w_close@            lda       ,x+
                    sta       >WizFi_DataReg
                    decb
                    bne       w_close@

* Wait ~5ms for 13 bytes to finish transmitting at 115200 baud
                    ldx       #5000
tx_wait@            leax      -1,x
                    bne       tx_wait@

* Reset FIFO immediately to clear response bytes
                    lbsr      ResetFIFO

* Wait 1 second for socket close completion
                    lbsr      Wait1Sec

* Final FIFO reset
                    lbsr      ResetFIFO

* Mask unused interrupt groups (UART, WizFi, Timers)
                    lda       #$FF
                    sta       >INT_MASK_1
                    sta       >INT_MASK_2
                    sta       >INT_MASK_3

* Mask Timer 0 & Timer 1 in Group 0 (preserving VKY_SOF and PS2_KBD)
                    lda       >INT_MASK_0
                    ora       #(INT_TIMER_0|INT_TIMER_1)
                    sta       >INT_MASK_0

* Clear all pending interrupt flags in FPGA interrupt controller
                    lda       #$FF
                    sta       >INT_PENDING_0
                    sta       >INT_PENDING_1
                    sta       >INT_PENDING_2
                    sta       >INT_PENDING_3

* Step 4: Disconnected
                    lda       #1
                    leax      msg_done,pcr
                    ldy       #msg_done_len
                    os9       I$WritLn

* Advisory message to power cycle / reset
                    lda       #1
                    leax      msg_warn,pcr
                    ldy       #msg_warn_len
                    os9       I$WritLn

* Exit cleanly
                    clrb
                    os9       F$Exit

*-------------------------------------------------------------------
* ResetFIFO: Resets WizFi hardware FIFO while preserving baud rate
*-------------------------------------------------------------------
ResetFIFO           pshs      a
                    lda       >WizFi_Base
                    ora       #WizFi_Reset
                    sta       >WizFi_Base
                    exg       a,a
                    exg       a,a
                    anda      #^WizFi_Reset
                    sta       >WizFi_Base
                    puls      a,pc

*-------------------------------------------------------------------
* Wait1Sec: Polls F$Time until the second counter increments
*-------------------------------------------------------------------
Wait1Sec            pshs      d,x
                    leax      timebuf,u
                    os9       F$Time
                    lda       5,x                 get current second
we_loop@            leax      timebuf,u
                    os9       F$Time
                    cmpa      5,x
                    beq       we_loop@            poll until second changes
                    puls      d,x,pc

                    endsect
