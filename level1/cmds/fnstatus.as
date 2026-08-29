********************************************************************
* fnstatus - show FujiNet adapter status
*
* Prints the adapter configuration (FUJI$GetAdapterCfg) and the
* wifi connection state (FUJI$GetWifiStatus).
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/05/10  OpenAI
* Created.
*   2      2026/07/13  Andrew Diller
* Reworked around the FujiNet transaction protocol (lib/fuji.as);
* now reports the adapter configuration.

* AdapterConfig field offsets (fujinet-firmware fujiDevice.h)
CFGSSID             equ       0                   char[33]
CFGHOST             equ       33                  char[64]
CFGIP               equ       97                  uint8[4]
CFGGATE             equ       101                 uint8[4]
CFGMASK             equ       105                 uint8[4]
CFGDNS              equ       109                 uint8[4]
CFGMAC              equ       113                 uint8[6]
CFGBSSID            equ       119                 uint8[6]
CFGVER              equ       125                 char[15]

ADPCFGSZ            equ       140                 sizeof AdapterConfig

                    section   __os9
type                equ       Prgrm
lang                equ       Objct
attr                equ       ReEnt
rev                 equ       $00
edition             equ       2
stack               equ       200
                    endsect

                    section   bss
netpath             rmb       1
wifista             rmb       1
request             rmb       2
config              rmb       ADPCFGSZ+1
                    endsect

                    section   code

__start             lbsr      NOpen
                    lbcs      errex
                    sta       netpath,u
                    lbsr      FBReady
                    lbcs      closeerr

                    leax      request,u
                    ldd       #OP_FUJI*256+FUJI$GetAdapterCfg
                    std       ,x
                    ldy       #2
                    lda       netpath,u
                    lbsr      FBCmd
                    lbcs      closeerr

                    leax      config,u
                    ldy       #ADPCFGSZ
                    lda       netpath,u
                    lbsr      FBRead
                    lbcs      closeerr
                    leax      config,u
                    clr       ADPCFGSZ,x     terminate the last field

                    lbsr      PrintLbl
                    fcc       /version:  /
                    fcb       $00
                    leax      config+CFGVER,u
                    lbsr      PUTS
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /hostname: /
                    fcb       $00
                    leax      config+CFGHOST,u
                    lbsr      PUTS
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /ssid:     /
                    fcb       $00
                    leax      config+CFGSSID,u
                    lbsr      PUTS
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /ip:       /
                    fcb       $00
                    leax      config+CFGIP,u
                    lbsr      PrintIP
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /gateway:  /
                    fcb       $00
                    leax      config+CFGGATE,u
                    lbsr      PrintIP
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /netmask:  /
                    fcb       $00
                    leax      config+CFGMASK,u
                    lbsr      PrintIP
                    lbsr      PUTCR

                    lbsr      PrintLbl
                    fcc       /dns:      /
                    fcb       $00
                    leax      config+CFGDNS,u
                    lbsr      PrintIP
                    lbsr      PUTCR

* wifi connection state
                    leax      request,u
                    ldd       #OP_FUJI*256+FUJI$GetWifiStatus
                    std       ,x
                    ldy       #2
                    lda       netpath,u
                    lbsr      FBCmd
                    lbcs      closeerr
                    leax      wifista,u
                    ldy       #1
                    lda       netpath,u
                    lbsr      FBRead
                    lbcs      closeerr

                    lbsr      PrintLbl
                    fcc       /wifi:     /
                    fcb       $00
                    lda       wifista,u
                    cmpa      #3                  3 = connected
                    bne       notconn
                    lbsr      PRINTS
                    fcc       /connected/
                    fcb       $00
                    lbsr      PUTCR
                    bra       closeok
notconn             lbsr      PrintLbl
                    fcc       /not connected (/
                    fcb       $00
                    clra
                    ldb       wifista,u
                    lbsr      PRINT_DEC
                    ldb       #')
                    lbsr      PUTC
                    lbsr      PUTCR

closeok             clrb
closeerr            pshs      b,cc
                    lda       netpath,u
                    os9       I$Close
                    puls      b,cc
errex               bcc       cleanex
                    os9       F$PErr
cleanex             os9       F$Exit

* print null-terminated label immediately following call without newline
PrintLbl            pshs      x,u
                    ldx       4,s                 X = start of label string
                    tfr       x,u
lbl_loop@           tst       ,u+
                    bne       lbl_loop@
                    stu       4,s                 update return address past null byte
                    leau      -1,u                U = null byte address
                    tfr       u,d
                    subd      #0                  set flags
                    pshs      x
                    subd      ,s++                D = string length
                    tfr       d,y                 Y = byte count to print
                    lda       #1                  Path 1 = stdout
                    os9       I$Write
                    puls      x,u,pc

* print four bytes at X as a dotted decimal address
PrintIP             pshs      x
                    ldb       #4
prtip1              pshs      b,x
                    clra
                    ldb       ,x
                    lbsr      PRINT_DEC
                    puls      b,x
                    leax      1,x
                    decb
                    beq       prtip2
                    pshs      b,x
                    ldb       #'.
                    lbsr      PUTC
                    puls      b,x
                    bra       prtip1
prtip2              puls      x,pc

                    endsect
