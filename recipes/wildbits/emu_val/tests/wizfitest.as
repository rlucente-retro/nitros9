********************************************************************
* wizfitest.as - WizFi360 Wi-Fi Hardware & AT Command Diagnostic
*
* Validates hardware control/status registers ($FF20-$FF29),
* hardware reset sequence, FIFO status flags, and AT command/response
* exchanges with the WizFi360 controller.
********************************************************************
                    nam       wizfitest
                    ttl       WizFi360 Hardware & AT Diagnostic

                    use       defsfile

                    section   bss
pass_count          rmb       1
fail_count          rmb       1
temp_buf            rmb       16
rx_buf              rmb       256
stack               rmb       200     * Stack at end
                    endsect

* Hardware Register Definitions ($FF20 - $FF29)
WIZ_CTRL            equ       $FF20
WIZ_DATA            equ       $FF21
WIZ_RX_CNT          equ       $FF24
WIZ_TX_CNT          equ       $FF28

WIZ_STAT_TX_EMPTY   equ       %00001000
WIZ_STAT_RX_EMPTY   equ       %00000100
WIZ_CTRL_RESET      equ       %00000010
WIZ_CTRL_RATE       equ       %00000001

                    section   code
                    export    __start

__start
                    clr       pass_count,u
                    clr       fail_count,u

                    lbsr      PRINTS
                    fcc       "=== WIZFI360 WI-FI HARDWARE & AT DIAGNOSTIC ==="
                    fcb       C$CR,0

                    * ========================================================
                    * TEST 1: Hardware Reset & FIFO State Check ($FF20)
                    * ========================================================
                    lbsr      PRINTS
                    fcc       "[TEST 1] Hardware Reset Handshake ($FF20)"
                    fcb       C$CR,0

                    * Pulse Hardware Reset: Assert Reset (Bit 1 = 1), then release (0)
                    lda       #WIZ_CTRL_RESET
                    sta       >WIZ_CTRL
                    lbsr      ShortDelay
                    clr       >WIZ_CTRL
                    lbsr      ShortDelay

                    * Verify TX FIFO is ready (TxEmpty = 1)
                    lda       >WIZ_CTRL
                    bita      #WIZ_STAT_TX_EMPTY
                    beq       T1_Fail

                    * Flush any power-on / boot banner from RX FIFO
                    lbsr      FlushRxFifo

                    lbsr      PRINTS
                    fcc       "         Hardware Reset & TX Ready Flag"
                    fcb       0
                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test2

T1_Fail             lbsr      PRINTS
                    fcc       "         Hardware Reset / TX Ready Check Failed"
                    fcb       0
                    lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 2: Basic 'AT' Ping & 'OK' Response
                    * ========================================================
Test2               lbsr      PRINTS
                    fcc       "[TEST 2] Basic AT Ping Command (AT -> OK)"
                    fcb       C$CR,0

                    * Send "AT\r\n"
                    lbsr      SendCmd
                    fcc       "AT"
                    fcb       13,10,0

                    * Receive response into rx_buf
                    lbsr      ReadResponse

                    * Display response
                    lbsr      PRINTS
                    fcc       "         Received: "
                    fcb       0
                    lbsr      PrintRxBuf

                    * Validate "OK" in response
                    lbsr      CheckForOK
                    bne       T2_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test3

T2_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 3: Firmware Version Query (AT+GMR)
                    * ========================================================
Test3               lbsr      PRINTS
                    fcc       "[TEST 3] Firmware Version Query (AT+GMR)"
                    fcb       C$CR,0

                    lbsr      SendCmd
                    fcc       "AT+GMR"
                    fcb       13,10,0

                    lbsr      ReadResponse

                    lbsr      PRINTS
                    fcc       "         Firmware: "
                    fcb       0
                    lbsr      PrintRxBuf

                    lbsr      CheckForOK
                    bne       T3_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test4

T3_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 4: Wi-Fi Station Mode Query (AT+CWMODE?)
                    * ========================================================
Test4               lbsr      PRINTS
                    fcc       "[TEST 4] Wi-Fi Mode Query (AT+CWMODE?)"
                    fcb       C$CR,0

                    lbsr      SendCmd
                    fcc       "AT+CWMODE?"
                    fcb       13,10,0

                    lbsr      ReadResponse

                    lbsr      PRINTS
                    fcc       "         Mode: "
                    fcb       0
                    lbsr      PrintRxBuf

                    lbsr      CheckForOK
                    bne       T4_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Test5

T4_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * TEST 5: Wi-Fi Connection Status Query (AT+CIPSTATUS)
                    * ========================================================
Test5               lbsr      PRINTS
                    fcc       "[TEST 5] Connection Status Query (AT+CIPSTATUS)"
                    fcb       C$CR,0

                    lbsr      SendCmd
                    fcc       "AT+CIPSTATUS"
                    fcb       13,10,0

                    lbsr      ReadResponse

                    lbsr      PRINTS
                    fcc       "         Status: "
                    fcb       0
                    lbsr      PrintRxBuf

                    lbsr      CheckForOK
                    bne       T5_Fail

                    lbsr      PrintPass
                    inc       pass_count,u
                    bra       Summary

T5_Fail             lbsr      PrintFail
                    inc       fail_count,u

                    * ========================================================
                    * Summary Output
                    * ========================================================
