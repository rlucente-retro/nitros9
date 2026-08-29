*******************************************************
*
* DWWrite
*    Send a packet to the DriveWire server.
*    Serial data format:  1-8-N-1
*
* Entry:
*    X  = starting address of data to send
*    Y  = number of bytes to send
*
* Exit:
*    X  = address of last byte sent + 1
*    Y  = 0
*    All others preserved
*

DWWrite             pshs      a,cc                preserve registers
                    orcc      #IntMasks           mask interrupts
write_loop@         lda       ,x+                 get byte from buffer
                    sta       >WizFi.Base+WizFi_DataReg
                    leay      -1,y                decrement byte counter
                    bne       write_loop@         loop if more to send
                    puls      cc,a,pc             restore registers and return
