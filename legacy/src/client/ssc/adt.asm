*--------------------------------
* APPLE DISK TRANSFER 1.23
* BY PAUL GUERTIN
* PG@SFF.NET (ALL IN LOWER CASE)
* OCTOBER 13TH, 1994 -- 1999
* DISTRIBUTE FREELY
*--------------------------------
         LST OFF

* THIS PROGRAM TRANSFERS A 16-SECTOR DISK
* TO A 140K MS-DOS FILE AND BACK. THE FILE
* FORMAT IS COMPATIBLE WITH RANDY SPURLOCK'S
* APL2EM EMULATOR.
* SSC OR COMPATIBLE HARDWARE IS REQUIRED.
* IIGS REQUIRES SSC OR COMPATIBLE CARD.

* VERSION HISTORY:

* VERSION 1.23 November 2005
* Knut Roll-Lund and Ed Eastman
* - Added 115200b rate for SSC card
* - Added additional baud rates to
*   Windows and DOS verisons
* - added buffering to DIR handling
*   so it works on higher baudrates

* VERSION 1.22 CHANGES "ABOUT" MSG

* VERSION 1.21 FILLS UNREADABLE SECTORS WITH ZEROS

* VERSION 1.20
* - HAS A CONFIGURATION MENU
* - HAS A DIRECTORY FUNCTION
* - ABORTS INSTANTLY IF USER PUSHES ESCAPE
* - FIXES THE "256 RETRIES" BUG
* - HAS MORE EFFICIENT CRC ROUTINES

* VERSION 1.11 SETS IOBVOL TO 0 BEFORE CALLING RWTS

* VERSION 1.10 ADDS THESE ENHANCEMENTS:
* - DIFFERENTIAL RLE COMPRESSION TO SPEED UP TRANSFER
* - 16-BIT CRC ERROR DETECTION
* - AUTOMATIC RE-READS OF BAD SECTORS

* VERSION 1.01 CORRECTS THE FOLLOWING BUGS:
* - INITIALIZATION ROUTINE CRASHED WITH SOME CARDS
* - FULL 8.3 MS-DOS FILENAMES NOW ACCEPTED

* VERSION 1.00 - FIRST PUBLIC RELEASE


* CONSTANTS

ESC      EQU $9B           ;ESCAPE KEY
ACK      EQU $06           ;ACKNOWLEDGE
NAK      EQU $15           ;NEGATIVE ACKNOWLEDGE
PARMNUM  EQU 8             ;NUMBER OF CONFIGURABLE PARMS

* ZERO PAGE LOCATIONS (ALL UNUSED BY DOS, BASIC & MONITOR)

MSGPTR   EQU $6            ;POINTER TO MESSAGE TEXT (2B)
SECPTR   EQU $8            ;POINTER TO SECTOR DATA  (2B)
TRKCNT   EQU $1E           ;COUNTS SEVEN TRACKS     (1B)
CRC      EQU $EB           ;TRACK CRC-16            (2B)
PREV     EQU $ED           ;PREVIOUS BYTE FOR RLE   (1B)
YSAVE    EQU $EE           ;TEMP STORAGE            (1B)

* BIG FILES

TRACKS   EQU $2000         ;7 TRACKS AT 2000-8FFF (28KB)
CRCTBLL  EQU $9000         ;CRC LOW TABLE         (256B)
CRCTBLH  EQU $9100         ;CRC HIGH TABLE        (256B)

* MONITOR STUFF

CH       EQU $24           ;CURSOR HORIZONTAL POSITION
CV       EQU $25           ;CURSOR VERTICAL POSITION
BASL     EQU $28           ;BASE LINE ADDRESS
INVFLG   EQU $32           ;INVERSE FLAG
CLREOL   EQU $FC9C         ;CLEAR TO END OF LINE
CLREOP   EQU $FC42         ;CLEAR TO END OF SCREEN
HOME     EQU $FC58         ;CLEAR WHOLE SCREEN
TABV     EQU $FB5B         ;SET BASL FROM A
VTAB     EQU $FC22         ;SET BASL FROM CV
RDKEY    EQU $FD0C         ;CHARACTER INPUT
NXTCHAR  EQU $FD75         ;LINE INPUT
COUT1    EQU $FDF0         ;CHARACTER OUTPUT
CROUT    EQU $FD8E         ;OUTPUT RETURN

* MESSAGES

MTITLE   EQU 0             ;TITLE SCREEN
MCONFIG  EQU 2             ;CONFIGURATION TOP OF SCREEN
MCONFG2  EQU 4             ;CONFIGURATION BOTTOM OF SCREEN
MPROMPT  EQU 6             ;MAIN PROMPT
MDIRCON  EQU 8             ;CONTINUED DIRECTORY PROMPT
MDIREND  EQU 10            ;END OF DIRECTORY PROMPT
MFRECV   EQU 12            ;FILE TO RECEIVE:_
MFSEND   EQU 14            ;FILE TO SEND:_
MRECV    EQU 16            ;RECEIVING FILE_    (_ = SPACE)
MSEND    EQU 18            ;SENDING FILE_
MCONFUS  EQU 20            ;NONSENSE FROM PC
MNOT16   EQU 22            ;NOT A 16 SECTOR DISK
MERROR   EQU 24            ;ERROR: FILE_
MCANT    EQU 26            ;|CAN'T BE OPENED.     (| = CR)
MEXISTS  EQU 28            ;|ALREADY EXISTS.
MNOT140  EQU 30            ;|IS NOT A 140K IMAGE.
MFULL    EQU 32            ;|DOESN'T FIT ON DISK.
MANYKEY  EQU 34            ;__ANY KEY:_
MDONT    EQU 36            ;<- DO NOT CHANGE
MABOUT   EQU 38            ;ABOUT ADT...
MTEST    EQU 40            ;TESTING DISK FORMAT
MPCANS   EQU 42            ;AWAITING ANSWER FROM PC

**********************************************************

         ORG $803

         JMP START         ;SKIP DEFAULT PARAMETERS

DEFAULT  DFB 5,0,1,5,1,0,0,0        ;DEFAULT PARM VALUES

