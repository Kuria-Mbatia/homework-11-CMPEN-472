;*******************************************************
;* Title:         Simple 24-Hour Clock with Real Time Interrupt
;* 
;* Objective:     CMPEN 472, Homework 8
;*                Basic clock implementation using RTI
;*
;* Revision:      V1.0
;*
;* Date:          March 23, 2025
;*
;* Programmer:    Kuria Mbatia
;*
;* Company:       The Pennsylvania State University
;*                School of Electrical Engineering and Computer Science
;*
;* Algorithm:     Real Time Interrupt based clock
;*                - Uses 2.5ms RTI for timing
;*                - Implements 24-hour clock
;*                - Displays time every second
;*
;* Register use:  A: Display formatting
;*                B: Time calculations
;*                X,Y: Counters, string operations
;*
;* Memory use:    RAM Locations from $3000 for data
;*                RAM Locations from $3100 for program
;*
;* Output:        - Time display on terminal (HH:MM:SS format)
;*                - LED1 toggles every second
;*
;* Comments:      Simple clock implementation that updates every second
;* 
;*******************************************************
;*******************************************************

; export symbols - program starting point
            XDEF        Entry        ; export 'Entry' symbol
            ABSENTRY    Entry        ; for assembly entry point

; include derivative specific macros
PORTA       EQU         $0000
PORTB       EQU         $0001
DDRA        EQU         $0002
DDRB        EQU         $0003

SCIBDH      EQU         $00C8        ; Serial port (SCI) Baud Register H
SCIBDL      EQU         $00C9        ; Serial port (SCI) Baud Register L
SCICR2      EQU         $00CB        ; Serial port (SCI) Control Register 2
SCISR1      EQU         $00CC        ; Serial port (SCI) Status Register 1
SCIDRL      EQU         $00CF        ; Serial port (SCI) Data Register

CRGFLG      EQU         $0037        ; Clock and Reset Generator Flags
CRGINT      EQU         $0038        ; Clock and Reset Generator Interrupts
RTICTL      EQU         $003B        ; Real Time Interrupt Control

CR          equ         $0d          ; carriage return, ASCII 'Return' key
LF          equ         $0a          ; line feed, ASCII 'next line' character

;*******************************************************
; variable/data section
            ORG    $3000             ; RAMStart defined as $3000
                                     ; in MC9S12C128 chip

; 7-segment display digit encoding table (0-9)
; Common cathode 7-segment display pattern
; Segment pattern layout:
;    a
;   ---
;  |   |
; f|   |b
;  | g |
;   ---
;  |   |
; e|   |c
;  |   |
;   ---
;    d   
;
; For digits 0-9, with segment map: 0bABCDEFG (Common cathode patterns)
; To illuminate segments: set bit to 1
; Digits in order: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
segTable    DC.B   $3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F

; Display mode constants
DISP_HOURS  EQU    1         ; Display hours on 7-segment
DISP_MINS   EQU    2         ; Display minutes on 7-segment
DISP_SECS   EQU    3         ; Display seconds on 7-segment
displayMode DS.B   1         ; Current display mode for 7-segment

timeh       DS.B   1                 ; Hour (0-23)
timem       DS.B   1                 ; Minute (0-59)
times       DS.B   1                 ; Second (0-59)
temph       DS.B   1                 ; Temporary hour for validation
tempm       DS.B   1                 ; Temporary minute for validation
temps       DS.B   1                 ; Temporary second for validation
ctr2p5m     DS.W   1                 ; interrupt counter for 2.5 mSec. of time
timeStr     DS.B   9                 ; Buffer for time string (HH:MM:SS\0)
dispFlag    DS.B   1                 ; Display update flag
typingFlag  DS.B   1                 ; Flag indicating user is typing (1=typing)
typewriterMode DS.B   1              ; Flag indicating typewriter mode (1=active)

; Command processing variables
cmdBuffer   DS.B   20                ; Buffer for command input
cmdIndex    DS.B   1                 ; Current position in command buffer
cmdReady    DS.B   1                 ; Flag indicating command is ready to process
errorMsg    DS.B   20                ; Buffer for error messages (reduced from 30)

