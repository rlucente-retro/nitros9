*******************************************************
*
* DWRead
*    Receive a response from the DriveWire server.
*    Times out if serial port goes idle for more than 1.4 (0.7) seconds.
*    Serial data format:  1-8-N-1
*
* Entry:
*    X  = starting address where data is to be stored
*    Y  = number of bytes expected
*
* Exit:
*    CC = carry set on framing error, Z set if all bytes received
*    X  = starting address of data received
*    Y  = checksum
*    U is preserved.  All accumulators are clobbered
*


DWRead              clra                          clear carry (no framing error)
                    clrb
                    pshs      u,x,d,cc            preserve registers
 
                    leau      ,x
                    ldx       #$0000

                    orcc      #IntMasks           mask interrupts

loop@               ldd       #$0000              store counter
                    std       1,s
loop2@              ldd       WizFi.Base+WizFi_RxD_WR_Cnt
                    bne       getbyte@            if available, get byte
                    mul                           extend the timeout much longer due to faster CPU
                    mul
                    mul
                    mul
                    ldd       1,s
                    addb      #$01
                    adca      #$00
                    std       1,s
                    cmpd      #$0000
                    bne       loop2@
                    lda       ,s                  get CC off stack
                    anda      #^$04               clear the Z flag to indicate not all bytes received.
                    sta       ,s
                    bra       bye@
getbyte@            ldb       WizFi.Base+WizFi_DataReg get the data byte
                    stb       ,u+                 save off acquired byte
                    abx                           update checksum
                    leay      ,-y                 decrement Y
                    bne       loop@               branch if more to obtain
                    leay      ,x                  return checksum in Y
bye@                puls      cc,d,x,u,pc         restore registers and return
