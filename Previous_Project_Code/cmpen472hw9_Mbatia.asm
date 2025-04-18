;*******************************************************
;* Title:         Combined Calculator and Clock Program
;* 
;* Objective:     CMPEN 472, Homework 9
;*                Making a calculator that doesn't crash with a clock
;*
;* Revision:      V1.5
;*
;* Date:          April 2, 2025
;*
;* Programmer:    Kuria Mbatia
;*
;* Company:       The Pennsylvania State University
;*                School of Electrical Engineering and Computer Science
;*
;* Algorithm:     RTI-based multi-tasking - pretty cool actually
;*                - 1.8ms RTI for timing (used to be 2.5ms but that was too slow)
;*                - 24-hour clock because who uses AM/PM anymore
;*                - Basic calculator ops: +,-,*,/ (no trig stuff, sorry)
;*                - Shows time & calcs on the same screen
;*
;* Register use:  A: Display stuff & calculations
;*                B: Timing & counters
;*                X,Y: Loop stuff, string ops, memory access
;*
;* Memory use:    RAM Locations from $3000 for small data variables
;*                RAM Locations from $3100 for program
;*                RAM Locations from $4000 for larger data structures and strings
;*
;* Output:        - HH:MM:SS on terminal (updates every sec if you don't type)
;*                - LED1 blinks every second so you know it's working
;*
;* Comments:      Multi-tasking without actual threads - pretty neat!
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

; Calculator specific constants
MAX_DIGITS   EQU        4           ; Maximum digits per operand
MAX_VALUE    EQU        9999        ; Maximum value allowed (4 digits)

ERR_FORMAT  EQU         1           ; Error code: Format error
ERR_DIV_ZERO EQU        2           ; Error code: Division by zero
ERR_OVERFLOW EQU        3           ; Error code: Overflow error

ERR_REASON_DIGIT EQU    1           ; Error reason: Too many digits

;*******************************************************
; variable/data section
            ORG    $3000             ; RAMStart defined as $3000
                                     ; in MC9S12C128 chip

; 7-segment display digit encoding table (0-9)
; Segment pattern for common cathode display: 0bABCDEFG
segTable    DC.B   $3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F

; Display mode constants
DISP_HOURS  EQU    1         ; Display hours on 7-segment
DISP_MINS   EQU    2         ; Display minutes on 7-segment
DISP_SECS   EQU    3         ; Display seconds on 7-segment
displayMode DS.B   1         ; Current display mode for 7-segment

; Clock variables
timeh       DS.B   1                 ; Hour (0-23)
timem       DS.B   1                 ; Minute (0-59)
times       DS.B   1                 ; Second (0-59)
temph       DS.B   1                 ; Temporary hour for validation
tempm       DS.B   1                 ; Temporary minute for validation
temps       DS.B   1                 ; Temporary second for validation
rtiCounter  DS.W   1                 ; Real-time interrupt counter
dispFlag    DS.B   1                 ; Display update flag
typingFlag  DS.B   1                 ; Flag indicating user is typing (1=typing)
typewriterMode DS.B   1              ; Flag indicating typewriter mode (1=active)

; Command processing variables
cmdIndex    DS.B   1                 ; Current position in command buffer
cmdReady    DS.B   1                 ; Flag indicating command is ready to process

; Calculator variables
calcActive  DS.B   1                 ; Flag indicating calculator mode is active
num1        DS.W   1                 ; First operand (16-bit)
num2        DS.W   1                 ; Second operand (16-bit)
result      DS.W   1                 ; Calculation result (16-bit)
operator    DS.B   1                 ; Operator character (+, -, *, /)
errorFlag   DS.B   1                 ; Error flag (0=no error, other=error code)
errorReason DS.B   1                 ; Additional error reason code
opPosition  DS.B   1                 ; Position of operator in command
digitCount1 DS.B   1                 ; Count of digits in first number
digitCount2 DS.B   1                 ; Count of digits in second number
tempByte    DS.B   1                 ; Temporary storage
tempCounter DS.B   1                 ; Temporary counter
tempResult  DS.W   1                 ; Temporary result for calculations
tempWord    DS.W   1                 ; Another temporary word storage

; Larger data structures section - moved to avoid overlap with code section
            ORG    $4000             ; Starting at $4000 for larger data structures
timeStr     DS.B   9                 ; Buffer for time string (HH:MM:SS\0)
cmdBuffer   DS.B   20                ; Buffer for command input
errorMsg    DS.B   20                ; Buffer for error messages (reduced from 30)
numBuf      DS.B   10                ; Buffer for number conversion
calcResultStr DS.B   20              ; String to hold calculator result

; Display messages and strings
msg1        DC.B   'Calculator and Clock Program', $00
msg2        DC.B   'Type t HH:MM:SS to set time, or enter a calculation (e.g. 123+456)', $00
errInvalid  DC.B   'Invalid input', $00
errOverflow DC.B   'Overflow', $00
errDivZero  DC.B   'Division by zero error', $00
errDigitMsg DC.B   'Too many digits', $00
typewriterMsg1 DC.B   'Clock and Calculator stopped and Typewrite program started.', $00
typewriterMsg2 DC.B   'You may type below.', $00
msgHourDisp DC.B   'Hours on display', $00
msgMinDisp  DC.B   'Mins on display', $00
msgSecDisp  DC.B   'Secs on display', $00
crlfStr     DC.B   CR,LF,$00         ; Carriage return and line feed

;*******************************************************
; interrupt vector section
            ORG    $FFF0             ; RTI interrupt vector setup for the simulator
;            ORG    $3FF0             ; RTI interrupt vector setup for the CSM-12C128 board
            DC.W   rtiisr

;*******************************************************
; code section

            ORG    $3100       ; Program starts at $3100 to avoid overlap with data
Entry
            LDS    #$4000         ; initialize the stack pointer

            ; Initialize hardware
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
            clr    timeh        ; Start with 00:00:00
            clr    timem        ; because who knows what time it is
            clr    times        ; in the microcontroller world
            clr    dispFlag     ; Don't update display yet
            
            ; Set up command processing stuff
            clr    cmdIndex     ; Start with empty command
            clr    cmdReady     ; No commands ready
            clr    errorMsg     ; No errors to show
            clr    typingFlag   ; Nobody typing yet
            clr    typewriterMode ; Not in typewriter mode
            clr    calcActive   ; No calc results to show
            
            ; Default to showing hours on the 7-seg display
            LDAA   #DISP_HOURS
            STAA   displayMode
            
            ; Say hello to the user!
            ldx    #msg1
            jsr    printmsg
            jsr    nextline
            ldx    #msg2
            jsr    printmsg
            jsr    nextline
            
            ; Set up the real-time interrupt - this is where the magic happens
            bset   RTICTL,%00010111 ; Faster interrupts (~1.8ms) = better accuracy!
            bset   CRGINT,%10000000 ; Turn on RTI interrupt
            bset   CRGFLG,%10000000 ; Clear the flag (always do this first)

            ldx    #0
            stx    rtiCounter      ; initialize interrupt counter with 0
            
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
            
            ; Display initial time line
            jsr    displayTime
            
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
            
            ; For the first character, we need to position the cursor at CMD> position
            jsr    nextline     ; Start with a fresh line
            
            ; Make sure the time string is updated with the latest time
            jsr    updateTimeStr
            
            ; Increment the displayed second to show "next second"
            ; This creates the effect of completing the next time update
            ; Save original time values
            ldaa   timeh
            psha   ; Save hours
            ldaa   timem
            psha   ; Save minutes
            ldaa   times
            psha   ; Save seconds
            
            ; Increment the second
            inc    times
            ldaa   times
            cmpa   #60
            blo    ml_no_min_increment
            
            ; Reset seconds, increment minutes
            clr    times
            inc    timem
            ldaa   timem
            cmpa   #60
            blo    ml_no_hour_increment
            
            ; Reset minutes, increment hours
            clr    timem
            inc    timeh
            ldaa   timeh
            cmpa   #24
            blo    ml_no_hour_reset
            
            ; Reset hours
            clr    timeh
            
ml_no_hour_reset:
ml_no_hour_increment:
ml_no_min_increment:
            ; Update time string with incremented values
            jsr    updateTimeStr
            
            ; Output Tcalc> and time
            ldaa   #'T'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'a'
            jsr    putchar
            ldaa   #'l'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display formatted time
            ldx    #timeStr
            jsr    printmsg
            
            ; Add padding spaces (22 total)
            ldab   #22
ml_spaceLoop ldaa  #' '
            jsr    putchar
            decb
            bne    ml_spaceLoop
            
            ; Output CMD>
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
            
            ; Now the cursor is positioned right after CMD> ready for input
            
            ; Output 16 spaces for proper Error section alignment
            ldab   #16
ml_errSpaceLoop ldaa  #' '
            jsr    putchar
            decb
            bne    ml_errSpaceLoop
            
            ; Output Error>
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
            
            ; Restore original time values
            pula
            staa   times  ; Restore seconds
            pula
            staa   timem  ; Restore minutes
            pula
            staa   timeh  ; Restore hours
            
            ; Move cursor back to just after CMD>
            ; This needs to be done by redrawing the line again up to CMD>
            jsr    nextline     ; Start with a fresh line
            
            ; Don't update time string here - we want to keep the incremented time
            ; Just use the previously updated timeStr that has the incremented time
            
            ; Output Tcalc> and time again
            ldaa   #'T'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'a'
            jsr    putchar
            ldaa   #'l'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display formatted time
            ldx    #timeStr
            jsr    printmsg
            
            ; Add padding spaces (22 total)
            ldab   #22
ml_spaceLoop2 ldaa  #' '
            jsr    putchar
            decb
            bne    ml_spaceLoop2
            
            ; Output CMD> again
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
            
            ; Now we're ready for input at the right position
            
notFirstChar
            ; Get the character back
            pula                ; Restore the character from stack
            
            ; If this is ENTER (CR), don't echo it, just process it
            cmpa   #CR
            lbeq   skipEcho
            
            ; Echo the character at current position (don't refresh entire display)
            jsr    putchar      ; Echo character where cursor currently is
            
skipEcho
            ; Process the character
            jsr    processChar
            
            ; Do NOT force a display update after each character
            ; This allows typing to stay on the same line
            
            ; No need to redraw the line - just continue
            lbra    mainLoop
            
checkCmdReady
            ; Check if command is ready to process
            ldaa   cmdReady
            lbeq   checkTime
            
            ; Process the command first (to set error message if needed)
            jsr    processCmd
            clr    cmdReady     ; Clear command ready flag
            
            ; Display error message if it exists
            ldx    #errorMsg
            ldaa   0,x         ; Check first byte of errorMsg
            beq    skipErrorMsg  ; If zero, no error to display
            
            ; Display error message to error section
            jsr    displayError
            
skipErrorMsg
            ; Update immediately - no extra line breaks
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
            
            ; Update the timeStr first to ensure latest time is used
            jsr    updateTimeStr
            
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
; This is where all the timing magic happens - runs every ~1.8ms!
rtiisr      bset   CRGFLG,%10000000 ; Reset the interrupt flag (or it'll keep firing)
            ldx    rtiCounter
            inx                      ; Just counting interrupts
            stx    rtiCounter
            
            ; Check if 1 second has passed (558 * 1.792ms ≈ 1000ms)
            ; Had to adjust this value a bunch to get accurate time
            cpx    #558
            blo    rtidone          ; Not a second yet, bail out
            
            ; Reset counter - new second!
            ldx    #0
            stx    rtiCounter
            
            ; Toggle LED1 - blink blink! (visual heartbeat)
            brset  PORTB,#%00010000,rtiisr_turnOffLED1 ; LED on? Turn it off
            
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
            
            ; Display "Tcalc> " prefix
            ldaa   #'T'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'a'
            jsr    putchar
            ldaa   #'l'
            jsr    putchar
            ldaa   #'c'
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Display formatted time
            ldx    #timeStr
            jsr    printmsg
            
            ; Check if calculator result is active
            ldaa   calcActive
            beq    dtNoCalcResult
            
            ; Add spacing after time
            ldaa   #' '
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            ; Display calculator result
            ldx    #calcResultStr
            jsr    printmsg
            
            ; Clear calculator active flag after displaying
            clr    calcActive
            
            ; Add fixed padding of 5 spaces after result
            ldaa   #' '
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            jsr    putchar
            
            bra    dtShowCmd
            
dtNoCalcResult
            ; No calculator result, just add padding spaces
            ; Need 22 spaces total to maintain alignment with the CMD section
            ldab   #22
dtSpaceLoop ldaa   #' '
            jsr    putchar
            decb
            bne    dtSpaceLoop
            
dtShowCmd   ; Display "CMD> " section
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
            
            ; Display command currently being typed if we're typing
            ldaa   typingFlag
            beq    noTypingCmd   ; Changed label name to avoid conflict
            
            ; If typing, display command buffer content
            ldx    #cmdBuffer
            jsr    printmsg
            
noTypingCmd ; Continue with standard display behavior
            jmp    continueDisplay

;****************displayError**********************
; Display error message in Error section
; Input: errorMsg contains error message
displayError
            psha
            pshx
            
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
            
            ; Display error message
            ldx    #errorMsg
            jsr    printmsg
            
            pulx
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
            
            ; Add null terminator after character
            inx
            clr    0,x
            
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
            
            ; Clear error message and error flags as default
            ldaa   #0
            staa   errorMsg
            
            ; Reset all calculator variables
            jsr    clearCalcVars
            
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
            
            ; If not a specific command, try to handle as calculator input
            jsr    parseCalcCommand
            ldaa   errorFlag
            bne    showCalcError
            
            ; If parsed successfully, perform calculation
            jsr    calculate
            ldaa   errorFlag
            bne    showCalcError
            
            ; If calculation successful, format the result and set flag
            jsr    formatCalcResult
            
            ; Set flag to display the result on the next time display line
            ldaa   #1
            staa   calcActive
            
            ; Ensure error flag is cleared for successful calculations
            clr    errorFlag
            
            lbra   cmdDone
            
showCalcError
            ; Copy appropriate error message based on errorFlag
            ldaa   errorFlag
            cmpa   #ERR_FORMAT
            bne    checkDivZero
            
            ; Format error
            ldx    #errInvalid
            jsr    copyMsg
            
            ; Ensure calculator result won't be displayed
            clr    calcActive
            
            ; Clear the calculation result string
            ldx    #calcResultStr
            clr    0,x
            
            ; Check if error is due to 5th digit
            ldaa   errorReason
            cmpa   #ERR_REASON_DIGIT
            bne    calcErrorDone
            
            ; Append digit message
            ldx    #errorMsg
            jsr    findMsgEnd   ; Find end of current message
            
            ; Add " ;due to 5th digit"
            ldaa   #' '
            staa   0,x
            inx
            ldaa   #';'
            staa   0,x
            inx
            ldaa   #'d'
            staa   0,x
            inx
            ldaa   #'u'
            staa   0,x
            inx
            ldaa   #'e'
            staa   0,x
            inx
            ldaa   #' '
            staa   0,x
            inx
            ldaa   #'t'
            staa   0,x
            inx
            ldaa   #'o'
            staa   0,x
            inx
            ldaa   #' '
            staa   0,x
            inx
            ldaa   #'5'
            staa   0,x
            inx
            ldaa   #'t'
            staa   0,x
            inx
            ldaa   #'h'
            staa   0,x
            inx
            ldaa   #' '
            staa   0,x
            inx
            ldaa   #'d'
            staa   0,x
            inx
            ldaa   #'i'
            staa   0,x
            inx
            ldaa   #'g'
            staa   0,x
            inx
            ldaa   #'i'
            staa   0,x
            inx
            ldaa   #'t'
            staa   0,x
            inx
            ldaa   #0
            staa   0,x
            
            bra    calcErrorDone
            
checkDivZero
            cmpa   #ERR_DIV_ZERO
            bne    checkOverflow
            
            ; Division by zero error
            ldx    #errDivZero
            jsr    copyMsg
            bra    calcErrorDone
            
checkOverflow
            ; Must be overflow error
            ldx    #errOverflow
            jsr    copyMsg
            
calcErrorDone
            lbra   cmdDone
            
timeCommand
            ; Start parsing after 't'
            ldx    #cmdBuffer
            inx                 ; Point to character after 't'
            
            ; Skip spaces - find first non-space character
timeSkipSpace
            ldaa   0,x
            cmpa   #' '
            bne    timeParseStart
            inx                 ; Move past space
            bra    timeSkipSpace
            
timeParseStart
            ; Check if we've reached the end of string (invalid)
            ldaa   0,x
            lbeq   invalidTime  ; Empty time string is invalid
            
            ; Clear temporary time variables
            clr    temph
            clr    tempm
            clr    temps
            
            ; Parse hours (one or two digits)
            jsr    parseDec     ; Parse decimal number
            cmpa   #24          ; Check if hours < 24
            lbhs   invalidTime  ; Invalid if hours >= 24
            staa   temph        ; Store valid hours
            
            ; Check for colon after hours
            ldaa   0,x
            cmpa   #':'
            lbne   invalidTime  ; Must have colon after hours
            inx                 ; Skip colon
            
            ; Parse minutes (one or two digits)
            jsr    parseDec     ; Parse decimal number
            cmpa   #60          ; Check if minutes < 60
            lbhs   invalidTime  ; Invalid if minutes >= 60
            staa   tempm        ; Store valid minutes
            
            ; Check for colon after minutes
            ldaa   0,x
            cmpa   #':'
            lbne   invalidTime  ; Must have colon after minutes
            inx                 ; Skip colon
            
            ; Parse seconds (one or two digits)
            jsr    parseDec     ; Parse decimal number
            cmpa   #60          ; Check if seconds < 60
            lbhs   invalidTime  ; Invalid if seconds >= 60
            staa   temps        ; Store valid seconds
            
            ; Ensure nothing follows except spaces
timeCheckEnd
            ldaa   0,x
            lbeq   timeValid    ; End of string is valid
            cmpa   #' '
            lbne   invalidTime  ; Non-space after seconds is invalid
            inx                 ; Move past space
            lbra   timeCheckEnd
            
timeValid
            ; Update actual time variables
            ldaa   temph
            staa   timeh
            ldaa   tempm
            staa   timem
            ldaa   temps
            staa   times
            
            ; Update the timeStr for display immediately
            jsr    updateTimeStr
            
            ; Clear error message - time is valid
            ldx    #errorMsg
            clr    0,x         ; Null-terminate error message
            
            lbra   cmdDone

;****************parseDec*************************
; Parse a decimal number (1 or 2 digits)
; Input:  X points to string
; Output: A contains binary value
;         X advanced past the digits
; Preserves: B
parseDec    pshb
            
            ; Check if first character is a digit
            ldaa   0,x
            cmpa   #'0'
            lblo   pdError     ; Not a digit
            cmpa   #'9'
            lbhi   pdError     ; Not a digit
            
            ; Convert first digit
            suba   #'0'        ; Convert to binary
            tab                ; Store in B
            
            ; Move to next character
            inx                
            
            ; Check if next character is also a digit
            ldaa   0,x
            cmpa   #'0'
            lblo   pdOneDone   ; Not a digit, we're done with one digit
            cmpa   #'9'
            lbhi   pdOneDone   ; Not a digit, we're done with one digit
            
            ; We have a second digit - first convert first digit (in B) to tens
            ldaa   #10
            mul                ; D = B * 10 (tens)
            
            ; Now add second digit
            ldaa   0,x
            suba   #'0'        ; Convert to binary
            aba                ; Add to tens
            
            ; Advance past second digit
            inx
            lbra   pdDone
            
pdOneDone   ; We only had one digit, value already in B
            tba                ; Transfer to A
            lbra   pdDone
            
pdError     ; Error in parsing - return invalid value
            ldaa   #$FF
            
pdDone      pulb
            rts

invalidTime
            ; Set error message for invalid time
            ldx    #errInvalid  ; This now contains "Invalid input" text
            jsr    copyMsg
            
            ; Clear calculator active flag to prevent showing previous results
            clr    calcActive
            
            lbra   cmdDone

;****************parseTimeComponent******************
; Parse a time component (hours, minutes, or seconds)
; Supports both single digit (1) and double digit (01) formats
; Input:  X - pointer to start of component
; Output: A - binary value of component
;         X - advanced past the component
; Preserves: B
parseTimeComponent
            psha
            pshb
            
            ; Read first digit
            ldaa   0,x
            cmpa   #'0'
            lblo   ptcError    ; Must be a digit
            cmpa   #'9'
            lbhi   ptcError    ; Must be a digit
            
            ; Convert first digit to binary
            suba   #'0'
            tab                ; Save first digit in B
            
            ; Check if there's a second digit
            ldaa   1,x
            
            ; Check if we're at end of string or non-digit character
            cmpa   #0          ; Null terminator?
            lbeq   ptcSingleDigit
            cmpa   #' '        ; Space?
            lbeq   ptcSingleDigit
            cmpa   #':'        ; Colon? (for hours/minutes)
            lbeq   ptcSingleDigit
            
            ; It should be a digit for double-digit format
            cmpa   #'0'
            lblo   ptcSingleDigit ; Not a digit, treat as single-digit format
            cmpa   #'9'
            lbhi   ptcSingleDigit ; Not a digit, treat as single-digit format
            
            ; It's a two-digit format
            ; First digit is already in B, multiply by 10
            ldaa   #10
            mul                ; D = B * A = first digit * 10
            
            ; Read second digit
            ldaa   1,x
            suba   #'0'        ; Convert to binary
            aba                ; Add to result (tens + ones)
            
            ; Advance pointer past both digits
            inx
            inx
            lbra   ptcDone
            
ptcSingleDigit:
            ; Single digit format, value is already in B
            tba                ; Transfer B to A
            
            ; Advance pointer past the digit
            inx
            lbra   ptcDone
            
ptcError:
            ; Error, return invalid value (0xFF)
            ldaa   #$FF
            
ptcDone:
            ; Result is in A
            tab                ; Save result in B
            pulb               ; Restore original B
            psha               ; Save A temporarily
            tba                ; Transfer saved result to A
            pulb               ; Clean up stack (discard temp A)
            rts

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
            
invalidCmd
            ; Set error message for invalid command
            ldx    #errInvalid  ; This now contains "Invalid input" text
            jsr    copyMsg
            
            ; Clear calculator active flag to prevent showing previous results
            clr    calcActive
            
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
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
            lbra   cmdDone

;****************minuteDisplayCommand****************
; Display current minutes on the 7-segment displays
minuteDisplayCommand
            ldaa   timem        ; Get current minute
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
            lbra   cmdDone

;****************secondDisplayCommand****************
; Display current seconds on the 7-segment displays
secondDisplayCommand
            ldaa   times        ; Get current second
            jsr    displayOnSevenSegment  ; Display on 7-segment display
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
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

;****************findMsgEnd**********************
; Find the end (null terminator) of a string
; Input: X - pointer to string
; Output: X - pointer to the null terminator
findMsgEnd  psha
            
findEnd     ldaa   0,x         ; Get character
            beq    findDone    ; If null, we found the end
            inx                ; Next character
            bra    findEnd
            
findDone    pula
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
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
            ; Also clear command buffer to ensure it's not displayed in error section
            ldx    #cmdBuffer
            clr    0,x         ; Clear first byte to null-terminate
            
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
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
            ; Also clear command buffer to ensure it's not displayed in error section
            ldx    #cmdBuffer
            clr    0,x         ; Clear first byte to null-terminate
            
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
            
            ; We don't need to set a message - this is a valid command
            ; that doesn't need any feedback message
            
            ; Clear error message to ensure nothing is displayed
            ldx    #errorMsg
            clr    0,x         ; Clear first byte to null-terminate
            
            ; Also clear command buffer to ensure it's not displayed in error section
            ldx    #cmdBuffer
            clr    0,x         ; Clear first byte to null-terminate
            
            lbra   cmdDone

;***************CALCULATOR FUNCTIONALITY***************
; Basic calculator that handles +,-,*,/ (not even % - maybe next time)
; Nothing fancy - max number is 9999, good enough for this class

;****************parseCalcCommand******************
; Looks for a valid calculator expression in the command buffer
; If someone types "123+456", figures out it's nums and operator
; Returns:     num1, num2, operator - or sets error if input is garbage
parseCalcCommand
            ; Reset operator position and error flags
            clr    opPosition
            clr    errorFlag
            clr    errorReason
            
            ; Count actual command length since cmdIndex may not be accurate
            ldx    #cmdBuffer
            ldab   #0          ; Initialize counter to 0
pcCountLoop ldaa   0,x         ; Get character from buffer
            beq    pcDoneCount  ; If null byte, we've reached the end
            incb               ; Increment counter
            inx                ; Move to next character
            bra    pcCountLoop  ; Continue counting
            
pcDoneCount ; B now has the command length
            stab   tempByte    ; Store length for later use
            
            ; Debug check - if command length is less than 3, it's invalid
            cmpb   #3
            bhs    pcCheckLen  ; If length >= 3, continue checking
            
            ; Invalid - command too short
            ldaa   #ERR_FORMAT
            staa   errorFlag
            rts                ; Return with error
            
pcCheckLen  ; Check if command is too long
            cmpb   #10        ; 10 characters should be enough (4+1+4 + margin)
            bls    pcFindOp    ; If length <= 10, try to find operator
            
            ; Invalid - command too long
            ldaa   #ERR_FORMAT
            staa   errorFlag
            ldaa   #ERR_REASON_DIGIT
            staa   errorReason
            rts                ; Return with error
            
pcFindOp    ; Start searching for an operator in the command
            ldx    #cmdBuffer  ; Reset pointer to start of buffer
            clr    opPosition  ; Reset operator position counter
            
pcOpLoop    ldaa   0,x         ; Get character
            beq    pcOpNotFound ; If null, no operator found
            
            ; Check if it's an operator (+, -, *, /)
            cmpa   #'+'
            beq    pcOpFound   ; Found + operator
            cmpa   #'-'
            beq    pcOpFound   ; Found - operator
            cmpa   #'*'
            beq    pcOpFound   ; Found * operator
            cmpa   #'/'
            beq    pcOpFound   ; Found / operator
            
            ; Not an operator, check if it's a valid digit
            cmpa   #'0'
            blo    pcInvalidChar ; If less than '0', invalid
            cmpa   #'9'
            bhi    pcInvalidChar ; If greater than '9', invalid
            
            ; Valid digit, continue searching
            inx                ; Move to next character
            inc    opPosition  ; Increment operator position counter
            bra    pcOpLoop    ; Continue searching
            
pcInvalidChar
            ; Found an invalid character
            ldaa   #ERR_FORMAT
            staa   errorFlag
            rts                ; Return with error
            
pcOpFound   ; Found a valid operator
            staa   operator    ; Store the operator character
            
            ; Operator can't be at the start of command
            ldaa   opPosition
            beq    pcInvalidChar ; If operator at position 0, invalid
            
            ; Operator can't be at the end of command
            ldab   opPosition
            incb               ; Get position after operator
            cmpb   tempByte    ; Compare with command length
            beq    pcInvalidChar ; If no characters after operator, invalid
            
            ; Check if first number has too many digits
            ldaa   opPosition  ; Get position of operator (equals digit count of first number)
            staa   digitCount1 ; Store for reference
            cmpa   #MAX_DIGITS+1
            blo    pcCheckSecond ; If digit count <= MAX_DIGITS, check second number
            
            ; First number has too many digits
            ldaa   #ERR_FORMAT
            staa   errorFlag
            ldaa   #ERR_REASON_DIGIT
            staa   errorReason
            rts                ; Return with error
            
pcCheckSecond
            ; Calculate length of second number
            ldaa   tempByte    ; Get command length
            suba   opPosition  ; Subtract operator position
            deca               ; Subtract 1 for the operator itself
            staa   digitCount2 ; Store for reference
            
            ; Check if second number has too many digits
            cmpa   #MAX_DIGITS+1
            blo    pcParseNums ; If digit count <= MAX_DIGITS, parse numbers
            
            ; Second number has too many digits
            ldaa   #ERR_FORMAT
            staa   errorFlag
            ldaa   #ERR_REASON_DIGIT
            staa   errorReason
            rts                ; Return with error
            
pcParseNums
            ; Parse first number
            jsr    parseNum1
            
            ; Check if there was an error parsing first number
            ldaa   errorFlag
            bne    pcDone2
            
            ; Parse second number
            jsr    parseNum2
            
pcDone2     rts                ; Return (errorFlag is set if there was an error)
            
pcOpNotFound
            ; No operator found in command
            ldaa   #ERR_FORMAT
            staa   errorFlag
            rts                ; Return with error

;****************parseNum1***********************
; Parse the first number from cmdBuffer
; Input:      cmdBuffer, opPosition
; Output:     num1, errorFlag
; Registers:  All modified
parseNum1   
            ; Clear result
            clra
            clrb
            std    num1
            
pn1Continue ; Parse the digits before operator
            ldx    #cmdBuffer
            
pn1Loop     ldaa   0,x         ; Get character
            beq    pn1Done     ; End of string
            
            ; Check if reached operator
            cmpa   operator
            beq    pn1Done
            
            ; Check if it's a digit
            cmpa   #'0'
            blo    pn1Error    ; Not a digit
            cmpa   #'9'
            bhi    pn1Error    ; Not a digit
            
            ; Multiply current num1 by 10 (D=D*10)
            ldd    num1
            
            ; D = D * 10 = D*8 + D*2
            std    tempResult  ; Save original
            lsld                ; D * 2
            std    num1        ; Save D*2
            ldd    tempResult  ; Get original
            lsld                ; D * 2
            lsld                ; D * 4
            lsld                ; D * 8
            addd   num1        ; D*8 + D*2 = D*10
            std    num1        ; Save result
            
            ; Convert digit and add
            ldaa   0,x         ; Get digit again
            suba   #'0'        ; Convert to binary
            tab                 ; Transfer A to B (put digit in low byte)
            clra                ; Clear high byte
            addd   num1        ; Add to result
            std    num1        ; Save updated result
            
            ; Continue with next digit
            inx
            bra    pn1Loop
            
pn1Error    ldaa   #ERR_FORMAT
            staa   errorFlag
            rts
            
pn1Done     ; Check if number exceeds the maximum allowed value (9999)
            ldd    num1
            cpd    #MAX_VALUE
            bls    pn1Ok       ; If num1 <= MAX_VALUE, it's OK
            
            ; Number too large - must be a 5+ digit number
            ldaa   #ERR_FORMAT
            staa   errorFlag
            ldaa   #ERR_REASON_DIGIT
            staa   errorReason
            rts
            
pn1Ok       rts

;****************parseNum2***********************
; Parse the second number from cmdBuffer
; Input:      cmdBuffer, opPosition
; Output:     num2, errorFlag
; Registers:  All modified
parseNum2   
            ; Clear result
            clra
            clrb
            std    num2
            
pn2Continue ; Position X at first digit of second number
            ldx    #cmdBuffer
            ldab   opPosition
            incb              ; Skip operator
            abx                ; X now points to second number
            
pn2Loop     ldaa   0,x         ; Get character
            beq    pn2Done     ; End of string
            
            ; Check if it's a digit
            cmpa   #'0'
            blo    pn2Error    ; Not a digit
            cmpa   #'9'
            bhi    pn2Error    ; Not a digit
            
            ; Multiply current num2 by 10 (D=D*10)
            ldd    num2
            
            ; D = D * 10 = D*8 + D*2
            std    tempResult  ; Save original
            lsld                ; D * 2
            std    num2        ; Save D*2
            ldd    tempResult  ; Get original
            lsld                ; D * 2
            lsld                ; D * 4
            lsld                ; D * 8
            addd   num2        ; D*8 + D*2 = D*10
            std    num2        ; Save result
            
            ; Convert digit and add
            ldaa   0,x         ; Get digit again
            suba   #'0'        ; Convert to binary
            tab                 ; Transfer A to B (put digit in low byte)
            clra                ; Clear high byte
            addd   num2        ; Add to result
            std    num2        ; Save updated result
            
            ; Continue with next digit
            inx
            bra    pn2Loop
            
pn2Error    ldaa   #ERR_FORMAT
            staa   errorFlag
            rts
            
pn2Done     ; Check if number exceeds the maximum allowed value (9999)
            ldd    num2
            cpd    #MAX_VALUE
            bls    pn2Ok       ; If num2 <= MAX_VALUE, it's OK
            
            ; Number too large - must be a 5+ digit number
            ldaa   #ERR_FORMAT
            staa   errorFlag
            ldaa   #ERR_REASON_DIGIT
            staa   errorReason
            rts
            
pn2Ok       rts

;****************calculate***********************
; Does the actual math! +, -, *, and / (the basics)
; Input:      num1, num2, operator
; Output:     result with error code if we messed up
calculate   
            ; Figure out which math operation to do
            ldaa   operator
            
            ; Addition - the easy one!
            cmpa   #'+'
            beq    calcAdd
            
            ; Subtraction - almost as easy
            cmpa   #'-'
            beq    calcSub
            
            ; Multiplication - getting trickier
            cmpa   #'*'
            beq    calcMul
            
            ; Division - watch out for divide by zero!
            cmpa   #'/'
            beq    calcDiv
            
            ; This should never happen since we already validated
            ldaa   #ERR_FORMAT
            staa   errorFlag
            rts
            
calcAdd     ; Addition: result = num1 + num2
            ldd    num1        ; Load first operand into D
            addd   num2        ; Add second operand to D
            
            ; Check for positive overflow (result > 9999)
            cpd    #10000      ; Compare with 10000 (0x2710)
            bhs    calcOverflow ; If result >= 10000, it's an overflow
            
            ; Store the result
            std    result
            rts
            
calcSub     ; Subtraction: result = num1 - num2
            ldd    num1        ; Load first operand into D
            subd   num2        ; Subtract second operand from D
            
            ; Check for negative overflow (result < -9999)
            cpd    #$D8F1      ; -9999 = 0xD8F1 in two's complement
            blt    calcOverflow ; If result < -9999, it's an overflow
            
            ; Store the result
            std    result
            rts
            
calcMul     ; Multiplication implementation
            ; Multiply the operands
            ldd    num1        ; Load first operand into D
            ldy    num2        ; Load second operand into Y (not X)
            emul               ; Multiply D * Y, result in Y:D (32-bit)
            
            ; Check for overflow - high word must be 0
            cpy    #0
            bne    calcOverflow  ; High word not zero means overflow
            
            ; Check if result > 9999
            cpd    #10000      ; Compare with 10000 (0x2710)
            bhi    calcOverflow  ; If result > 9999, it's an overflow error
            
            ; Store result
            std    result
            rts
            
calcDiv     ; Division implementation
            ; Check for division by zero
            ldd    num2
            beq    calcDivZero   ; If divisor is zero, error
            
            ; Perform division
            ldd    num1        ; Load dividend into D
            ldx    num2        ; Load divisor into X
            idiv               ; Divide D / X: quotient in X, remainder in D
            
            ; Store the quotient (X) as the result
            stx    result
            rts
            
calcDivZero ; Handle division by zero error
            ldaa   #ERR_DIV_ZERO
            staa   errorFlag
            rts
            
calcOverflow ; Handle overflow error
            ldaa   #ERR_OVERFLOW
            staa   errorFlag
            rts

;****************formatCalcResult*******************
; Format calculator result for display
; Input:      cmdBuffer, result
; Output:     calcResultStr with formatted result
; Registers:  All modified
formatCalcResult
            ; Format the result as "EXPR=RESULT"
            
            ; Clear the calcResultStr first
            ldx    #calcResultStr
            clr    0,x
            
            ; Copy command buffer (expression) to calcResultStr
            ldx    #cmdBuffer
            ldy    #calcResultStr
            
copyExpr    ldaa   0,x         ; Get character
            beq    copyDone2   ; If null, done
            staa   0,y         ; Store in result string
            inx
            iny
            bra    copyExpr
            
copyDone2   ; Add equals sign
            ldaa   #'='
            staa   0,y
            iny
            
            ; Check if result is negative
            ldd    result
            bpl    formatPositive
            
            ; Handle negative result
            ldaa   #'-'
            staa   0,y
            iny
            
            ; Negate the result for formatting
            ldd    result
            coma
            comb
            addd   #1          ; D now contains positive value
            std    tempWord    ; Store for processing
            bra    formatDigits
            
formatPositive
            ; Just use the result as is
            ldd    result
            std    tempWord    ; Store for processing
            
formatDigits
            ; Special case for zero
            ldd    tempWord
            cpd    #0
            bne    format4Digits
            
            ; Just output "0" for zero
            ldaa   #'0'
            staa   0,y
            iny
            bra    formatDone
            
format4Digits
            ; Clear work area in numBuf
            pshx
            ldx    #numBuf
            clr    0,x
            clr    1,x
            clr    2,x
            clr    3,x
            clr    4,x
            pulx
            
            ; Always format as 4 potential digits, filling with leading zeros if needed
            
            ; Extract thousands digit (if any)
            ldd    tempWord
            ldx    #1000
            idiv               ; X = quotient (thousands), D = remainder
            xgdx               ; Move thousands digit to D
            addb   #'0'
            stab   numBuf      ; Store thousands digit
            
            ; Extract hundreds digit
            xgdx               ; Get remainder back to D
            ldx    #100
            idiv               ; X = quotient (hundreds), D = remainder
            xgdx               ; Move hundreds digit to D
            addb   #'0'
            stab   numBuf+1    ; Store hundreds digit
            
            ; Extract tens digit
            xgdx               ; Get remainder back to D
            ldx    #10
            idiv               ; X = quotient (tens), D = remainder
            xgdx               ; Move tens digit to D
            addb   #'0'
            stab   numBuf+2    ; Store tens digit
            
            ; Extract ones digit
            xgdx               ; Get remainder back to D
            addb   #'0'        ; Convert remainder to ASCII
            stab   numBuf+3    ; Store ones digit
            
            ; Null terminate
            clr    numBuf+4
            
            ; Skip leading zeros except for the last digit
            ldx    #numBuf
            
skipZeros   ldaa   0,x         ; Get current digit
            cmpa   #'0'        ; Is it a leading zero?
            bne    copyDigits  ; If not zero, start copying from here
            
            ; Check if this is the last digit position
            cpx    #numBuf+3
            beq    copyDigits  ; Don't skip the last digit even if it's zero
            
            inx                ; Move to next digit
            bra    skipZeros
            
copyDigits  ; X now points to first non-zero digit (or last digit)
            
copyDigit   ldaa   0,x         ; Get digit
            beq    formatDone  ; If null, we're done
            staa   0,y         ; Store in result
            inx                ; Next source position
            iny                ; Next destination position
            bra    copyDigit
            
formatDone  ; Null terminate the result string
            clr    0,y
            rts

;****************displayCalcResult******************
; The calculator result string should be displayed on a separate line
; after a successful calculation
displayCalcResult
            psha
            pshx
            
            ; Move to beginning of a new line
            ldaa  #CR              ; move the cursor to beginning of the line
            jsr   putchar          ; Carriage Return/Enter key
            ldaa  #LF              ; move the cursor to next line, Line Feed
            jsr   putchar
            
            ; Display the formatted calculator result
            ldx   #calcResultStr
            jsr   printmsg
            
            ; Move to beginning of a new line
            ldaa  #CR              ; move the cursor to beginning of the line
            jsr   putchar          ; Carriage Return/Enter key
            ldaa  #LF              ; move the cursor to next line, Line Feed
            jsr   putchar
            
            pulx
            pula
            rts

;****************clearCalcVars**********************
; Clear all calculator-related variables
clearCalcVars
            ; Clear all calculator-related variables
            clr    opPosition
            clr    digitCount1
            clr    digitCount2
            clr    num1
            clr    num1+1
            clr    num2
            clr    num2+1
            clr    result
            clr    result+1
            clr    operator
            clr    errorFlag
            clr    errorReason
            rts

continueDisplay
            ; When typing, we already display the cmdBuffer in the CMD section,
            ; so we don't need to show it here
            ldaa   typingFlag
            bne    skipCmdDisplayInError
            
            ; If not typing, display command buffer if it has content
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
            bra    padCmd
            
skipCmdDisplayInError
            ; When typing, we don't show command buffer here
            ldab   #0          ; Set length to 0
            
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

            END               ; this is end of assembly source file