msg1        DC.B   'Simple Clock', $00     ; Shortened
msg2        DC.B   'Updates every second', $00  ; Shortened
errInvalid  DC.B   'Invalid format', $00   ; Shortened
typewriterMsg1 DC.B   'Typewriter started', $00  ; Shortened
typewriterMsg2 DC.B   'Type below', $00    ; Shortened
msgHourDisp DC.B   'Hours on display', $00  ; Shortened
msgMinDisp  DC.B   'Mins on display', $00   ; Shortened
msgSecDisp  DC.B   'Secs on display', $00   ; Shortened

;*******************************************************
; interrupt vector section
            ORG    $FFF0             ; RTI interrupt vector setup for the simulator
;            ORG    $3FF0             ; RTI interrupt vector setup for the CSM-12C128 board
            DC.W   rtiisr

;*******************************************************
; code section

            ORG    $3100       ; Program starts at $3100 as per requirements
Entry
            LDS    #Entry         ; initialize the stack pointer

            LDAA   #%11111111   ; Set PORTA and PORTB bit 0,1,2,3,4,5,6,7
            STAA   DDRA         ; all bits of PORTA as output
            STAA   PORTA        ; set all bits of PORTA, initialize
            STAA   DDRB         ; all bits of PORTB as output
            STAA   PORTB        ; set all bits of PORTB, initialize

            ; Initialize serial port for 9600 baud
            ldaa   #$0C         ; Enable SCI port Tx and Rx units
            staa   SCICR2       ; disable SCI interrupts
            ldd    #$009C       ; Set SCI Baud Register = $009C => 9600 baud at 24MHz
            std    SCIBDH       ; SCI port baud rate change

            ; Initialize clock variables
            clr    timeh        ; Clear hours
            clr    timem        ; Clear minutes
            clr    times        ; Clear seconds
            clr    dispFlag     ; Clear display flag
            
            ; Initialize command processing
            clr    cmdIndex     ; Clear command index
            clr    cmdReady     ; Clear command ready flag
            clr    errorMsg     ; Clear error message buffer
            clr    typingFlag   ; Clear typing flag
            clr    typewriterMode ; Clear typewriter mode flag
            
            ; Initialize display mode to hours by default
            LDAA   #DISP_HOURS
            STAA   displayMode
            
            ; Display welcome message
            ldx    #msg1
            jsr    printmsg
            jsr    nextline
            ldx    #msg2
            jsr    printmsg
            jsr    nextline
            
            ; Initialize RTI for 2.5ms intervals
            bset   RTICTL,%00011001 ; set RTI: dev=10*(2**10)=2.555msec
            bset   CRGINT,%10000000 ; enable RTI interrupt
            bset   CRGFLG,%10000000 ; clear RTI IF (Interrupt Flag)

            ldx    #0
            stx    ctr2p5m      ; initialize interrupt counter with 0
            
            ; Initialize time string
            ldaa   #'0'
            staa   timeStr      ; Hours tens
            staa   timeStr+1    ; Hours ones
            ldaa   #':'
            staa   timeStr+2    ; Colon
            ldaa   #'0'
            staa   timeStr+3    ; Minutes tens
            staa   timeStr+4    ; Minutes ones
            ldaa   #':'
            staa   timeStr+5    ; Colon
            ldaa   #'0'
            staa   timeStr+6    ; Seconds tens
            staa   timeStr+7    ; Seconds ones
            ldaa   #0
            staa   timeStr+8    ; Null terminator
            
            ; Display initial time with formatting
            jsr    nextline
            
            ; Display "Clock> " prefix
            ldaa   #'C'
            jsr    putchar
            ldaa   #'l'
            jsr    putchar
            ldaa   #'o'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'k'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display initial time
            ldx    #timeStr
            jsr    printmsg
            
            ; Display 5 spaces for padding
            ldaa   #' '
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            ; Display "CMD> " section
            ldaa   #'C'
            jsr    putchar
            ldaa   #'M'
            jsr    putchar
            ldaa   #'D'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display 16 spaces for CMD padding
            ldaa   #' '
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            ; Display "Error> " section
            ldaa   #'E'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'o'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            jsr    nextline
            
            ; Enable interrupts
            cli                 ; enable interrupt, global

