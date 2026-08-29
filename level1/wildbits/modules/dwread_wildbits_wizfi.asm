*******************************************************
*
* DWRead
*    Receive a response from the DriveWire server.
*    Times out if serial port goes idle for more than ~1.0 second.
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

loop@               clra
                    clrb
                    std       1,s                 reset 16-bit timeout counter
loop2@              ldd       >WizFi.Base+WizFi_RxD_WR_Cnt
                    bne       getbyte@            if available, get byte
                    ldb       #70                 ~350 cycle delay on 25MHz CPU
dly@                decb
                    bne       dly@
                    ldd       1,s
                    addd      #1                  advance 16-bit counter
                    std       1,s
                    bne       loop2@              loop until 16-bit wrap (~1.0s at 25MHz)
                    lda       ,s                  get CC off stack
                    anda      #^$04               clear Z flag: not all bytes received
                    sta       ,s
                    bra       bye@
getbyte@            ldb       >WizFi.Base+WizFi_DataReg get data byte
                    stb       ,u+                 save acquired byte
                    abx                           update checksum
                    leay      ,-y                 decrement Y
                    bne       loop@               branch if more to obtain
                    leay      ,x                  return checksum in Y
bye@                puls      cc,d,x,u,pc         restore registers and return