*---------------------------------------------------------
* START - MAIN PROGRAM
*---------------------------------------------------------
START    CLD               ;BINARY MODE
         JSR $FE84         ;NORMAL TEXT
         JSR $FB2F         ;TEXT MODE, FULL WINDOW
         JSR $FE89         ;INPUT FROM KEYBOARD
         JSR $FE93         ;OUTPUT TO 40-COL SCREEN

         LDA #0
         STA SECPTR        ;SECPTR ALWAYS PAGE-ALIGNED

         STA STDDOS        ;ASSUME STANDARD DOS INITIALLY
         LDA $B92E         ;SAVE CONTENTS OF DOS
         STA DOSBYTE       ;CHECKSUM BYTES
         CMP #$13
         BEQ DOSOK1        ;AND DECREMENT STDDOS (MAKING
         DEC STDDOS        ;IT NONZERO) IF THE CORRECT
DOSOK1   LDA $B98A         ;BYTES AREN'T THERE
         STA DOSBYTE+1
         CMP #$B7
         BEQ DOSOK2
         DEC STDDOS

DOSOK2   JSR MAKETBL       ;MAKE CRC-16 TABLES
         JSR PARMDFT       ;RESET PARAMETERS TO DEFAULTS
         JSR PARMINT       ;INTERPRET PARAMETERS

REDRAW   JSR TITLE         ;DRAW TITLE SCREEN

MAINLUP  LDY #MPROMPT      ;SHOW MAIN PROMPT
         JSR SHOWMSG       ;AT BOTTOM OF SCREEN
         JSR RDKEY         ;GET ANSWER
         AND #$DF          ;CONVERT TO UPPERCASE
MOD0     BIT $C088         ;CLEAR SSC INPUT REGISTER

         CMP #"S"          ;SEND?
         BNE KRECV         ;NOPE, TRY RECEIVE
         JSR SEND          ;YES, DO SEND ROUTINE
         JMP MAINLUP

KRECV    CMP #"R"          ;RECEIVE?
         BNE KDIR          ;NOPE, TRY DIR
         JSR RECEIVE       ;YES, DO RECEIVE ROUTINE
         JMP MAINLUP

KDIR     CMP #"D"          ;DIR?
         BNE KCONF         ;NOPE, TRY CONFIGURE
         JSR DIR           ;YES, DO DIR ROUTINE
         JMP REDRAW

KCONF    CMP #"C"          ;CONFIGURE?
         BNE KABOUT        ;NOPE, TRY ABOUT
         JSR CONFIG        ;YES, DO CONFIGURE ROUTINE
         JSR PARMINT       ;AND INTERPRET PARAMETERS
         JMP REDRAW

KABOUT   CMP #$9F          ;ABOUT MESSAGE? ("?" KEY)
         BNE KQUIT         ;NOPE, TRY QUIT
         LDY #MABOUT       ;YES, SHOW MESSAGE, WAIT
         JSR SHOWMSG       ;FOR KEY, AND RETURN
         JSR RDKEY
         JMP MAINLUP

KQUIT    CMP #"Q"          ;QUIT?
         BNE MAINLUP       ;NOPE, WAS A BAD KEY
         LDA DOSBYTE       ;YES, RESTORE DOS CHECKSUM CODE
         STA $B92E
         LDA DOSBYTE+1
         STA $B98A
         JMP $3D0          ;AND QUIT TO DOS


*---------------------------------------------------------
* DIR - GET DIRECTORY FROM THE PC AND PRINT IT
* PC SENDS 0,1 AFTER PAGES 1..N-1, 0,0 AFTER LAST PAGE
*---------------------------------------------------------
DIR      JSR HOME          ;CLEAR SCREEN
         LDA #"D"          ;SEND DIR COMMAND TO PC
         JSR PUTC

         LDA PSPEED
         CMP #6
         BNE DIRLOOP

         LDA #/TRACKS      ;GET BUFFER POINTER HIGHBYTE
         STA SECPTR+1      ;SET SECTOR BUFFER POINTER
         LDY #0            ;COUNTER
DIRBUFF  JSR GETC          ;GET SERIAL CHARACTER
         PHP               ;SAVE FLAGS
         STA (SECPTR),Y    ;STORE BYTE
         INY               ;BUMP
         BNE DIRNEXT       ;SKIP
         INC SECPTR+1      ;NEXT 256 BYTES
DIRNEXT  PLP               ;RESTORE FLAGS
         BNE DIRBUFF       ;LOOP UNTIL ZERO

         JSR GETC          ;GET CONTINUATION CHARACTER
         STA (SECPTR),Y    ;STORE CONTINUATION BYTE TOO

         LDA #/TRACKS      ;GET BUFFER POINTER HIGHBYTE
         STA SECPTR+1      ;SET SECTOR BUFFER POINTER
         LDY #0            ;COUNTER
DIRDISP  LDA (SECPTR),Y    ;GET BYTE FROM BUFFER
         PHP               ;SAVE FLAGS
         INY               ;BUMP
         BNE DIRMORE       ;SKIP
         INC SECPTR+1      ;NEXT 256 BYTES
DIRMORE  PLP               ;RESTORE FLAGS
         BEQ DIRPAGE       ;PAGE OR DIR END
         ORA #$80
         JSR COUT1         ;DISPLAY
         JMP DIRDISP       ;LOOP

DIRPAGE  LDA (SECPTR),Y    ;GET BYTE FROM BUFFER
         BNE DIRCONT

         LDY #MDIREND      ;NO MORE FILES, WAIT FOR KEY
         JSR SHOWMSG       ;AND RETURN
         JSR RDKEY
         RTS