mainLoop    
            ; Check if we're in typewriter mode
            ldaa   typewriterMode
            lbne   typewriterLoop   ; If in typewriter mode, handle differently
            
            ; Check for user input
            jsr    getchar
            tsta                
            lbeq   checkCmdReady ; If no input, check if we have a completed command
            
            ; Save the input character
            psha                ; Save the character on stack
            
            ; First character received? Set typing flag and position cursor
            ldab   cmdIndex
            lbne   notFirstChar
            
            ; This is the first character of command - set typing flag immediately
            ldab   #1
            stab   typingFlag   ; Set typing flag immediately
            
            ; Force a display update before starting input to ensure correct positioning
            jsr    displayTime
            
notFirstChar
            ; Get the character back
            pula                ; Restore the character from stack
            
            ; If this is ENTER (CR), don't echo it, just process it
            cmpa   #CR
            lbeq   skipEcho
            
            ; Echo the character immediately so user can see it
            jsr    putchar      ; This ensures the character is immediately visible
            
skipEcho
            ; Process the character
            jsr    processChar
            
            ; No need to redraw the line - just continue
            lbra    mainLoop
            
checkCmdReady
            ; Check if command is ready to process
            ldaa   cmdReady
            lbeq   checkTime
            
            ; Process the command first (to set error message if needed)
            jsr    processCmd
            clr    cmdReady     ; Clear command ready flag
            
            ; Display "Error> " section at current cursor position
            ldaa   #' '         ; Add some space after command
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            ; Display "Error> " section
            ldaa   #'E'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'o'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display error message if it exists
            ldx    #errorMsg
            ldaa   0,x         ; Check first byte of errorMsg
            beq    skipErrorMsg  ; If zero, no error to display
            
            ; Display error message
            jsr    printmsg
            
skipErrorMsg
            ; Now move to next line
            ldaa   #CR              ; Carriage return to beginning of line
            jsr    putchar
            ldaa   #LF              ; Line feed to next line
            jsr    putchar
            
            ; Check if we're in typewriter mode now (after processing q command)
            ldaa   typewriterMode
            lbne   mainLoop         ; If in typewriter mode, don't update time
            
            ; Update time display
            jsr    updateTimeStr    ; Make sure timeStr is updated
            
            ; Clear error message after displaying it once
            ldaa   #0
            staa   errorMsg
            
            ; Force immediate display update
            ldaa   #1
            staa   dispFlag
            
            ; Skip other checks and display time now
            jsr    displayTime
            
            ; Continue with main loop
            lbra   mainLoop
            
checkTime    
            ; Check if it's time to display (dispFlag set by RTI)
            ldaa   dispFlag
            lbeq   mainLoop     ; Use long branch for far target
            
            ; Check if user is typing 
            ldaa   typingFlag
            lbne   clearDispFlag  ; User is typing, don't update display
            
            ; User not typing, update display normally
            lbra   updateDisplay
            
clearDispFlag
            ; Clear the display flag without updating display
            clr    dispFlag
            lbra   mainLoop
            
updateDisplay
            ; Clear display flag
            clr    dispFlag
            
            ; Format and display time
            jsr    displayTime
            lbra   mainLoop

; Typewriter loop - handles continuous character input/output in typewriter mode            
typewriterLoop
            ; In typewriter mode, just echo any character received
            jsr    getchar
            tsta                ; Check if a character was received
            lbeq   typewriterLoop  ; If no input, keep checking
            
            ; Echo the character immediately
            jsr    putchar
            
            ; Continue typewriter loop
            lbra   typewriterLoop

;***********RTI interrupt service routine***************
rtiisr      bset   CRGFLG,%10000000 ; clear RTI Interrupt Flag
            ldx    ctr2p5m
            inx
            stx    ctr2p5m
            
            ; Check if 1 second has passed (400 * 2.5ms = 1000ms)
            cpx    #400
            blo    rtidone
            
            ; Reset counter
            ldx    #0
            stx    ctr2p5m
            
            ; Toggle LED1 and keep track of its state
            brset  PORTB,#%00010000,rtiisr_turnOffLED1 ; If LED1 is on, turn it off
            
            ; Turn on LED1
            bset   PORTB,#%00010000
            bra    rtitimecontinue
            
