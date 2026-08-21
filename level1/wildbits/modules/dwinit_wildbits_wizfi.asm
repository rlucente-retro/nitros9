DWInit
                    pshs      d
flush@              ldd       WizFi.Base+WizFi_RxD_WR_Cnt
                    beq       flushed@
                    lda       WizFi.Base+WizFi_DataReg
                    bra       flush@
flushed@            clrb
                    andcc     #^Carry
                    puls      d,pc