DIRLOOP  JSR GETC          ;PRINT PC OUTPUT EXACTLY AS
         BEQ DIRSTOP       ;IT ARRIVES (PC IS RESPONSIBLE
         ORA #$80          ;FOR FORMATTING), UNTIL 00
         JSR COUT1         ;RECEIVED
         JMP DIRLOOP

DIRSTOP  JSR GETC          ;GET CONTINUATION CHARACTER
         BNE DIRCONT       ;NOT 00, THERE'S MORE

         LDY #MDIREND      ;NO MORE FILES, WAIT FOR KEY
         JSR SHOWMSG       ;AND RETURN
         JSR RDKEY
         RTS

DIRCONT  LDY #MDIRCON      ;SPACE TO CONTINUE, ESC TO STOP
         JSR SHOWMSG
         JSR RDKEY
         EOR #ESC          ;NOT ESCAPE, CONTINUE NORMALLY
         BNE DIR           ;BY SENDING A "D" TO PC
         JMP PUTC          ;ESCAPE, SEND 00 AND RETURN

*---------------------------------------------------------
* CONFIG - ADT CONFIGURATION
*---------------------------------------------------------
CONFIG   JSR HOME          ;CLEAR SCREEN
         LDY #MCONFIG      ;SHOW CONFIGURATION SCREEN
         JSR SHOWM1
         LDY #MCONFG2
         JSR SHOWMSG       ;IN 2 PARTS BECAUSE >256 CHARS

         LDY #PARMNUM-1    ;SAVE PREVIOUS PARAMETERS
SAVPARM  LDA PARMS,Y       ;IN CASE OF ESCAPE
         STA OLDPARM,Y
         DEY
         BPL SAVPARM

*--------------- FIRST PART: DISPLAY SCREEN --------------

REFRESH  LDA #3            ;FIRST PARAMETER IS ON LINE 3
         JSR TABV
         LDX #0            ;PARAMETER NUMBER
         LDY #$FF          ;OFFSET INTO PARAMETER TEXT

NXTLINE  STX LINECNT       ;SAVE CURRENT LINE
         LDA #15
         STA CH
         CLC
         LDA PARMSIZ,X     ;GET CURRENT VALUE (NEGATIVE:
         SBC PARMS,X       ;LAST VALUE HAS CURVAL=0)
         STA CURVAL
         LDA PARMSIZ,X     ;X WILL BE EACH POSSIBLE VALUE
         TAX               ;STARTING WITH THE LAST ONE
         DEX

VALLOOP  CPX CURVAL        ;X EQUAL TO CURRENT VALUE?
         BEQ PRINTIT       ;YES, PRINT IT
SKIPCHR  INY               ;NO, SKIP IT
         LDA PARMTXT,Y
         BNE SKIPCHR
         BEQ ENDVAL

PRINTIT  LDA LINECNT       ;IF WE'RE ON THE ACTIVE LINE,
         CMP CURPARM       ;THEN PRINT VALUE IN INVERSE
         BNE PRTVAL        ;ELSE PRINT IT NORMALLY
         LDA #$3F
         STA INVFLG

PRTVAL   LDA #$A0          ;SPACE BEFORE & AFTER VALUE
         JSR COUT1
PRTLOOP  INY               ;PRINT VALUE
         LDA PARMTXT,Y
         BEQ ENDPRT
         JSR COUT1
         JMP PRTLOOP
ENDPRT   LDA #$A0
         JSR COUT1
         LDA #$FF          ;BACK TO NORMAL
         STA INVFLG
ENDVAL   DEX
         BPL VALLOOP       ;PRINT REMAINING VALUES

         STY YSAVE         ;CLREOL USES Y
         JSR CLREOL        ;REMOVE GARBAGE AT EOL
         JSR CROUT
         LDY YSAVE
         LDX LINECNT       ;INCREMENT CURRENT LINE
         INX
         CPX #PARMNUM
         BCC NXTLINE       ;LOOP 8 TIMES

         LDA STDDOS        ;IF NON-STANDARD DOS, WRITE
         BEQ GETCMD        ;"DO NOT CHANGE" ON SCREEN
         LDA #9            ;NEXT TO THE CHECKSUMS OPTION
         JSR TABV
         LDY #23
         STY CH
         LDY #MDONT
         JSR SHOWM1

*--------------- SECOND PART: CHANGE VALUES --------------

GETCMD   LDA $C000         ;WAIT FOR NEXT COMMAND
         BPL GETCMD
         BIT $C010
         LDX CURPARM       ;CURRENT PARAMETER IN X

         CMP #$88
         BNE NOTLEFT
         DEC PARMS,X       ;LEFT ARROW PUSHED
         BPL LEFTOK        ;DECREMENT CURRENT VALUE
         LDA PARMSIZ,X
         SBC #1
         STA PARMS,X
LEFTOK   JMP REFRESH

NOTLEFT  CMP #$95
         BNE NOTRGT
         LDA PARMS,X       ;RIGHT ARROW PUSHED
         ADC #0            ;INCREMENT CURRENT VALUE
         CMP PARMSIZ,X
         BCC RIGHTOK
         LDA #0
RIGHTOK  STA PARMS,X
         JMP REFRESH

NOTRGT   CMP #$8B
         BNE NOTUP
         DEX               ;UP ARROW PUSHED
         BPL UPOK          ;DECREMENT PARAMETER
         LDX #PARMNUM-1
UPOK     STX CURPARM
         JMP REFRESH

NOTUP    CMP #$8A
         BEQ ISDOWN
         CMP #$A0
         BNE NOTDOWN
ISDOWN   INX               ;DOWN ARROW OR SPACE PUSHED
         CPX #PARMNUM      ;INCREMENT PARAMETER
         BCC DOWNOK
         LDX #0
DOWNOK   STX CURPARM
         JMP REFRESH

NOTDOWN  CMP #$84
         BNE NOTCTLD
         JSR PARMDFT       ;CTRL-D PUSHED, RESTORE DEFAULT
NOTESC   JMP REFRESH       ;PARAMETERS

NOTCTLD  CMP #$8D
         BEQ ENDCFG        ;RETURN PUSHED, STOP CONFIGURE

         CMP #ESC
         BNE NOTESC
         LDY #PARMNUM-1    ;ESCAPE PUSHED, RESTORE OLD
PARMRST  LDA OLDPARM,Y     ;PARAMETERS AND STOP CONFIGURE
         STA PARMS,Y
         DEY
         BPL PARMRST
ENDCFG   RTS

LINECNT  HEX 00            ;CURRENT LINE NUMBER
CURPARM  HEX 00            ;ACTIVE PARAMETER
CURVAL   HEX 00            ;VALUE OF ACTIVE PARAMETER
OLDPARM  DS  PARMNUM       ;OLD PARAMETERS SAVED HERE


*---------------------------------------------------------
* PARMINT - INTERPRET PARAMETERS
*---------------------------------------------------------
PARMINT  LDY PDSLOT        ;GET SLOT# (0..6)
         INY               ;NOW 1..7
         TYA
         ORA #"0"          ;CONVERT TO ASCII AND PUT
         STA MTSLT         ;INTO TITLE SCREEN
         TYA
         ASL
         ASL
         ASL
         ASL               ;NOW $S0
         STA IOBSLT        ;STORE IN IOB
         ADC #$89          ;NOW $89+S0
         STA MOD5+1        ;SELF-MOD FOR "DRIVES ON"

         LDY PDRIVE        ;GET DRIVE# (0..1)
         INY               ;NOW 1..2
         STY IOBDRV        ;STORE IN IOB
         TYA
         ORA #"0"          ;CONVERT TO ASCII AND PUT
         STA MTDRV         ;INTO TITLE SCREEN

         LDY PSSC          ;GET SSC SLOT# (0..6)
         INY               ;NOW 1..7
         TYA
         ORA #"0"          ;CONVERT TO ASCII AND PUT
         STA MTSSC         ;INTO TITLE SCREEN
         TYA
         ASL
         ASL
         ASL
         ASL               ;NOW $S0
         ADC #$88
         TAX
         LDA #$0B          ;COMMAND: NO PARITY, RTS ON,
         STA $C002,X       ;DTR ON, NO INTERRUPTS
         LDY PSPEED        ;CONTROL: 8 DATA BITS, 1 STOP
         LDA BPSCTRL,Y     ;BIT, BAUD RATE DEPENDS ON
         STA $C003,X       ;PSPEED
         STX MOD0+1        ;SELF-MODS FOR $C088+S0
         STX MOD2+1        ;IN MAIN LOOP
         STX MOD4+1        ;AND IN GETC AND PUTC
         INX
         STX MOD1+1        ;SELF-MODS FOR $C089+S0
         STX MOD3+1        ;IN GETC AND PUTC

         TYA               ;GET SPEED (0..6)
         ASL
         ASL
         ADC PSPEED        ;6*SPEED IN Y, NOW COPY
         TAY               ;FIVE CHARACTERS INTO
         LDX #4            ;TITLE SCREEN
PUTSPD   LDA SPDTXT,Y
         STA MTSPD,X
         INY
         DEX
         BPL PUTSPD

         LDY #1            ;CONVERT RETRIES FROM 0..7
TRYLUP   LDX PRETRY,Y      ;TO 0..5,10,128
         LDA TRYTBL,X
         STA REALTRY,Y
         DEY
         BPL TRYLUP

         LDX #0            ;IF PCKSUM IS 'NO', WE PATCH
         LDY #0            ;DOS TO IGNORE ADDRESS AND
         LDA PCKSUM        ;DATA CHECKSUM ERRORS
         BNE RWTSMOD
         LDX DOSBYTE+1
         LDY DOSBYTE
RWTSMOD  STX $B98A         ;IS THERE AN APPLE II TODAY
         STY $B92E         ;THAT DOESN'T HAVE >=48K RAM?
         RTS               ;(YES)

SPDTXT   ASC "  003 0021 0042 0084 006900291 K511"
BPSCTRL  DFB $16,$18,$1A,$1C,$1E,$1F,$10
TRYTBL   DFB 0,1,2,3,4,5,10,99


*---------------------------------------------------------
* GETNAME - GET FILENAME AND SEND TO PC
*---------------------------------------------------------
GETNAME  STX DIRECTN       ;TFR DIRECTION (0=RECV, 1=SEND)
         LDY PRMPTBL,X
         JSR SHOWMSG       ;ASK FILENAME
         LDX #0            ;GET ANSWER AT $200
         JSR NXTCHAR
         LDA #0            ;NULL-TERMINATE IT
         STA $200,X
         TXA
         BNE FNAMEOK
         JMP ABORT         ;ABORT IF NO FILENAME

FNAMEOK  LDY #MTEST        ;"TESTING THE DISK"
         JSR SHOWMSG
         LDA #/TRACKS      ;READ TRACK 1 SECTOR 1
         STA IOBBUF+1      ;TO SEE IF THERE'S A 16-SECTOR
         LDA #1            ;DISK IN THE DRIVE
         STA IOBCMD
         STA IOBTRK
         STA IOBSEC
         LDA #/IOB
         LDY #IOB
         JSR $3D9
         BCC DISKOK        ;READ SUCCESSFUL

         LDY #MNOT16       ;NOT 16-SECTOR DISK
         JSR SHOWMSG
         LDY #MANYKEY      ;APPEND PROMPT
         JSR SHOWM1
         JSR AWBEEP
         JSR RDKEY         ;WAIT FOR KEY
         JMP ABORT         ;AND ABORT

DISKOK   LDY #MPCANS       ;"AWAITING ANSWER FROM PC"
         JSR SHOWMSG
         LDA #"R"          ;LOAD ACC WITH "R" OR "S"
         ADC DIRECTN
         JSR PUTC          ;AND SEND TO PC
         LDX #0
FNLOOP   LDA $200,X        ;SEND FILENAME TO PC
         JSR PUTC
         BEQ GETANS        ;STOP AT NULL
         INX
         BNE FNLOOP

GETANS   JSR GETC          ;ANSWER FROM PC SHOULD BE 0
         BNE PCERROR       ;THERE'S A PROBLEM

         JSR TITLE         ;CLEAR STATUS
         LDX DIRECTN
         LDY TFRTBL,X
         JSR SHOWMSG       ;SHOW TRANSFER MESSAGE

SHOWFN   LDA #2            ;AND ADD FILENAME
         STA MSGPTR+1
         LDA #0
         STA MSGPTR
         TAY
         JMP MSGLOOP       ;AND RETURN THROUGH SHOWMSG

PCERROR  PHA               ;SAVE ERROR NUMBER
         LDY #MERROR       ;SHOW "ERROR: FILE "
         JSR SHOWMSG       ;SHOW FILENAME
         JSR SHOWFN
         PLA
         TAY
         JSR SHOWM1        ;SHOW ERROR MESSAGE
         LDY #MANYKEY      ;APPEND PROMPT
         JSR SHOWM1
         JSR AWBEEP
         JSR RDKEY         ;WAIT FOR KEY
         JMP ABORT         ;AND RESTART

DIRECTN  HEX 00
PRMPTBL  DFB MFRECV,MFSEND
TFRTBL   DFB MRECV,MSEND


*---------------------------------------------------------
* RECEIVE - MAIN RECEIVE ROUTINE
*---------------------------------------------------------
RECEIVE  LDX #0            ;DIRECTION = PC-->APPLE
         JSR GETNAME       ;ASK FOR FILENAME & SEND TO PC
         LDA #ACK          ;1ST MESSAGE ALWAYS ACK
         STA MESSAGE
         LDA #0            ;START ON TRACK 0
         STA IOBTRK
         STA ERRORS        ;NO DISK ERRORS YET

RECVLUP  STA SAVTRK        ;SAVE CURRENT TRACK
         LDX #1
         JSR SR7TRK        ;RECEIVE 7 TRACKS FROM PC
         LDX #2
         JSR RW7TRK        ;WRITE 7 TRACKS TO DISK
         LDA IOBTRK
         CMP #$23          ;REPEAT UNTIL TRACK $23
         BCC RECVLUP
         LDA MESSAGE       ;SEND LAST ACK
         JSR PUTC
         LDA ERRORS
         JSR PUTC          ;SEND ERROR FLAG TO PC
         JMP AWBEEP        ;BEEP AND END


*---------------------------------------------------------
* SEND - MAIN SEND ROUTINE
*---------------------------------------------------------
SEND     LDX #1            ;DIRECTION = APPLE-->PC
         JSR GETNAME       ;ASK FOR FILENAME & SEND TO PC
         LDA #ACK          ;SEND INITIAL ACK
         JSR PUTC
         LDA #0            ;START ON TRACK 0
         STA IOBTRK
         STA ERRORS        ;NO DISK ERRORS YET

SENDLUP  STA SAVTRK        ;SAVE CURRENT TRACK
         LDX #1
         JSR RW7TRK        ;READ 7 TRACKS FROM DISK
         LDX #0
         JSR SR7TRK        ;SEND 7 TRACKS TO PC
         LDA IOBTRK
         CMP #$23          ;REPEAT UNTIL TRACK $23
         BCC SENDLUP
         LDA ERRORS
         JSR PUTC          ;SEND ERROR FLAG TO PC
         JMP AWBEEP        ;BEEP AND END


*---------------------------------------------------------
* SR7TRK - SEND (X=0) OR RECEIVE (X=1) 7 TRACKS
*---------------------------------------------------------
SR7TRK   STX WHAT2DO       ;X=0 FOR SEND, X=1 FOR RECEIVE
         LDA #7            ;DO 7 TRACKS
         STA TRKCNT
         LDA #/TRACKS      ;STARTING HERE
         STA SECPTR+1
         JSR HOMECUR       ;RESET CURSOR POSITION

S7TRK    LDA #$F           ;COUNT SECTORS FROM F TO 0
         STA IOBSEC
S7SEC    LDX WHAT2DO       ;PRINT STATUS CHARACTER
         LDA SRCHAR,X
         JSR CHROVER

         LDA WHAT2DO       ;EXECUTE SEND OR RECEIVE
         BNE DORECV        ;ROUTINE

*------------------------ SENDING ------------------------

         JSR SENDSEC       ;SEND CURRENT SECTOR
         LDA CRC           ;FOLLOWED BY CRC
         JSR PUTC
         LDA CRC+1
         JSR PUTC
         JSR GETC          ;GET RESPONSE FROM PC
         CMP #ACK          ;IS IT ACK?
         BEQ SROKAY        ;YES, ALL RIGHT
         CMP #NAK          ;IS IT NAK?
         BEQ S7SEC         ;YES, SEND AGAIN

         LDY #MCONFUS      ;SOMETHING IS WRONG
         JSR SHOWMSG       ;TELL BAD NEWS
         LDY #MANYKEY      ;APPEND PROMPT
         JSR SHOWM1
         JSR AWBEEP
         JSR RDKEY         ;WAIT FOR KEY
         JMP ABORT         ;AND ABORT

*----------------------- RECEIVING -----------------------

DORECV   LDY #0            ;CLEAR NEW SECTOR
         TYA
CLRLOOP  STA (SECPTR),Y
         INY
         BNE CLRLOOP

         LDA MESSAGE       ;SEND RESULT OF PREV SECTOR
         JSR PUTC
         JSR RECVSEC       ;RECEIVE SECTOR
         JSR GETC
         STA PCCRC         ;AND CRC
         JSR GETC
         STA PCCRC+1
         JSR UNDIFF        ;UNCOMPRESS SECTOR

         LDA CRC           ;CHECK RECEIVED CRC VS
         CMP PCCRC         ;CALCULATED CRC
         BNE RECVERR
         LDA CRC+1
         CMP PCCRC+1
         BEQ SROKAY

RECVERR  LDA #NAK          ;CRC ERROR, ASK FOR RESEND
         STA MESSAGE
         BNE S7SEC

*------------------ BACK TO COMMON LOOP ------------------

SROKAY   JSR CHRREST       ;RESTORE PREVIOUS STATUS CHAR
         INC SECPTR+1      ;NEXT SECTOR
         DEC IOBSEC
         BPL S7SEC         ;TRACK NOT FINISHED
         LDA TRKCNT
         CMP #2            ;STARTING LAST TRACK, TURN
         BNE NOTONE        ;DRIVE ON, EXCEPT IN THE LAST
         LDA SAVTRK        ;BLOCK
         CMP #$1C
         BEQ NOTONE
MOD5     BIT $C089

NOTONE   DEC TRKCNT
         BEQ SREND
         JMP S7TRK         ;LOOP UNTIL 7 TRACKS DONE
SREND    RTS

SRCHAR   ASC "OI"          ;STATUS CHARACTERS: OUT/IN
WHAT2DO  HEX 00


*---------------------------------------------------------
* SENDSEC - SEND CURRENT SECTOR WITH RLE
* CRC IS COMPUTED BUT NOT SENT
*---------------------------------------------------------
SENDSEC  LDY #0            ;START AT FIRST BYTE
         STY CRC           ;ZERO CRC
         STY CRC+1
         STY PREV          ;NO PREVIOUS CHARACTER
SS1      LDA (SECPTR),Y    ;GET BYTE TO SEND
         JSR UPDCRC        ;UPDATE CRC
         TAX               ;KEEP A COPY IN X
         SEC               ;SUBTRACT FROM PREVIOUS
         SBC PREV
         STX PREV          ;SAVE PREVIOUS BYTE
         JSR PUTC          ;SEND DIFFERENCE
         BEQ SS3           ;WAS IT A ZERO?
         INY               ;NO, DO NEXT BYTE
         BNE SS1           ;LOOP IF MORE TO DO
         RTS               ;ELSE RETURN

SS2      JSR UPDCRC
SS3      INY               ;ANY MORE BYTES?
         BEQ SS4           ;NO, IT WAS 00 UP TO END
         LDA (SECPTR),Y    ;LOOK AT NEXT BYTE
         CMP PREV
         BEQ SS2           ;SAME AS BEFORE, CONTINUE
SS4      TYA               ;DIFFERENCE NOT A ZERO
         JSR PUTC          ;SEND NEW ADDRESS
         BNE SS1           ;AND GO BACK TO MAIN LOOP
         RTS               ;OR RETURN IF NO MORE BYTES


*---------------------------------------------------------
* RECVSEC - RECEIVE SECTOR WITH RLE (NO TIME TO UNDIFF)
*---------------------------------------------------------
RECVSEC  LDY #0            ;START AT BEGINNING OF BUFFER
RC1      JSR GETC          ;GET DIFFERENCE
         BEQ RC2           ;IF ZERO, GET NEW INDEX
         STA (SECPTR),Y    ;ELSE PUT CHAR IN BUFFER
         INY               ;AND INCREMENT INDEX
         BNE RC1           ;LOOP IF NOT AT BUFFER END
         RTS               ;ELSE RETURN
RC2      JSR GETC          ;GET NEW INDEX
         TAY               ;IN Y REGISTER
         BNE RC1           ;LOOP IF INDEX <> 0
         RTS               ;ELSE RETURN


*---------------------------------------------------------
* UNDIFF -  FINISH RLE DECOMPRESSION AND UPDATE CRC
*---------------------------------------------------------
UNDIFF   LDY #0
         STY CRC           ;CLEAR CRC
         STY CRC+1
         STY PREV          ;INITIAL BASE IS ZERO
UDLOOP   LDA (SECPTR),Y    ;GET NEW DIFFERENCE
         CLC
         ADC PREV          ;ADD TO BASE
         JSR UPDCRC        ;UPDATE CRC
         STA PREV          ;THIS IS THE NEW BASE
         STA (SECPTR),Y    ;STORE REAL BYTE
         INY
         BNE UDLOOP        ;REPEAT 256 TIMES
         RTS


*---------------------------------------------------------
* RW7TRK - READ (X=1) OR WRITE (X=2) 7 TRACKS
* USES A,X,Y. IF ESCAPE, CALLS ABORT
*---------------------------------------------------------
RW7TRK   STX IOBCMD        ;X=1 FOR READ, X=2 FOR WRITE
         LDA #7            ;COUNT 7 TRACKS
         STA TRKCNT
         LDA #/TRACKS      ;START AT BEGINNING OF BUFFER
         STA IOBBUF+1
         JSR HOMECUR       ;RESET CURSOR POSITION

NEXTTRK  LDA #$F           ;START AT SECTOR F (READ IS
         STA IOBSEC        ;FASTER THIS WAY)