rtiisr_turnOffLED1
            ; Turn off LED1
            bclr   PORTB,#%00010000
            
rtitimecontinue
            ; Set display flag
            ldaa   #1
            staa   dispFlag
            
            ; Update time
            inc    times        ; Increment seconds
            ldaa   times
            cmpa   #60         ; Check if 60 seconds
            blo    rtisevenseg
            
            ; Reset seconds, increment minutes
            clr    times
            inc    timem
            ldaa   timem
            cmpa   #60         ; Check if 60 minutes
            blo    rtisevenseg
            
            ; Reset minutes, increment hours
            clr    timem
            inc    timeh
            ldaa   timeh
            cmpa   #24         ; Check if 24 hours
            blo    rtisevenseg
            
            ; Reset hours
            clr    timeh
            
rtisevenseg
            ; Now update 7-segment display based on display mode
            ldaa   displayMode
            cmpa   #DISP_HOURS
            bne    rticheckmin
            
            ; Display hours
            ldaa   timeh
            jsr    displayOnSevenSegment
            bra    rtidone
            
rticheckmin cmpa   #DISP_MINS
            bne    rtichecksec
            
            ; Display minutes
            ldaa   timem
            jsr    displayOnSevenSegment
            bra    rtidone
            
rtichecksec
            ; Must be seconds mode
            ldaa   times
            jsr    displayOnSevenSegment
            
rtidone     RTI

;****************displayTime**********************
displayTime psha
            pshb
            pshx
            
            ; Clear line first
            jsr    nextline
            
            ; First make sure the timeStr is up-to-date with current time values
            jsr    updateTimeStr
            
            ; Display "Clock> " prefix
            ldaa   #'C'
            jsr    putchar
            ldaa   #'l'
            jsr    putchar
            ldaa   #'o'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'k'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display formatted time
            ldx    #timeStr
            jsr    printmsg
            
            ; Display 5 spaces for padding
            ldaa   #' '
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            ; Display "CMD> " section
            ldaa   #'C'
            jsr    putchar
            ldaa   #'M'
            jsr    putchar
            ldaa   #'D'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Check if user is typing
            ldaa   typingFlag
            beq    continueDisplay  ; Not typing, continue with display
            
            ; Show command buffer
            ldx    #cmdBuffer
            jsr    printmsg
            
            ; Return while keeping cursor position
            pulx
            pulb
            pula
            rts
            
continueDisplay
            ; Display command buffer if it has content
            ldx    #cmdBuffer
            ldaa   0,x
            beq    emptyCmd     ; If buffer is empty and not typing
            
            ; Display command buffer
            jsr    printmsg
            
            ; Count command length for padding
            ldx    #cmdBuffer
            ldab   #0
cmdLenLoop  ldaa   0,x
            beq    padCmd       ; End of string found
            incb               ; Count character
            inx                ; Next character
            bra    cmdLenLoop
            
emptyCmd    ldab   #0          ; Set length to 0
            
padCmd      
            ; Calculate padding (16 - cmdLength)
            ldaa   #16
            sba                ; A = 16 - B
            
            ; Apply padding if needed
            cmpa   #0
            ble    displayErrorSection ; Skip if no padding needed
            
            ; Display padding spaces
            tab                ; Transfer count to B
padLoop     ldaa   #' '        ; Space character
            jsr    putchar     ; Display space
            decb               ; Decrement count
            bne    padLoop     ; Continue if more needed
            
displayErrorSection
            ; Display "Error> " section
            ldaa   #'E'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'o'
            jsr    putchar
            ldaa   #'r'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display error message if it exists
            ldx    #errorMsg
            ldaa   0,x         ; Check first byte of errorMsg
            beq    displayDone  ; If zero, no error to display
            
            ; Display error message
            jsr    printmsg
            
displayDone pulx
            pulb
            pula
            rts

;****************formatByte**********************
; Formats a byte as two decimal digits
; Input: A = byte to format (0-99)
;        X = pointer to output buffer
; Output: Two ASCII digits stored at X
;         X advanced by 2
formatByte  psha
            pshb
            
            ; Calculate tens and ones digits
            tab                 ; Copy A to B for safe keeping
            ldaa   #0          ; Initialize tens digit
            
