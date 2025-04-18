;*******************************************************
;* Title:         Clock Program
;* 
;* Objective:     CMPEN 472, Homework 10
;*                24-hour clock with simple terminal interface
;*                and interrupt-driven wave generation.
;*
;* Summary:       This program implements a 24-hour digital clock
;*                using the Real-Time Interrupt (RTI) for timekeeping
;*                and displays the time (HH, MM, or SS selectable via
;*                commands) on 7-segment LEDs connected to PORTB.
;*                It also generates various waveforms (sawtooth, triangle,
;*                square) at different frequencies using Timer Output
;*                Compare channel 5 (OC5). Waveform data points (0-255)
;*                are sent to the SCI terminal every 125us. A simple
;*                command-line interface via the SCI port allows users
;*                to set the time, select the display mode, trigger wave
;*                generation, and quit to a basic typewriter mode.
;*
;* Revision:      V1.0
;*
;* Date:          April 8, 2025
;*
;* Programmer:    Kuria Mbatia
;*
;* Company:       The Pennsylvania State University
;*                School of Electrical Engineering and Computer Science
;*
;* Algorithm:     RTI-based timing
;*                - 1.8ms RTI for timing
;*                - OC5-based wave generation (8000Hz sample rate)
;*                - 24-hour clock
;*                - Simple terminal interface
;*
;* Register use:  A: Display stuff, temp values
;*                B: Timing & counters, temp values
;*                D: 16-bit operations (A:B pair)
;*                X,Y: Loop stuff, string ops, memory access
;*
;* Memory use:    RAM Locations from $3000 for small data variables
;*                RAM Locations from $3100 for program
;*                RAM Locations from $3C00 for constant data (strings, tables)
;*
;* Output:        - Waveform data (0-255 ASCII integers) on SCI terminal
;*                - Time (HH, MM, or SS) on 7-segment LEDs (PORTB)
;*                - LED1 blinks every second (visual heartbeat)
;*
;* Comments:      Uses interrupts for multitasking (RTI for clock, OC5 for waves).
;*                Includes basic error checking for commands and time setting.
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

; Timer registers for wave generation
TIOS        EQU         $0040   ; Timer Input Capture (IC) or Output Compare (OC) select
TIE         EQU         $004C   ; Timer interrupt enable register
TCNTH       EQU         $0044   ; Timer free running main counter
TSCR1       EQU         $0046   ; Timer system control 1
TSCR2       EQU         $004D   ; Timer system control 2
TFLG1       EQU         $004E   ; Timer interrupt flag 1
TC5H        EQU         $005A   ; Timer channel 5 register  << CHANGED from TC6H ($005C)

CR          equ         $0d          ; carriage return, ASCII 'Return' key
LF          equ         $0a          ; line feed, ASCII 'next line' character

; Command buffer size
CMDBUFFER_SIZE EQU      20          ; Size of command buffer

ERR_FORMAT  EQU         1           ; Error code: Format error
ERR_DIV_ZERO EQU        2           ; Error code: Division by zero
ERR_OVERFLOW EQU        3           ; Error code: Overflow error

ERR_REASON_DIGIT EQU    1           ; Error reason: Too many digits

; Wave generation constants
WAVE_POINTS EQU        2048         ; Total wave points to generate (2048)
WAVE_NONE   EQU        0            ; No wave being generated
WAVE_SAW    EQU        1            ; Sawtooth wave type (0-255 over 256 samples)
WAVE_SAW_125 EQU       2            ; Sawtooth wave type (0-255 over 64 samples, 125Hz)
WAVE_TRI    EQU        3            ; Triangle wave type (0-255-0 over 512 samples)
WAVE_SQUARE EQU        4            ; Square wave type (0 for 255, 255 for 255)
WAVE_SQUARE_125 EQU    5            ; Square wave type 125Hz (0 for 32, 255 for 32)

;*******************************************************
; variable/data section
            ORG    $3000             ; RAMStart defined as $3000
                                     ; in MC9S12C128 chip

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
errorFlag   DS.B   1                 ; Error flag (0=no error, 1=error)

; Wave generation variables
waveType    DS.B   1                 ; Type of wave being generated (0=none)
waveCounter DS.W   1                 ; Counter for wave points (0-2047)
waveCompleteFlag DS.B 1            ; Flag set by ISR when wave generation is done
waveDataReady DS.B  1                ; Flag indicating a wave data point is ready to print (set by ISR)
waveDataVal   DS.B  1                ; Value to be printed (set by ISR)

; Buffers and other variables
timeStr     DS.B   9                 ; Buffer for time string (HH:MM:SS\0)
cmdBuffer   DS.B   CMDBUFFER_SIZE    ; Buffer for command input (Use EQU)
errorMsg    DS.B   20                ; Buffer for error messages
BUF         DS.B   6                 ; Character buffer for pnum10
CTR         DS.B   1                 ; Character count for pnum10