NEXTSEC  LDX IOBCMD        ;GET MAX RETRIES FROM
         LDA REALTRY-1,X   ;PARAMETER DATA
         STA RETRIES
         LDA RWCHAR-1,X    ;PRINT STATUS CHARACTER
         JSR CHROVER

RWAGAIN  LDA $C000         ;CHECK KEYBOARD
         CMP #ESC          ;ESCAPE PUSHED?
         BNE RWCONT        ;NO, CONTINUE
         JMP SABORT        ;YES, ABORT

RWCONT   LDA #/IOB         ;GET IOB ADDRESS IN REGISTERS
         LDY #IOB
         JSR $3D9          ;CALL RWTS THROUGH VECTOR
         LDA #"."          ;CARRY CLEAR MEANS NO ERROR
         BCC SECTOK        ;NO ERROR: PUT . IN STATUS
         DEC RETRIES       ;ERROR: SOME PATIENCE LEFT?
         BPL RWAGAIN       ;YES, TRY AGAIN
         ROL ERRORS        ;NO, SET ERRORS TO NONZERO
         JSR CLRSECT       ;FILL SECTOR WITH ZEROS
         LDA #'*'          ;AND PUT INVERSE * IN STATUS

SECTOK   JSR CHRADV        ;PRINT SECTOR STATUS & ADVANCE
         INC IOBBUF+1      ;NEXT PAGE IN BUFFER
         DEC IOBSEC        ;NEXT SECTOR
         BPL NEXTSEC       ;LOOP UNTIL END OF TRACK
         INC IOBTRK        ;NEXT TRACK
         DEC TRKCNT        ;LOOP UNTIL 7 TRACKS DONE
         BNE NEXTTRK
         RTS