divLoop     cmpb   #10         ; Compare value with 10
            blo    divDone     ; If less than 10, we're done
            subb   #10         ; Subtract 10
            inca               ; Increment tens digit
            bra    divLoop     ; Continue loop
            
divDone     
            ; Store tens digit
            adda   #'0'        ; Convert to ASCII
            staa   0,x         ; Store at current position
            inx                ; Move to next position
            
            ; Store ones digit (remainder in B)
            tba                ; Transfer B to A
            adda   #'0'        ; Convert to ASCII
            staa   0,x         ; Store at current position
            inx                ; Move to next position
            
            pulb
            pula
            rts

;***********printmsg***************************
;* Program: Output character string to SCI port, print message
;* Input:   Register X points to ASCII characters in memory
;* Output:  message printed on the terminal connected to SCI port
;* 
;* Registers modified: CCR
;* Algorithm:
;     Pick up 1 byte from memory where X register is pointing
;     Send it out to SCI port
;     Update X register to point to the next byte
;     Repeat until the byte data $00 is encountered
;       (String is terminated with NULL=$00)
;**********************************************
NULL            equ     $00
printmsg        psha                   ;Save registers
                pshx
printmsgloop    ldaa    0,X            ;pick up an ASCII character from string
                                       ;   pointed by X register
                cmpa    #NULL
                beq     printmsgdone   ;end of string yet?
                inx                    ;point to next character
                jsr     putchar        ;if not, print character and do next
                bra     printmsgloop
printmsgdone    pulx 
                pula
                rts
;***********end of printmsg********************

;***************putchar************************
;* Program: Send one character to SCI port, terminal
;* Input:   Accumulator A contains an ASCII character, 8bit
;* Output:  Send one character to SCI port, terminal
;* Registers modified: CCR
;* Algorithm:
;    Wait for transmit buffer become empty
;      Transmit buffer empty is indicated by TDRE bit
;      TDRE = 1 : empty - Transmit Data Register Empty, ready to transmit
;      TDRE = 0 : not empty, transmission in progress
;**********************************************
putchar     brclr SCISR1,#%10000000,putchar   ; wait for transmit buffer empty
            staa  SCIDRL                      ; send a character
            rts
;***************end of putchar*****************

;****************getchar***********************
;* Program: Input one character from SCI port (terminal/keyboard)
;*             if a character is received, other wise return NULL
;* Input:   none    
;* Output:  Accumulator A containing the received ASCII character
;*          if a character is received.
;*          Otherwise Accumulator A will contain a NULL character, $00.
;* Registers modified: CCR
;* Algorithm:
;    Check for receive buffer become full
;      Receive buffer full is indicated by RDRF bit
;      RDRF = 1 : full - Receive Data Register Full, 1 byte received
;      RDRF = 0 : not full, 0 byte received
;**********************************************

getchar     brclr SCISR1,#%00100000,getchar7  ; Check if character available
            ldaa  SCIDRL                      ; Get character from buffer
            rts                               ; Return with character in A
getchar7    clra                              ; No character, return 0
            rts
;****************end of getchar****************

;****************nextline**********************
nextline    psha
            ldaa  #CR              ; move the cursor to beginning of the line
            jsr   putchar          ;   Cariage Return/Enter key
            ldaa  #LF              ; move the cursor to next line, Line Feed
            jsr   putchar
            pula
            rts
;****************end of nextline***************

;****************processChar*********************
; Process an input character
; Input: A = input character
; Output: Updates command buffer and cmdReady flag if CR received
processChar psha                ; Save original character on stack
            pshb
            pshx
            
            ; Get the character from accumulator A (saved on stack)
            ldaa   3,sp         ; Get character from stack (3 bytes up due to pshx, pshb)
            
            ; Check for Enter key
            cmpa   #CR
            beq    cmdComplete
            
            ; Check for command buffer overflow
            ldab   cmdIndex
            cmpb   #18         ; Leave room for null terminator
            bhs    pcDone      ; Ignore if buffer would overflow
            
            ; Store character in command buffer
            ldx    #cmdBuffer
            abx                ; Add B to X to get buffer position
            staa   0,x         ; Store character at position
            
            ; Update command index
            inc    cmdIndex
            
            bra    pcDone
            