;*******************************************************
; code section

            ORG    $3100       ; Program starts at $3100
Entry
            LDS    #$3F00         ; Initialize stack pointer (adjust if needed based on RAM usage)

            ; Initialize hardware
            LDAA   #%11111111   ; Set PORTA and PORTB bit 0,1,2,3,4,5,6,7
            STAA   DDRA         ; all bits of PORTA as output
            STAA   PORTA        ; set all bits of PORTA, initialize
            STAA   DDRB         ; all bits of PORTB as output
            STAA   PORTB        ; set all bits of PORTB, initialize

            ; Initialize serial port for 9600 baud
            ldaa   #$0C         ; Enable SCI port Tx and Rx units
            staa   SCICR2       ; disable SCI interrupts
            ; ldd    #$009C       ; Set SCI Baud Register = $009C => 9600 baud at 24MHz (for hardware)
            ldd    #$0001       ; Set SCI Baud Register = $0001 => 1.5M baud at 24MHz (for simulation, matches sample)
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
            clr    errorFlag    ; No errors to start
            
            ; Initialize wave generation to none
            ldaa   #WAVE_NONE
            staa   waveType
            ldx    #0
            stx    waveCounter
            clr    waveDataReady      ; Initialize flags
            clr    waveDataVal
            clr    waveCompleteFlag
            
            ; Make sure interrupts for wave generator are off at startup
            LDAA   #0
            STAA   TIE          ; No timer interrupts enabled initially
            
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
            
            ; Set up the real-time interrupt - RE-ENABLING
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
            
            ; Check if wave data is ready to be printed by main loop
            ldaa    waveDataReady
            beq     checkWaveComplete   ; No data ready, check if wave finished
            
            sei                      ; <<< Disable interrupts - Start critical section
            ; Data is ready, print it
            clr     waveDataReady    ; Clear the flag first

            ; Set up registers for pnum10
            ldab    waveDataVal      ; Get the value into B
            cli                      ; <<< Enable interrupts - End critical section
            clra                     ; Clear A
            jsr     pnum10           ; Print the number (with newline)
            ; Fall through to check if wave finished
            
checkWaveComplete
            ; Check if wave generation just finished
            ldaa    waveCompleteFlag
            beq     checkUserInput   ; Not complete, check user input
            
            ; Wave complete, print final prompt and reset flag
            clr     waveCompleteFlag ; Reset the completion flag
            jsr     printFinalPrompt ; Print the final "> " prompt
            ; Fall through to check user input
            