RWCHAR   ASC "RW"          ;STATUS CHARACTERS: READ/WRITE
RETRIES  HEX 00
REALTRY  HEX 00,00         ;REAL NUMBER OF RETRIES


*---------------------------------------------------------
* CLRSECT - CLEAR CURRENT SECTOR
*---------------------------------------------------------
CLRSECT  LDA IOBBUF+1      ;POINT TO CORRECT SECTOR
         STA CSLOOP+2
         LDY #0            ;AND FILL 256 ZEROS
         TYA
CSLOOP   STA $FF00,Y
         INY
         BNE CSLOOP
         RTS


*---------------------------------------------------------
* HOMECUR - RESET CURSOR POSITION TO 1ST SECTOR
* CHRREST - RESTORE PREVIOUS CONTENTS & ADVANCE CURSOR
* CHRADV  - WRITE NEW CONTENTS & ADVANCE CURSOR
* ADVANCE - JUST ADVANCE CURSOR
* CHROVER - JUST WRITE NEW CONTENTS
*---------------------------------------------------------
HOMECUR  LDY SAVTRK
         INY               ;CURSOR ON 0TH COLUMN
         STY CH
         JSR TOPNEXT       ;TOP OF 1ST COLUMN
         JMP CHRSAVE       ;SAVE 1ST CHARACTER