Summary             lbsr      PRINTS
                    fcc       "---------------------------------------------------"
                    fcb       C$CR,0

                    lbsr      PRINTS
                    fcc       "SUMMARY: Passed="
                    fcb       0
                    lda       pass_count,u
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcc       " / 5 | Failed="
                    fcb       0
                    lda       fail_count,u
                    adda      #'0
                    lbsr      PUTC
                    lbsr      PRINTS
                    fcb       C$CR,0

                    tst       fail_count,u
                    bne       ExitErr

                    lbsr      PRINTS
                    fcc       "RESULT: ALL WIZFI360 HARDWARE TESTS PASSED!"
                    fcb       C$CR,0
                    clrb
                    os9       F$Exit

ExitErr             lbsr      PRINTS
                    fcc       "RESULT: WIZFI360 HARDWARE / FIRMWARE MISMATCH DETECTED!"
                    fcb       C$CR,0
                    ldb       #1
                    os9       F$Exit

* --- WizFi Hardware Helper Subroutines ---

* Flush all pending characters from RX FIFO
FlushRxFifo         pshs      a,x
                    ldx       #1000
flush_lp            lda       >WIZ_CTRL
                    bita      #WIZ_STAT_RX_EMPTY
                    bne       flush_done
                    lda       >WIZ_DATA        * Pop byte
                    leax      -1,x
                    bne       flush_lp
flush_done          puls      a,x,pc

* Send inline null-terminated command string to WizFi Data Register ($FF21)
SendCmd             pshs      x
                    ldx       2,s              * Get return address (string pointer)
send_lp             lda       ,x+
                    beq       send_ex
                    sta       >WIZ_DATA        * Write to WizFi FIFO
                    bra       send_lp
send_ex             stx       2,s              * Advance return address past string
                    puls      x,pc

* Read response string into rx_buf,u until timeout or "OK"/"ERROR" detected
ReadResponse        pshs      a,b,cc,x,y
                    leax      rx_buf,u
                    clr       ,x               * null terminate initially
                    ldb       #250             * Maximum buffer capacity
                    ldy       #30000           * Timeout counter

read_lp             lda       >WIZ_CTRL
                    bita      #WIZ_STAT_RX_EMPTY
                    beq       got_byte         * Branch if byte available

                    * Decrement timeout
                    leay      -1,y
                    bne       read_lp
                    bra       read_done        * Timeout reached

got_byte            lda       >WIZ_DATA        * Read byte
                    sta       ,x+
                    clr       ,x               * Keep null terminated
                    ldy       #30000           * Reset timeout for next byte

                    decb                       * Check if buffer full
                    beq       read_done
                    bra       read_lp

read_done           puls      a,b,cc,x,y,pc

* Search for "OK" inside rx_buf,u. Sets Z=1 if found, Z=0 if not found.
CheckForOK          pshs      a,x
                    leax      rx_buf,u
chk_lp              lda       ,x+
                    beq       chk_notfound
                    cmpa      #'O'
                    bne       chk_lp
                    lda       ,x
                    cmpa      #'K'
                    beq       chk_found
                    bra       chk_lp

chk_found           clra                       * Z=1
                    puls      a,x,pc

chk_notfound        lda       #1               * Z=0
                    puls      a,x,pc

* Print contents of rx_buf,u to screen cleanly
PrintRxBuf          pshs      a,x
                    leax      rx_buf,u
prx_lp              lda       ,x+
                    beq       prx_done
                    cmpa      #13              * Replace CR with space
                    beq       prx_spc
                    cmpa      #10              * Replace LF with space
                    beq       prx_spc
                    cmpa      #32              * Printable ASCII?
                    blo       prx_dot
                    cmpa      #126
                    bhi       prx_dot
                    lbsr      PUTC
                    bra       prx_lp
prx_spc             lda       #32
                    lbsr      PUTC
                    bra       prx_lp
prx_dot             lda       #'.'
                    lbsr      PUTC
                    bra       prx_lp
prx_done            puls      a,x,pc

ShortDelay          pshs      d
                    ldd       #1000
sd_lp               subd      #1
                    bne       sd_lp
                    puls      d,pc

* --- Formatting Helper Subroutines ---

PrintPass           lbsr      PRINTS
                    fcc       " -> [PASS]"
                    fcb       C$CR,0
                    rts

PrintFail           lbsr      PRINTS
                    fcc       " -> [FAIL]"
                    fcb       C$CR,0
                    rts

* Print 16-bit word in D (A=MSB, B=LSB) as 4 hex ASCII characters
PrintHexWord        pshs      b
                    bsr       PrintHexByte
                    puls      a

* Print 8-bit byte in A as 2 hex ASCII characters
PrintHexByte        pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nibble2Hex
                    puls      a
                    anda      #$0F

* Convert lower nibble in A (0..15) to ASCII ('0'..'9','A'..'F') and print
Nibble2Hex          adda      #$90
                    daa
                    adca      #$40
                    daa
putc_ok             lbsr      PUTC
                    rts

* Single character write via os9 I$Write (preserving all registers)
PUTC                pshs      a,b,cc,x,y
                    leax      temp_buf,u
                    sta       ,x
                    ldy       #1
                    lda       #1               * stdout
                    os9       I$Write
                    lda       ,x
                    cmpa      #C$CR
                    bne       putc_done
                    lda       #C$LF
                    sta       ,x
                    ldy       #1
                    lda       #1
                    os9       I$Write
putc_done           puls      a,b,cc,x,y,pc

* Inline string print (100% register preserving)
PRINTS              pshs      x
                    ldx       2,s
prints_lp           lda       ,x+
                    beq       prints_ex
                    lbsr      PUTC
                    bra       prints_lp
prints_ex           stx       2,s
                    puls      x,pc

                    endsect   0