checkUserInput
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
            
            ; Just display a simple prompt
            jsr    nextline     ; Start with a fresh line
            
            ; Display simple prompt
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Now the cursor is positioned right after > ready for input
            
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
; NOTE: RTI is currently disabled in Entry for debugging wave generation
rtiisr      psha                 ; <<< Save Accumulator A
            pshb                 ; <<< Save Accumulator B
            pshx                 ; <<< Save Index Register X
            bset   CRGFLG,%10000000 ; Reset the interrupt flag (or it'll keep firing)
            ldx    rtiCounter
            inx                      ; Just counting interrupts
            stx    rtiCounter
            
            ; Check if 1 second has passed (558 * 1.792ms ? 1000ms)
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
            
rtidone     pulx                 ; <<< Restore Index Register X
            pulb                 ; <<< Restore Accumulator B
            pula                 ; <<< Restore Accumulator A
            RTI

;****************displayTime**********************
displayTime pshx
            pshy
            
            ; Start a new line
            jsr    nextline
            
            ; Display simple prompt
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ; Check if user is typing and show command buffer content if so
            ldaa   typingFlag
            beq    noCommand
            
            ; Display the command buffer content
            ldx    #cmdBuffer
dtNextCh:    ldaa   0,x
            beq    dtDone     ; End if null terminator
            jsr    putchar
            inx
            cpx    #cmdBuffer+CMDBUFFER_SIZE
            bne    dtNextCh
dtDone:
            ; Display cursor
            ldaa   #'_'
            jsr    putchar
            
noCommand:
            puly
            pulx
            rts

;****************displayError**********************
; Display error message in Error section
; Input: errorMsg contains error message
displayError
            psha
            pshx
            
            ; Start a new line for error
            jsr    nextline
            
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
            
            ; Add a new line after error message
            jsr    nextline
            
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
            
            ; Clear error message as default
            ldaa   #0
            staa   errorMsg
            clr    errorFlag
            
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
            cmpa   #'g'
            lbeq   checkWaveCommand  ; If 'g', it might be a wave generation command
            
            ; If not a recognized command, show invalid command error
            jmp   invalidNonGCmd ; <<< FIX: Ensure lbra -> jmp
            
; Handler for 'g' commands (wave generation)
checkWaveCommand
            ldx    #cmdBuffer
            ldaa   1,x             ; Check second char
            cmpa   #'w'
            bne    skip_gw_check   ; <<< FIX: Invert logic
            jmp    checkGWCmd      ; <<< FIX: Use jmp
skip_gw_check:
            cmpa   #'t'
            bne    skip_gt_check   ; <<< FIX: Invert logic
            jmp    checkGTCmd      ; <<< FIX: Use jmp
skip_gt_check:
            cmpa   #'q'            
            bne    skip_gq_check   ; <<< FIX: Invert logic
            jmp    checkGQCmd      ; <<< FIX: Use jmp
skip_gq_check:
            ; If second char is not w, t, or q, invalid g command
            jmp   invalidGCmd ; (Already absolute)

checkGWCmd: ; Starts with "gw"
            ; Check character after 'w'
            ldaa   2,x             
            cmpa   #0              ; Is it exactly "gw"?
            bne   skip_genSawtooth ; If not equal, skip long branch
            jmp  generateSawtooth ; <<< FIX: Changed lbra to jmp
skip_genSawtooth:
            
            cmpa   #'2'            ; Is it potentially "gw2" or "gw2 "?
            beq    checkGW2
            
            cmpa   #' '            ; Is it potentially "gw "?
            beq    checkGWSpace

            ; If not null, '2', or ' ', it's invalid
            jmp   invalidGCmd     ; <<< FIX: Reapply lbra -> jmp
            
checkGW2:   ; Starts with "gw2"
            ldaa   3,x             ; Check char after '2'
            cmpa   #0              ; Is it exactly "gw2"?
            bne   skip_genSaw125_2 ; If not equal, skip long branch
            jmp  generateSawtooth125Hz ; <<< FIX: Changed lbra to jmp
skip_genSaw125_2:
            cmpa   #' '            ; Is it "gw2 "?
            beq    skip_jmp_invalid_gw2 ; <<< FIX: Invert logic
            jmp    invalidGCmd          ; <<< FIX: Jump if not space
skip_jmp_invalid_gw2:               ; <<< FIX: Label for skipping jump

checkGWSpace: ; Starts with "gw "
            ; Check if only spaces follow "gw "
            ldx    #cmdBuffer
            inx                    ; Standard HCS12 way to add 3 to X
            inx
            inx
checkOnlySpacesAfterGW_Loop:
            ldaa   0,x
            cmpa   #0              ; End of string?
            bne    skip_jmp_gw     ; Not end? Check if space
            jmp    generateSawtooth ; End of string? Valid, jump to generate
skip_jmp_gw:
            cmpa   #' '            ; Is it a space?
            beq    is_space_gw     ; Branch if space
            jmp    invalidGCmd     ; <<< FIX: Ensure this is jmp (was already changed)
is_space_gw:                     ; <<< FIX: Label for skipping jump
            inx
            bra    checkOnlySpacesAfterGW_Loop

checkOnlySpacesAfterGW2:
            ; Check if only spaces follow "gw2 "
            ldx    #cmdBuffer
            inx                    ; Standard HCS12 way to add 4 to X
            inx
            inx
            inx
checkOnlySpacesAfterGW2_Loop:
            ldaa   0,x
            cmpa   #0              ; End of string?
            bne   skip_genSaw125_SpacesCheckEnd ; <<< FIX Branch to unique label
            jmp  generateSawtooth125Hz ; <<< FIX: Changed lbra to jmp
skip_genSaw125_SpacesCheckEnd:      ; <<< FIX Unique label definition
            cmpa   #' '            ; Is it a space?
            beq    is_space_gw2    ; <<< FIX: Invert logic
            jmp    invalidGCmd     ; <<< FIX: Jump if not space
is_space_gw2:                     ; <<< FIX: Label for skipping jump
            inx
            bra    checkOnlySpacesAfterGW2_Loop
            
checkGTCmd: ; Starts with "gt"
            ; Check character after 't'
            ldaa   2,x
            cmpa   #0              ; Is it exactly "gt"?
            bne   skip_genTri      ; If not equal, skip long branch
            jmp  generateTriangleWave ; <<< FIX: Changed lbra to jmp
skip_genTri:
            cmpa   #' '            ; Is it potentially "gt "?
            bne    skip_gt_space_jmp ; <<< FIX: Invert logic
            jmp    checkGTSpace      ; <<< FIX: Use jmp
skip_gt_space_jmp:
            ; If not null or space, invalid gt command
            jmp   invalidGCmd     ; (Already absolute)

checkGTSpace: ; Starts with "gt "
            ; Check if only spaces follow "gt "
            ldx    #cmdBuffer
            inx                    ; Point after "gt "
            inx
            inx
checkOnlySpacesAfterGT_Loop:
            ldaa   0,x
            cmpa   #0              ; End of string?
            bne   skip_genTri2     ; If not equal, skip long branch
            jmp  generateTriangleWave ; <<< FIX: Changed lbra to jmp
skip_genTri2:
            cmpa   #' '            ; Is it a space?
            beq    continue_gt_space_check ; If equal (space), continue loop
            jmp   invalidGCmd           ; If not equal (not space), it's invalid
continue_gt_space_check:
            inx
            bra    checkOnlySpacesAfterGT_Loop

; Handler for 'gq' commands
checkGQCmd: ; Starts with "gq"
            ldx    #cmdBuffer      ; <<< Assume X points to cmdBuffer here
            ; Check character after 'q'
            ldaa   2,x
            cmpa   #0              ; Is it exactly "gq"?
            bne    skip_genSquare   ; If not equal, check for space or '2'
            jmp   generateSquareWave ; If equal, generate standard square
skip_genSquare:
            cmpa   #'2'            ; Is it potentially "gq2" or "gq2 "?
            beq    checkGQ2        ; <<< ADD: Branch to check gq2
            cmpa   #' '            ; Is it potentially "gq "?
            beq    checkGQSpace    ; Handle "gq "
            ; If not null, '2', or space, invalid gq command
            jmp   invalidGCmd ; <<< Use jmp

checkGQ2:   ; Starts with "gq2"
            ldaa   3,x             ; Check char after '2'
            cmpa   #0              ; Is it exactly "gq2"?
            bne   skip_genSquare125_2 ; If not equal, check for space
            jmp  generateSquareWave125Hz ; If equal, generate 125Hz square
skip_genSquare125_2:
            cmpa   #' '            ; Is it "gq2 "?
            beq    checkOnlySpacesAfterGQ2 ; Check for spaces after
            jmp    invalidGCmd     ; Invalid if anything else follows "gq2"

checkGQSpace: ; Starts with "gq "
            ; Check if only spaces follow "gq "
            ldx    #cmdBuffer
            inx                    ; Point after "gq "
            inx
            inx
checkOnlySpacesAfterGQ_Loop:
            ldaa   0,x
            cmpa   #0              ; End of string?
            bne    skip_genSquare2 ; If not equal, check space
            jmp   generateSquareWave ; <<< FIX: Changed lbra to jmp
skip_genSquare2:
            cmpa   #' '            ; Is it a space?
            beq    continue_gq_space_check ; If equal (space), continue loop
            jmp   invalidGCmd           ; If not equal (not space), it's invalid
continue_gq_space_check:
            inx
            bra    checkOnlySpacesAfterGQ_Loop

checkOnlySpacesAfterGQ2:
            ; Check if only spaces follow "gq2 "
            ldx    #cmdBuffer
            inx                    ; Standard HCS12 way to add 4 to X
            inx
            inx
            inx
checkOnlySpacesAfterGQ2_Loop:
            ldaa   0,x
            cmpa   #0              ; End of string?
            bne   skip_genSquare125_SpacesCheckEnd
            jmp  generateSquareWave125Hz ; Valid if end
skip_genSquare125_SpacesCheckEnd:
            cmpa   #' '            ; Is it a space?
            beq    continue_gq2_space_check
            jmp    invalidGCmd     ; Invalid if not space
continue_gq2_space_check:
            inx
            bra    checkOnlySpacesAfterGQ2_Loop

invalidGCmd:
            ; Generic invalid 'g' command error (or general invalid)
            ldx    #errInvalid
            jsr    copyMsg
            ldaa   #1
            staa   errorFlag
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp
            
invalidNonGCmd: ; Handler for commands not starting with g, t, h, m, s, q
            ldx    #errInvalid
            jsr    copyMsg
            ldaa   #1
            staa   errorFlag
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp
            
; Generate Sawtooth wave (for gw)
generateSawtooth
            ; Initialize wave generation variables FIRST
            ldaa   #WAVE_SAW
            staa   waveType
            ldx    #0
            stx    waveCounter     ; Reset wave counter to 0
            clr    waveDataReady   ; Clear flags
            clr    waveDataVal
            clr    waveCompleteFlag

            ; Enable global interrupts *just before* starting timer
            CLI

            ; Start the timer interrupt for wave generation
            jsr    StartTimer5oc   ; <<< CHANGED from StartTimer6oc

            ; Display sawtooth wave message
            jsr    nextline
            
            ldaa   #' '            ; Add spacing for formatting
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ldx    #msgSawWave     ; Display sawtooth message
            jsr    printmsg
            
            ; Clear error message
            ldx    #errorMsg
            clr    0,x             ; No error
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp
            
; Generate Sawtooth 125Hz wave
generateSawtooth125Hz
            ; Initialize wave generation variables FIRST
            ldaa   #WAVE_SAW_125   ; <<< Set wave type to 125Hz Sawtooth
            staa   waveType
            ldx    #0
            stx    waveCounter     ; Reset wave counter to 0
            clr    waveDataReady   ; Clear flags
            clr    waveDataVal
            clr    waveCompleteFlag

            ; Enable global interrupts *just before* starting timer
            CLI
            
            ; Start the timer interrupt for wave generation
            jsr    StartTimer5oc   ; <<< CHANGED from StartTimer6oc

            ; Display sawtooth wave message
            jsr    nextline
            
            ldaa   #' '            ; Add spacing for formatting
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ldx    #msgSawWave125Hz ; <<< Use 125Hz message
            jsr    printmsg
            
            ; Clear error message
            ldx    #errorMsg
            clr    0,x             ; No error
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

; Generate Triangle wave (for gt)
generateTriangleWave
            ; Initialize wave generation variables FIRST
            ldaa   #WAVE_TRI       ; <<< Set wave type to Triangle
            staa   waveType
            ldx    #0
            stx    waveCounter     ; Reset wave counter to 0
            clr    waveDataReady   ; Clear flags
            clr    waveDataVal
            clr    waveCompleteFlag

            ; Enable global interrupts *just before* starting timer
            CLI

            ; Start the timer interrupt for wave generation
            jsr    StartTimer5oc   ; <<< CHANGED from StartTimer6oc

            ; Display triangle wave message
            jsr    nextline
            
            ldaa   #' '            ; Add spacing for formatting
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            
            ldx    #msgTriWave     ; <<< Use Triangle message
            jsr    printmsg
            
            ; Clear error message
            ldx    #errorMsg
            clr    0,x             ; No error
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

; Generate Square wave (for gq)
generateSquareWave
            ; Initialize wave generation variables FIRST
            ldaa   #WAVE_SQUARE    ; <<< Set wave type to Square
            staa   waveType
            ldx    #0
            stx    waveCounter     ; Reset wave counter to 0
            clr    waveDataReady   ; Clear flags
            clr    waveDataVal
            clr    waveCompleteFlag

            ; Enable global interrupts *just before* starting timer
            CLI

            ; Start the timer interrupt for wave generation
            jsr    StartTimer5oc   ; <<< CHANGED from StartTimer6oc

            ; Display square wave message
            jsr    nextline

            ldaa   #' '            ; Add spacing for formatting
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar

            ldx    #msgSquareWave  ; <<< Use Square message
            jsr    printmsg

            ; Clear error message
            ldx    #errorMsg
            clr    0,x             ; No error

            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

; Generate Square 125Hz wave (for gq2)
generateSquareWave125Hz
            ; Initialize wave generation variables FIRST
            ldaa   #WAVE_SQUARE_125 ; <<< Set wave type to 125Hz Square
            staa   waveType
            ldx    #0
            stx    waveCounter     ; Reset wave counter to 0
            clr    waveDataReady   ; Clear flags
            clr    waveDataVal
            clr    waveCompleteFlag

            ; Enable global interrupts *just before* starting timer
            CLI

            ; Start the timer interrupt for wave generation
            jsr    StartTimer5oc   ; <<< CHANGED from StartTimer6oc

            ; Display square wave 125Hz message
            jsr    nextline

            ldaa   #' '            ; Add spacing for formatting
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            ldaa   #' '
            jsr    putchar

            ldx    #msgSquareWave125Hz  ; <<< Use Square 125Hz message
            jsr    printmsg

            ; Clear error message
            ldx    #errorMsg
            clr    0,x             ; No error

            jmp   cmdDone

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
            clr    errorFlag   ; Clear error flag
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

invalidTime
            ; Set error message for invalid time
            ldx    #errTimeFormat  ; Use the more descriptive time format error message
            jsr    copyMsg
            ldaa   #1
            staa   errorFlag
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

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
            lbne   invalidNonGCmd ; <<< FIX - Branch to general invalid handler
            
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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

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

;***************StartTimer5oc************************
;* Program: Start the timer interrupt, timer channel 5 output compare
;* Input:   None
;* Output:  Timer Channel 5 interrupt is enabled and configured
;* Registers modified: A, CCR
;* Algorithm:
;*  Sets Timer Channel 5 to Output Compare mode.
;*  Enables Timer system.
;*  Sets initial Output Compare time (TCNT + interval).
;*  Clears TC5 flag and enables TC5 interrupt.
;**********************************************
StartTimer5oc                 ; <<< RENAMED from StartTimer6oc
            PSHD
            
            LDAA   #%00100000        ; <<< CHANGED to bit 5 for channel 5
            STAA   TIOS              ; set CH5 Output Compare
            
            LDAA   #%10000000        ; enable timer, Fast Flag Clear not set
            STAA   TSCR1
            LDAA   #%00000000        ; TOI Off, TCRE Off, TCLK = BCLK/1
            STAA   TSCR2             ; not needed if started from reset

            LDD    #3000             ; 125usec with (24MHz/1 clock)
            ADDD   TCNTH             ; for first interrupt
            STD    TC5H              ; <<< CHANGED to TC5H

            BSET   TFLG1,%00100000   ; <<< CHANGED to bit 5 for channel 5 flag (C5F)
            LDAA   #%00100000        ; <<< CHANGED to bit 5 for channel 5
            STAA   TIE               ; set CH5 interrupt Enable
            
            PULD                   ; Restore registers
            RTS
;***************end of StartTimer5oc*****************

;***********Timer OC5 interrupt service routine***************
;* Flag-setting ISR for TC5
;* Generates wave data point and sets flag for main loop
;* Input:   None (triggered by hardware)
;* Output:  waveDataVal set, waveDataReady set, waveCompleteFlag set on completion
;* Registers modified: D (A, B), CCR
;* Uses:    waveType, waveCounter, waveDataVal, waveDataReady, waveCompleteFlag
;**************************************************************
oc5isr      pshd                 ; <<< RENAMED from oc6isr, Save D (A and B)

            ; 1. Set up next interrupt
            ldd   #3000              ; 125usec interval
            addd  TC5H               ; <<< CHANGED Using TC5H
            std   TC5H               ; <<< CHANGED Using TC5H
            bset  TFLG1,%00100000    ; <<< CHANGED Clear C5F flag (Bit 5)

            ; 2. Increment counter
            ldd   waveCounter
            addd  #1                 ; Increment D (counter value)
            std   waveCounter

            ; 3. Check if finished
            cpd   #WAVE_POINTS       ; Compare D (counter) with max points
            bhs   oc5_stopWave_minimal ; <<< RENAMED If counter >= WAVE_POINTS, stop

            ; Branch based on wave type
            ldaa  waveType
            cmpa  #WAVE_SAW
            beq   oc5_setDataFlag      ; <<< RENAMED Handle standard sawtooth
            cmpa  #WAVE_SAW_125
            beq   oc5_setDataFlag_125Hz ; <<< RENAMED Handle 125Hz sawtooth
            cmpa  #WAVE_TRI
            beq   oc5_setDataFlag_Tri   ; <<< RENAMED Handle Triangle
            cmpa  #WAVE_SQUARE
            beq   oc5_setDataFlag_Square ; <<< RENAMED Handle Square
            cmpa  #WAVE_SQUARE_125
            beq   oc5_setDataFlag_Square125 ; <<< RENAMED Handle 125Hz Square
            ; Add checks for other wave types here if needed
            bra   oc5_done_minimal     ; <<< RENAMED Unknown type, just return

            ; 4a. Not finished (Standard Sawtooth): Store lower byte and set ready flag
oc5_setDataFlag:                     ; <<< RENAMED
            ; D holds waveCounter here
            stab  waveDataVal        ; Store lower byte of counter (in B)
            ldaa  #1
            staa  waveDataReady
            bra   oc5_done_minimal   ; <<< RENAMED Go to RTI

            ; 4b. Not finished (125Hz Sawtooth): Calculate scaled value
oc5_setDataFlag_125Hz:               ; <<< RENAMED
            ; D still holds waveCounter value from increment/check
            andb  #$3F               ; Isolate lower 6 bits (0-63) in B
            aslb                     ; B = B * 2
            aslb                     ; B = B * 4 (scales 0-63 to 0-252)
            stab  waveDataVal        ; Store the calculated value
            ldaa  #1
            staa  waveDataReady      ; Set data ready flag
            bra   oc5_done_minimal   ; <<< RENAMED Go to RTI

            ; 4c. Not finished (Triangle): Calculate value
oc5_setDataFlag_Tri:                 ; <<< RENAMED
            ldd   waveCounter      ; <<< RELOAD waveCounter into D
            ; Perform D = waveCounter & $01FF using standard instructions
            anda #$01              ; A = A & $01 (Mask high byte)
            andb #$FF              ; B = B & $FF (Mask low byte - effectively no change, but good practice)

            ; Check if D < 256 (equivalent to checking if A == 0)
            tsta                   ; Test accumulator A
            beq  tri_ramp_up_calc  ; If A is zero (D < 256), branch to ramp up

            ; else (D >= 256), calculate 511 - phase (which is equivalent to 255 - lower_byte_of_phase)
            comb                   ; B = 255 - B (where B is lower byte of phase)
            lbra tri_store_value   ; Branch to store the calculated value
            
tri_ramp_up_calc:
            ; B already holds the correct ramp-up value (lower byte of phase)
            nop                    ; Placeholder if needed, B holds the value
            
tri_store_value:                 ; Common store point
            stab waveDataVal         ; Store B (holds ramp-up or ramp-down value)
            ldaa #1
            staa waveDataReady       ; Set data ready flag
            bra  oc5_done_minimal    ; <<< RENAMED Go to RTI

            ; 4d. Not finished (Square): Calculate value
        oc5_setDataFlag_Square:          ; <<< RENAMED
            ldd   waveCounter      ; Reload waveCounter into D
            ; Determine output based on phase within a 512-sample cycle
            ; phase = waveCounter & $01FF
            anda #$01              ; A = high byte of phase
            ; andb #$FF            ; B = low byte of phase (optional, B not used directly here)

            ; Check if phase < 256 (high byte A == 0)
            tsta                   ; Test accumulator A
            beq  square_set_zero   ; If A is zero (phase 0-255), output 0

            ; Else (phase is 256-511), output 255
            ldab #255
            bra  square_store_value

        square_set_zero:
            clrb                   ; Output 0

        square_store_value:        ; Common store point
            stab waveDataVal       ; Store B (0 or 255)
            ldaa #1
            staa waveDataReady     ; Set data ready flag
            bra  oc5_done_minimal  ; <<< RENAMED Go to RTI

            ; 4e. Not finished (125Hz Square): Calculate value
oc5_setDataFlag_Square125:           ; <<< RENAMED
            ldab  waveCounter+1    ; Load low byte of waveCounter into B
            andb  #$3F             ; Mask lower 6 bits (0-63) to get phase within 64-sample cycle

            ; Check if phase < 32
            cmpb  #32
            blo   square125_set_zero ; If B < 32, output 0

            ; Else (phase is 32-63), output 255
            ldab #255
            bra  square125_store_value

square125_set_zero:
            clrb                   ; Output 0

square125_store_value:       ; Common store point
            stab waveDataVal       ; Store B (0 or 255)
            ldaa #1
            staa waveDataReady     ; Set data ready flag
            bra  oc5_done_minimal  ; <<< RENAMED Go to RTI

            ; 5. Finished: Disable interrupt, reset type, set complete flag
oc5_stopWave_minimal:                ; <<< RENAMED
            ldaa  #%11011111         ; <<< CHANGED Mask to disable ONLY TC5 interrupt (bit 5)
            anda  TIE                ; Read current TIE
            staa  TIE                ; Write back with TC5 bit cleared
            ldaa  #WAVE_NONE         ; Set wave type back to none
            staa  waveType
            ldaa  #1
            staa  waveCompleteFlag   ; Set complete flag for main loop

            ; 6. Return from interrupt
oc5_done_minimal:                    ; <<< RENAMED
            puld                 ; <<< Restore D (A and B)
            RTI
;***********end of Timer OC5 interrupt service routine********

;***********Minimal Timer OC5 ISR for Testing***************
;* Renamed from oc6isr_test_minimal
;* This ISR does almost nothing - just clears flag and sets next time.
;* Used to test if the interrupt itself causes the crash.
;* COMMENTED OUT - Restore if needed for debugging
;**************************************************************
; oc5isr_test_minimal: ; <<< RENAMED
;     pshd                  ; Save D
;     ldd   #3000           ; Next interrupt time
;     addd  TC5H            ; <<< CHANGED to TC5H
;     std   TC5H            ; <<< CHANGED to TC5H
;     bset  TFLG1,%00100000 ; <<< CHANGED to bit 5 for C5F flag
;     puld                  ; Restore D
;     RTI
;***********End of Minimal Test ISR*************************

;*******************************************************
; RE-INSERTED MISSING SUBROUTINES BELOW
;*******************************************************

;***********pnum10***************************
;* Program: print a word (16bit) in decimal to SCI port
;* Input:   Register D contains a 16 bit number to print in decimal number
;* Output:  decimal number printed on the terminal connected to SCI port
;* 
;* Registers modified: CCR
;* Algorithm:
;     Keep divide number by 10 and keep the remainders
;     Then send it out to SCI port
;*  Need memory location for counter CTR and buffer BUF(6 byte max)
;**********************************************
pnum10      pshd                   ; Save registers
            pshx
            pshy
            
            clr     CTR            ; Clear character count of an 8 bit number

            ldy     #BUF
pnum10p1    ldx     #10
            idiv                   ; D / X -> X = quotient, D = remainder
            beq     pnum10p2       ; If quotient is 0, we're done dividing
            stab    1,y+           ; Store remainder (in B) in buffer
            inc     CTR            ; Increment counter
            tfr     x,d            ; Transfer quotient to D for next division
            bra     pnum10p1       ; Continue dividing

pnum10p2    stab    1,y+           ; Store final remainder
            inc     CTR                        

;--------------------------------------
pnum10p3    ldaa    #$30           ; ASCII '0'      
            adda    1,-y           ; Add digit value to '0' to get ASCII digit
            jsr     putchar        ; Output the character
            dec     CTR            ; Decrement counter
            bne     pnum10p3       ; Continue until all digits are printed
            
            ; Add newline at the end
            jsr     nextline
            
            puly
            pulx
            puld
            rts
;***********end of pnum10********************

;****************checkHourCommand*******************
; Check if the hour command is valid (just 'h' alone)
checkHourCommand
            ; Check if any characters after 'h'
            ldx    #cmdBuffer
            inx                ; Point to character after 'h'
            ldaa   0,x         ; Get character after 'h'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidNonGCmd ; <<< FIX - Branch to general invalid handler
            
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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

;****************checkMinuteCommand*****************
; Check if the minute command is valid (just 'm' alone)
checkMinuteCommand
            ; Check if any characters after 'm'
            ldx    #cmdBuffer
            inx                ; Point to character after 'm'
            ldaa   0,x         ; Get character after 'm'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidNonGCmd ; <<< FIX - Branch to general invalid handler
            
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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

;****************checkSecondCommand*****************
; Check if the second command is valid (just 's' alone)
checkSecondCommand
            ; Check if any characters after 's'
            ldx    #cmdBuffer
            inx                ; Point to character after 's'
            ldaa   0,x         ; Get character after 's'
            cmpa   #0          ; Is it null terminator?
            lbne   invalidNonGCmd ; <<< FIX - Branch to general invalid handler
            
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
            
            jmp   cmdDone ; <<< FIX: Reapply lbra -> jmp

;****************printFinalPrompt*******************
; Prints the simple "> " prompt after wave generation finishes
printFinalPrompt
            psha
            ldaa   #CR
            jsr    putchar          ; Ensure it's on a new line
            ldaa   #LF
            jsr    putchar
            ldaa   #'>'
            jsr    putchar
            ldaa   #' '
            jsr    putchar
            pula
            rts

;*******************************************************
; Larger Data Structures Section

cmdDone:    ; <<< RESTORED LABEL
            ; Thoroughly clear the command buffer - all bytes to 0
            pshx
            ldx    #cmdBuffer
cmdClearLoop:
            clr    0,x
            inx
            cpx    #cmdBuffer+CMDBUFFER_SIZE   ; Check if we've cleared all 20 bytes
            blo    cmdClearLoop
            pulx
            
            ; Force a display update now that command is processed
            ldaa   #1
            staa   dispFlag
            
            ; Restore registers from processCmd entry
            pulx
            pulb
            pula
            rts ; <<< Ensure RTS is here for processCmd exit

;*******************************************************
; Constant Data Section (Tables, Strings, etc.)
            ORG    $3C00             ; Start constant data after code

; 7-segment display digit encoding table (0-9)
; Segment pattern for common cathode display: 0bABCDEFG
segTable    DC.B   $3F,$06,$5B,$4F,$66,$6D,$7D,$07,$7F,$6F

; Display messages and strings
msg1        DC.B   'Clock Program', $00
msg2        DC.B   'Type t HH:MM:SS to set time', $00
errInvalid  DC.B   'Invalid input format', $00
errTimeFormat DC.B  'Invalid time format. Correct example => 00:00:00 to 23:59:59', $00
errHourCmd  DC.B   'Invalid command. ("h" for hour display only)', $00
errMinCmd   DC.B   'Invalid command. ("m" for minute display only)', $00
errSecCmd   DC.B   'Invalid command. ("s" for second display only)', $00
errQuitCmd  DC.B   'Invalid command. ("q" for quit only)', $00
typewriterMsg1 DC.B   'Wave Generator and Clock stopped and Typewrite program started.', $00
typewriterMsg2 DC.B   'You may type below.', $00
msgHourDisp DC.B   'Hours on display', $00
msgMinDisp  DC.B   'Mins on display', $00
msgSecDisp  DC.B   'Secs on display', $00
msgSawWave  DC.B   'sawtooth wave generation ....', $00
msgSawWave125Hz DC.B ' sawtooth wave 125Hz generation ....', $00
msgTriWave  DC.B   ' triangle wave generation ....', $00
msgSquareWave DC.B ' square wave generation ....', $00
msgSquareWave125Hz DC.B ' square wave 125Hz generation ....', $00
crlfStr     DC.B   CR,LF,$00         ; Carriage return and line feed

;*******************************************************
; interrupt vector section (Keep at the end or specified location)
            ORG    $FFF0             ; RTI interrupt vector setup for the simulator
;            ORG    $3FF0             ; RTI interrupt vector setup for the CSM-12C128 board
            DC.W   rtiisr

;           ORG    $FFE2             ; Timer channel 6 interrupt vector setup (NOT USED ANYMORE)
;           DC.W   oc6isr_test_minimal ; <<< Minimal test ISR (commented out)
;           DC.W   oc6isr              ; <<< Point to full flag-setting ISR for TC6

            ORG    $FFE4             ; Timer channel 5 interrupt vector setup << MOVED & CHANGED
            DC.W   oc5isr              ; <<< Point to full flag-setting ISR for TC5

            END               ; this is end of assembly source file