CHRREST  LDA SAVCHR        ;RESTORE OLD CHARACTER
CHRADV   JSR CHROVER       ;OVERWRITE STATUS CHAR
         JSR ADVANCE       ;ADVANCE CURSOR
CHRSAVE  LDY CH
         LDA (BASL),Y      ;SAVE NEW CHARACTER
         STA SAVCHR
         RTS

ADVANCE  INC CV            ;CURSOR DOWN
         LDA CV
         CMP #21           ;STILL IN DISPLAY?
         BCC NOWRAP        ;YES, WE'RE DONE
TOPNEXT  INC CH            ;NO, GO TO TOP OF NEXT
         LDA #5            ;COLUMN
NOWRAP   JMP TABV          ;VALIDATE BASL,H

CHROVER  LDY CH
         STA (BASL),Y
         RTS


*---------------------------------------------------------
* UPDCRC - UPDATE CRC WITH CONTENTS OF ACCUMULATOR
*---------------------------------------------------------
UPDCRC   PHA
         EOR CRC+1
         TAX
         LDA CRC
         EOR CRCTBLH,X
         STA CRC+1
         LDA CRCTBLL,X
         STA CRC
         PLA
         RTS


*---------------------------------------------------------
* MAKETBL - MAKE CRC-16 TABLES
*---------------------------------------------------------
MAKETBL  LDX #0
         LDY #0