cmdComplete
            ; Null-terminate the command buffer
            ldab   cmdIndex
            ldx    #cmdBuffer
            abx                ; Add B to X to get position after last char
            clr    0,x         ; Store null terminator
            
            ; Set command ready flag and clear typing flag
            ldaa   #1
            staa   cmdReady
            clr    typingFlag      ; User is done typing
            
            ; Reset command index for next command
            clr    cmdIndex
            
pcDone      pulx
            pulb
            pula
            rts

;****************processCmd**********************
; Process a completed command from the command buffer
; Input: cmdBuffer contains null-terminated command string
; Output: Updates time variables if valid, error message if not
processCmd  psha
            pshb
            pshx
            
            ; Clear error message as default
            ldaa   #0
            staa   errorMsg
            
            ; Check if command is empty
            ldaa   cmdBuffer
            cmpa   #0
            lbeq   cmdDone      ; If empty, nothing to do
            
            ; Check first character for command type
            cmpa   #'t'
            lbeq   timeCommand  ; If 't', process time command
            cmpa   #'q'
            lbeq   checkQuitCommand  ; If 'q', check if it's just 'q' alone
            cmpa   #'h'
            lbeq   checkHourCommand  ; If 'h', check if it's a valid command
            cmpa   #'m'
            lbeq   checkMinuteCommand  ; If 'm', check if it's a valid command
            cmpa   #'s'
            lbeq   checkSecondCommand  ; If 's', check if it's a valid command
            
            ; Unrecognized command
            lbra   invalidCmd
            
timeCommand
            ; Start parsing after 't'
            ldx    #cmdBuffer
            inx                 ; Point to character after 't'
            
            ; Skip spaces - find first non-space character
skipSpace   ldaa   0,x
            cmpa   #' '
            lbne   checkHours   ; If not space, start parsing time
            inx                 ; Move to next character
            lbra   skipSpace
            
checkHours  
            ; Check if first digit is valid
            ldaa   0,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Check if second digit is valid
            ldaa   1,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Parse hours (now we know we have two valid digits)
            jsr    parseTwoDigits
            cmpa   #24          ; Check if hours < 24
            lbhs   invalidTime
            
            ; Store parsed hours in temporary variable
            staa   temph
            
            ; Check for colon
            ldaa   0,x
            cmpa   #':'
            lbne   invalidTime
            inx                 ; Move past colon
            
            ; Check if first digit of minutes is valid
            ldaa   0,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Check if second digit of minutes is valid
            ldaa   1,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Parse minutes
            jsr    parseTwoDigits
            cmpa   #60          ; Check if minutes < 60
            lbhs   invalidTime
            
            ; Store parsed minutes in temporary variable
            staa   tempm
            
            ; Check for colon
            ldaa   0,x
            cmpa   #':'
            lbne   invalidTime
            inx                 ; Move past colon
            
            ; Check if first digit of seconds is valid
            ldaa   0,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Check if second digit of seconds is valid
            ldaa   1,x
            cmpa   #'0'
            lblo   invalidTime  ; If less than '0', invalid
            cmpa   #'9'
            lbhi   invalidTime  ; If greater than '9', invalid
            
            ; Parse seconds
            jsr    parseTwoDigits
            cmpa   #60          ; Check if seconds < 60
            lbhs   invalidTime
            
            ; Store parsed seconds in temporary variable
            staa   temps
            
            ; All validation passed - now we can update the actual time variables
            ldaa   temph
            staa   timeh
            ldaa   tempm
            staa   timem
            ldaa   temps
            staa   times
            
            ; Update the timeStr for display immediately
            jsr    updateTimeStr
            
            ; Time is valid, clear error message
            ; Make sure error message is explicitly cleared (put 0 in first byte)
            ldx    #errorMsg
            clr    0,x         ; Clear the first byte to null-terminate the error message
            
            lbra   cmdDone

checkQuitCommand
            ; Check if the character after 'q' is null or spaces (meaning 'q' is alone)
            ldx    #cmdBuffer
            inx                ; Point to character after 'q'
            
            ; Skip any spaces