CRCBYTE  STX CRC           ;LOW BYTE = 0
         STY CRC+1         ;HIGH BYTE = INDEX

         LDX #8            ;FOR EACH BIT
CRCBIT   LDA CRC
CRCBIT1  ASL               ;SHIFT CRC LEFT
         ROL CRC+1
         BCS CRCFLIP
         DEX               ;HIGH BIT WAS CLEAR, DO NOTHING
         BNE CRCBIT1
         BEQ CRCSAVE
CRCFLIP  EOR #$21          ;HIGH BIT WAS SET, FLIP BITS
         STA CRC           ;0, 5, AND 12
         LDA CRC+1
         EOR #$10
         STA CRC+1
         DEX
         BNE CRCBIT

         LDA CRC           ;STORE CRC IN TABLES
CRCSAVE  STA CRCTBLL,Y
         LDA CRC+1
         STA CRCTBLH,Y
         INY
         BNE CRCBYTE       ;DO NEXT BYTE
         RTS


*---------------------------------------------------------
* PARMDFT - RESET PARAMETERS TO DEFAULT VALUES (USES AX)
*---------------------------------------------------------
PARMDFT  LDX #PARMNUM-1
DFTLOOP  LDA DEFAULT,X
         STA PARMS,X
         DEX
         BPL DFTLOOP
         RTS