skipQSpaces ldaa   0,x
            cmpa   #' '        ; Check if it's a space
            lbne   checkQEnd   ; If not space, check if it's end of string
            inx                ; Move past the space
            lbra   skipQSpaces ; Continue checking
            
checkQEnd   cmpa   #0          ; Check if it's null terminator
            lbne   invalidCmd  ; If not null, it's an invalid command
            
            ; Valid 'q' command - enter typewriter mode
            ldaa   #1
            staa   typewriterMode  ; Set typewriter mode flag
            
            ; Display one last time update before entering typewriter mode
            jsr    displayTime
            
            ; Start new line after time display
            jsr    nextline
            
            ; Display typewriter mode message
            ldaa   #' '      ; Add leading space for indentation
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ldx    #typewriterMsg1
            jsr    printmsg
            jsr    nextline
            
            ldaa   #' '      ; Add leading space for indentation
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ldx    #typewriterMsg2
            jsr    printmsg
            jsr    nextline
            
            lbra   cmdDone
            
invalidTime
            ; Set error message for invalid time
            ldx    #errInvalid
            jsr    copyMsg
            lbra   cmdDone
            
invalidCmd
            ; Set error message for invalid command
            ldx    #errInvalid
            jsr    copyMsg
            
cmdDone     
            ; Thoroughly clear the command buffer - all bytes to 0
            pshx
            ldx    #cmdBuffer
cmdClearLoop
            clr    0,x
            inx
            cpx    #cmdBuffer+20   ; Check if we've cleared all 20 bytes
            blo    cmdClearLoop
            pulx
            
            ; Force a display update now that command is processed
            ldaa   #1
            staa   dispFlag
            
            pulx
            pulb
            pula
            rts

;****************hourDisplayCommand******************
; Display current hours on the 7-segment displays
hourDisplayCommand
            ldaa   timeh        ; Get current hour
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgHourDisp
            jsr    copyMsg      ; Copy to errorMsg buffer
            
            lbra   cmdDone

;****************minuteDisplayCommand****************
; Display current minutes on the 7-segment displays
minuteDisplayCommand
            ldaa   timem        ; Get current minute
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgMinDisp
            jsr    copyMsg      ; Copy to errorMsg buffer
            
            lbra   cmdDone

;****************secondDisplayCommand****************
; Display current seconds on the 7-segment displays
secondDisplayCommand
            ldaa   times        ; Get current second
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgSecDisp
            jsr    copyMsg      ; Copy to errorMsg buffer
            
            lbra   cmdDone

;****************displayOnSevenSegment**************
; Displays a value on the 7-segment displays
; Input: A = value to display (0-99)
; Output: PORTB updated to drive 7-segment displays
displayOnSevenSegment
            psha                    ; Save original value
            pshb                    ; Save B register
            pshx                    ; Save X register
            
            ; First, ensure value is in valid range (0-99)
            cmpa    #100
            blo     ds_range_ok
            ldaa    #0              ; Default to 0 if out of range
ds_range_ok
            
            ; Convert to BCD (tens in high nibble, ones in low)
            tab                     ; Keep original in B
            ldaa    #0              ; Start tens digit at 0
            
ds_tens     cmpb    #10
            blo     ds_tens_done    ; If less than 10, done
            subb    #10             ; Subtract 10
            inca                    ; Increment tens digit
            bra     ds_tens         ; Continue dividing
            
ds_tens_done
            ; Now A = tens digit, B = ones digit
            
            ; For testing: Display raw BCD value
            lsla                    ; Shift tens digit to high nibble
            lsla
            lsla
            lsla
            aba                     ; Add ones digit in low nibble
            
            ; Write to PORTB (this will be the raw BCD value)
            staa    PORTB
            
            pulx                    ; Restore registers
            pulb
            pula
            rts