*---------------------------------------------------------
* AWBEEP - CUTE TWO-TONE BEEP (USES AXY)
*---------------------------------------------------------
AWBEEP   LDA PSOUND        ;IF SOUND OFF, RETURN NOW
         BNE NOBEEP
         LDA #$80          ;STRAIGHT FROM APPLE WRITER ][
         JSR BEEP1         ;(CANNIBALISM IS THE SINCEREST
         LDA #$A0          ;FORM OF FLATTERY)
BEEP1    LDY #$80
BEEP2    TAX
BEEP3    DEX
         BNE BEEP3
         BIT $C030         ;WHAP SPEAKER
         DEY
         BNE BEEP2
NOBEEP   RTS


*---------------------------------------------------------
* PUTC - SEND ACC OVER THE SERIAL LINE (AXY UNCHANGED)
*---------------------------------------------------------
PUTC     PHA
PUTC1    LDA $C000
         CMP #ESC          ;ESCAPE = ABORT
         BEQ SABORT
MOD1     LDA $C089         ;CHECK STATUS BITS
         AND #$70
         CMP #$10
         BNE PUTC1         ;OUTPUT REG FULL, LOOP
         PLA
MOD2     STA $C088         ;PUT CHARACTER
         RTS


*---------------------------------------------------------
* GETC - GET A CHARACTER FROM SERIAL LINE (XY UNCHANGED)
*---------------------------------------------------------
GETC     LDA $C000
         CMP #ESC          ;ESCAPE = ABORT
         BEQ SABORT
MOD3     LDA $C089         ;CHECK STATUS BITS
         AND #$68
         CMP #$8
         BNE GETC          ;INPUT REG EMPTY, LOOP
MOD4     LDA $C088         ;GET CHARACTER
         RTS


*---------------------------------------------------------
* ABORT - STOP EVERYTHING (CALL SABORT TO BEEP ALSO)
*---------------------------------------------------------
SABORT   JSR AWBEEP        ;BEEP
ABORT    LDX #$FF          ;POP GOES THE STACKPTR
         TXS
         BIT $C010         ;STROBE KEYBOARD
         JMP REDRAW        ;AND RESTART


*---------------------------------------------------------
* TITLE - SHOW TITLE SCREEN
*---------------------------------------------------------
TITLE    JSR HOME          ;CLEAR SCREEN
         LDY #MTITLE
         JSR SHOWM1        ;SHOW TOP PART OF TITLE SCREEN

         LDX #15           ;SHOW SECTOR NUMBERS
         LDA #5            ;IN DECREASING ORDER
         STA CV            ;FROM TOP TO BOTTOM
SHOWSEC  JSR VTAB
         LDA #$20
         LDY #38
         STA (BASL),Y
         LDY #0
         STA (BASL),Y
         LDA HEXNUM,X
         INY
         STA (BASL),Y
         LDY #37
         STA (BASL),Y
         INC CV
         DEX
         BPL SHOWSEC

         LDA #"_"          ;SHOW LINE OF UNDERLINES
         LDX #38           ;ABOVE INVERSE TEXT
SHOWUND  STA $500,X
         DEX
         BPL SHOWUND
         RTS


*---------------------------------------------------------
* SHOWMSG - SHOW NULL-TERMINATED MESSAGE #Y AT BOTTOM OF
* SCREEN.  CALL SHOWM1 TO SHOW ANYWHERE WITHOUT ERASING
*---------------------------------------------------------
SHOWMSG  STY YSAVE         ;CLREOP USES Y
         LDA #0
         STA CH            ;COLUMN 0
         LDA #22           ;LINE 22
         JSR TABV
         JSR CLREOP        ;CLEAR MESSAGE AREA
         LDY YSAVE

SHOWM1   LDA MSGTBL,Y      ;CALL HERE TO SHOW ANYWHERE
         STA MSGPTR
         LDA MSGTBL+1,Y
         STA MSGPTR+1

         LDY #0
MSGLOOP  LDA (MSGPTR),Y
         BEQ MSGEND
         JSR COUT1
         INY
         BNE MSGLOOP
MSGEND   RTS


*------------------------ MESSAGES -----------------------

MSGTBL   DA  MSG01,MSG02,MSG03,MSG04,MSG05,MSG06,MSG07
         DA  MSG08,MSG09,MSG10,MSG11,MSG12,MSG13,MSG14
         DA  MSG15,MSG16,MSG17,MSG18,MSG19,MSG20,MSG21
         DA  MSG22

MSG01    ASC "SSC:S"
MTSSC    ASC " ,"
MTSPD    ASC "       "
         INV "+ ADT 1.23 +"
         ASC "   DISK:S"
MTSLT    ASC " ,D"
MTDRV    ASC " ",8D,8D,8D
         INV "  00000000000000001111111111111111222  ",8D
         INV "  "
HEXNUM   INV "0123456789ABCDEF0123456789ABCDEF012  ",8D,00

MSG02    INV " ADT CONFIGURATION ",8D,8D,8D
         ASC "DISK SLOT",8D
         ASC "DISK DRIVE",8D
         ASC "SSC SLOT",8D
         ASC "SSC SPEED",8D
         ASC "READ RETRIES",8D
         ASC "WRITE RETRIES",8D
         ASC "USE CHECKSUMS",8D
         ASC "ENABLE SOUND",00

MSG03    ASC "USE ARROWS AND SPACE TO CHANGE VALUES,",8D
         ASC "RETURN TO ACCEPT, CTRL-D FOR DEFAULTS.",00

MSG04    ASC "SEND, RECEIVE, DIR, CONFIGURE, QUIT? ",00
MSG05    ASC "SPACE TO CONTINUE, ESC TO STOP: ",00
MSG06    ASC "END OF DIRECTORY, TYPE SPACE: ",00

MSG07    ASC "FILE TO RECEIVE: ",00
MSG08    ASC "FILE TO SEND: ",00

MSG09    ASC "RECEIVING FILE ",00
MSG10    ASC "SENDING FILE ",00

MSG11    INV "ERROR:"
         ASC " NONSENSE FROM PC.",00

MSG12    INV "ERROR:"
         ASC " NOT A 16-SECTOR DISK.",00

MSG13    INV "ERROR:"
         ASC " FILE ",00

MSG14    HEX 8D
         ASC "CAN'T BE OPENED.",00

MSG15    HEX 8D
         ASC "ALREADY EXISTS.",00

MSG16    HEX 8D
         ASC "IS NOT A 140K IMAGE.",00

MSG17    HEX 8D
         ASC "DOESN'T FIT ON DISK.",00

MSG18    ASC "  ANY KEY: ",00

MSG19    ASC "<- DO NOT CHANGE",00

MSG20    ASC "APPLE DISK TRANSFER 1.24     1994-10-13",8D
         ASC "PAUL GUERTIN (SSC COMPAT HDW REQUIRED.)",00

MSG21    ASC "TESTING DISK FORMAT.",00

MSG22    ASC "AWAITING ANSWER FROM PC.",00


*----------------------- PARAMETERS ----------------------

PARMSIZ  DFB 7,2,7,7,8,8,2,2        ;#OPTIONS OF EACH PARM

PARMTXT  DFB "1,0,"2,0,"3,0,"4,0,"5,0,"6,0,"7,0
         DFB "1,0,"2,0
         DFB "1,0,"2,0,"3,0,"4,0,"5,0,"6,0,"7,0
         DFB "3,"0,"0,0,"1,"2,"0,"0,0,"2,"4,"0,"0,0
         DFB "4,"8,"0,"0,0,"9,"6,"0,"0,0,"1,"9,"2,"0,"0,0
         DFB "1,"1,"5,"K,0
         DFB "0,0,"1,0,"2,0,"3,0,"4,0,"5,0,"1,"0,0,"9,"9,0
         DFB "0,0,"1,0,"2,0,"3,0,"4,0,"5,0,"1,"0,0,"9,"9,0
         DFB "Y,"E,"S,0,"N,"O,0
         DFB "Y,"E,"S,0,"N,"O,0

PARMS
PDSLOT   DFB 5             ;DISK SLOT (6)
PDRIVE   DFB 0             ;DISK DRIVE (1)
PSSC     DFB 1             ;SSC SLOT (2)
PSPEED   DFB 5             ;SSC SPEED (19200)
PRETRY   DFB 1,0           ;READ/WRITE MAX RETRIES (1,0)
PCKSUM   DFB 0             ;USE RWTS CHECKSUMS? (Y)
PSOUND   DFB 0             ;SOUND AT END OF TRANSFER? (Y)

*-------------------------- IOB --------------------------

IOB      HEX 01            ;IOB TYPE
IOBSLT   HEX 60            ;SLOT*$10
IOBDRV   HEX 01            ;DRIVE
         HEX 00            ;VOLUME
IOBTRK   HEX 00            ;TRACK
IOBSEC   HEX 00            ;SECTOR
         DA  DCT           ;DEVICE CHAR TABLE POINTER
IOBBUF   DA  TRACKS        ;SECTOR BUFFER POINTER
         HEX 00,00         ;UNUSED
IOBCMD   HEX 01            ;COMMAND (1=READ, 2=WRITE)
         HEX 00            ;ERROR CODE
         HEX FE            ;ACTUAL VOLUME
         HEX 60            ;PREVIOUS SLOT
         HEX 01            ;PREVIOUS DRIVE
DCT      HEX 00,01,EF,D8   ;DEVICE CHARACTERISTICS TABLE

*-------------------------- MISC -------------------------

DOSBYTE  HEX 00,00         ;DOS BYTES CHANGED BY ADT
STDDOS   HEX 00            ;ZERO IF "STANDARD" DOS
SAVTRK   HEX 00            ;FIRST TRACK OF SEVEN
SAVCHR   HEX 00            ;CHAR OVERWRITTEN WITH STATUS
MESSAGE  HEX 00            ;SECTOR STATUS SENT TO PC
PCCRC    HEX 00,00         ;CRC RECEIVED FROM PC
ERRORS   HEX 00            ;NON0 IF AT LEAST 1 DISK ERROR