;****************updateTimeStr**********************
; Updates the timeStr buffer based on current time values
; Input: timeh, timem, times variables
; Output: timeStr updated with formatted time
updateTimeStr
            psha
            pshb
            pshx
            
            ; Format time string
            ldx    #timeStr
            
            ; Format hours
            ldaa   timeh        ; Load hours
            jsr    formatByte   ; Format as 2 digits (X is advanced)
            
            ; Add first colon
            ldaa   #':'
            staa   0,x         ; Store at X position
            inx                ; Move to next position
            
            ; Format minutes
            ldaa   timem        ; Load minutes
            jsr    formatByte   ; Format as 2 digits (X is advanced)
            
            ; Add second colon
            ldaa   #':'
            staa   0,x         ; Store at X position
            inx                ; Move to next position
            
            ; Format seconds
            ldaa   times        ; Load seconds
            jsr    formatByte   ; Format as 2 digits (X is advanced)
            
            ; Add null terminator
            ldaa   #0
            staa   0,x         ; Store null terminator
            
            pulx
            pulb
            pula
            rts

;****************parseTwoDigits*****************
; Parse two ASCII digits to a single byte value
; Input: X points to two ASCII digits
; Output: A = binary value (0-99), X advanced past the two digits
; Preserves: B
parseTwoDigits
            pshb
            
            ; First digit (tens place)
            ldaa   0,x
            suba   #'0'        ; Convert from ASCII to binary
            
            ; Calculate tens * 10
            ldab   #10
            mul                ; D = A * B (tens * 10)
            
            ; Save result
            pshb               ; Save result (in B after mul) 
            
            ; Second digit (ones place)
            ldaa   1,x
            suba   #'0'        ; Convert from ASCII to binary
            
            ; Add ones to (tens * 10)
            pulb               ; Restore tens * 10
            aba                ; A = tens*10 + ones
            
            ; Advance pointer past the two digits
            inx
            inx
            
            pulb
            rts

;****************copyMsg************************
; Copy message from X to errorMsg buffer
; Input: X points to source string
; Output: errorMsg contains the string
copyMsg     psha
            pshy
            
            ldy    #errorMsg   ; Destination
            
copyLoop    ldaa   0,x         ; Get character from source
            staa   0,y         ; Store in destination
            beq    copyDone    ; If null, done
            inx                ; Next source position
            iny                ; Next destination position
            bra    copyLoop
            
copyDone    puly
            pula
            rts

;****************checkHourCommand*******************
; Check if the hour command is valid (just 'h' alone)
checkHourCommand
            ; Check if any characters after 'h'
            ldx    #cmdBuffer
            inx                ; Point to character after 'h'
            ldaa   0,x         ; Get character after 'h'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidCmd  ; If not, invalid command
            
            ; Valid 'h' command - set display mode to hours
            ldaa   #DISP_HOURS
            staa   displayMode
            
            ; Display hours on 7-segment
            ldaa   timeh       ; Get current hour
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgHourDisp
            jsr    copyMsg     ; Copy to errorMsg buffer
            
            lbra   cmdDone

;****************checkMinuteCommand*****************
; Check if the minute command is valid (just 'm' alone)
checkMinuteCommand
            ; Check if any characters after 'm'
            ldx    #cmdBuffer
            inx                ; Point to character after 'm'
            ldaa   0,x         ; Get character after 'm'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidCmd  ; If not, invalid command
            
            ; Valid 'm' command - set display mode to minutes
            ldaa   #DISP_MINS
            staa   displayMode
            
            ; Display minutes on 7-segment
            ldaa   timem       ; Get current minute
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgMinDisp
            jsr    copyMsg     ; Copy to errorMsg buffer
            
            lbra   cmdDone

;****************checkSecondCommand*****************
; Check if the second command is valid (just 's' alone)
checkSecondCommand
            ; Check if any characters after 's'
            ldx    #cmdBuffer
            inx                ; Point to character after 's'
            ldaa   0,x         ; Get character after 's'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidCmd  ; If not, invalid command
            
            ; Valid 's' command - set display mode to seconds
            ldaa   #DISP_SECS
            staa   displayMode
            
            ; Display seconds on 7-segment
            ldaa   times       ; Get current second
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; Set success message
            ldx    #msgSecDisp
            jsr    copyMsg     ; Copy to errorMsg buffer
            
            lbra   cmdDone

            END               ; this is end of assembly source file
                              ; lines below are ignored - not assembled/compiled
