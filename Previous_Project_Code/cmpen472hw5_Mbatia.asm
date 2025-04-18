***********************************************************************
*
* Title:         Advanced LED Control with Serial Interface
* 
* Objective:     CMPEN 472 Homework 5 - Fixed Version
*
* Revision:      V2.1
*
* Date:          Feb. 17, 2025
*
* Programmer:    Kuria Mbatia
*
* Company:       The Pennsylvania State University
*
* Algorithm:     Serial command processing with PWM and mode switching
*
* Register use:  A: Command processing, temp calculations
*                B: Bit manipulation, counters
*                X,Y: Pointers and delay counters
*                Z: Not used
*
* Description:   Program is an LED control system using
*                serial communication. It controls 4 LEDs 
*                through an interface in the terminal.
*                
*                Features:
*                - Controls 4 LEDs (LED1-LED4) independently
*                - Commands for each LED: Lx (turn on), Fx (turn off), where x=1-4
*                - Special PWM control for LED4 with fading effects
*                - LED4 fades up/down over 0.4 seconds with 100 brightness levels
*                - QUIT command to enter typewriter mode
*                - Error checking and invalid command handling(logically)
*                
*
*                Commands:
*                L1-L3: Turn on respective LED
*                F1-F3: Turn off respective LED
*                L4: Fade LED4 from 0% to 100% brightness
*                F4: Fade LED4 from 100% to 0% brightness
*                QUIT: Exit to typewriter mode
***********************************************************************
* Parameter Declaration Section
*
* Export Symbols
            XDEF        pstart      ; Program entry point
            ABSENTRY    pstart      ; For absolute assembly

* Symbols and Macros
PORTB       EQU         $0001       ; LED outputs (bits 4-7)
DDRB        EQU         $0003       ; Data Direction Register B

SCIBDH      EQU         $00C8       ; Serial port (SCI) Baud Register High
SCIBDL      EQU         $00C9       ; Serial port (SCI) Baud Register Low
SCICR2      EQU         $00CB       ; Serial port (SCI) Control Register 2
SCISR1      EQU         $00CC       ; Serial port (SCI) Status Register 1
SCIDRL      EQU         $00CF       ; Serial port (SCI) Data Register Low

CR          EQU         $0D         ; ASCII carriage return
LF          EQU         $0A         ; ASCII line feed
NULL        EQU         $00         ; ASCII null

***********************************************************************
* Data Section - Variables and Strings
***********************************************************************
            ORG         $3000       ; Start of data section

Counter1    DC.W        $1B58       ; PWM timing constant 
LightLevel  DC.B        0           ; Current LED brightness (0-100)
cmdLength   DS.B        1           ; Length of current command
cmdBuffer   DS.B        8           ; Command input buffer
tempChar    DS.B        1           ; Temporary character storage

msgMenu     DC.B        'LED Control Menu:',CR,LF
            DC.B        'L1/F1: LED1 On/Off',CR,LF
            DC.B        'L2/F2: LED2 On/Off',CR,LF
            DC.B        'L3/F3: LED3 On/Off',CR,LF
            DC.B        'L4: LED4 fade up',CR,LF
            DC.B        'F4: LED4 fade down',CR,LF
            DC.B        'QUIT: Enter typewriter mode',CR,LF,NULL

msgPrompt   DC.B        '> ',NULL
msgInvalid  DC.B        'Invalid command. Please try again.',CR,LF,NULL
msgQuit     DC.B        'Entering Typewriter Mode...',CR,LF,NULL

***********************************************************************
* Program Section
***********************************************************************
            ORG         $3100       ; Start of program section
            
pstart      LDS         #$3100      ; Initialize stack pointer

            ; Initialize hardware
            LDAA        #%11111111  ; Set PORTB as all outputs
            STAA        DDRB
            CLR         PORTB       ; Clear all outputs initially

            ; Initialize serial port
            LDAA        #$0C        ; Enable SCI transmitter and receiver
            STAA        SCICR2
            LDD         #$0001      ; Set baud rate
            STD         SCIBDH      

mainInit    ; Print menu and enter main loop
            LDX         #msgMenu
            JSR         printmsg

mainLoop    LDX         #msgPrompt  ; Show command prompt
            JSR         printmsg
            
            JSR         getCommand  ; Get command from user
            TST         cmdLength   ; Check if command was valid
            BEQ         mainLoop    ; If zero length, restart
            
            JSR         processCmd  ; Process the command
            BRA         mainLoop    ; Return to main loop

***********************************************************************
* Command Processing Subroutines
***********************************************************************
getCommand  CLR         cmdLength   ; Reset command length
            LDY         #cmdBuffer  ; Point to start of buffer
            
gcLoop      JSR         getchar     ; Get a character
            CMPA        #CR         ; Check for Enter key
            BEQ         gcDone      ; If Enter, we're done
            
            CMPA        #LF         ; Ignore line feeds
            BEQ         gcLoop
            
            ; Check maximum command length
            LDAB        cmdLength
            CMPB        #7          ; Maximum 7 chars (QUIT + margin)
            BHS         gcInvalid   ; If exceeded, invalid
            
            JSR         putchar     ; Echo character
            STAA        0,Y         ; Store in buffer
            INY                     ; Next buffer position
            INC         cmdLength   ; Count the character
            BRA         gcLoop      ; Get next character
            
gcInvalid   LDX         #msgInvalid ; Show error
            JSR         printmsg
            CLR         cmdLength   ; Invalidate command
            RTS
            
gcDone      CLR         0,Y         ; Null-terminate buffer
            RTS

processCmd  LDX         #cmdBuffer  ; Point to command

            ; Check for QUIT command
            LDAA        cmdLength
            CMPA        #4          ; QUIT must be exactly 4 chars
            BNE         checkLF     ; If not, check for LED commands
            
            LDAA        0,X         ; Check 'Q'
            CMPA        #'Q'
            BNE         invalidCmd
            LDAA        1,X         ; Check 'U'
            CMPA        #'U'
            BNE         invalidCmd
            LDAA        2,X         ; Check 'I'
            CMPA        #'I'
            BNE         invalidCmd
            LDAA        3,X         ; Check 'T'
            CMPA        #'T'
            BNE         invalidCmd
            
            LDX         #msgQuit    ; Show quit message
            JSR         printmsg
            JSR         typewriter  ; Enter typewriter mode
            RTS

checkLF     LDAA        cmdLength
            CMPA        #2          ; L/F commands must be exactly 2 chars
            BNE         invalidCmd
            
            LDAA        0,X         ; Get command type (L/F)
            CMPA        #'L'
            BEQ         checkLEDNum
            CMPA        #'F'
            BEQ         checkLEDNum
            BRA         invalidCmd

checkLEDNum LDAA        1,X         ; Get LED number
            SUBA        #'0'        ; Convert ASCII to number
            CMPA        #1          ; Check range 1-4
            BLO         invalidCmd
            CMPA        #4
            BHI         invalidCmd
            
            LDAB        0,X         ; Get command type again
            CMPB        #'L'        ; Check if turn on
            BEQ         turnOnLED
            BRA         turnOffLED

turnOnLED   DECA                    ; Convert 1-4 to 0-3
            CMPA        #3          ; Check if LED4
            BEQ         led4On      ; Special handling for LED4
            JSR         onLED       ; Regular LED
            RTS

turnOffLED  DECA                    ; Convert 1-4 to 0-3
            CMPA        #3          ; Check if LED4
            BEQ         led4Off     ; Special handling for LED4
            JSR         offLED      ; Regular LED
            RTS

invalidCmd  LDX         #msgInvalid
            JSR         printmsg
            RTS

***********************************************************************
* LED Control Subroutines
***********************************************************************
onLED       PSHA                    ; Save LED number
            ADDA        #4          ; Convert to bit position (4-7)
            TAB                     ; Transfer to B for bit shifting
            LDAA        #1          ; Start with bit 0
shiftOn     DECB
            BMI         doneOn
            LSLA                    ; Shift left until desired position
            BRA         shiftOn
doneOn      ORAA        PORTB      ; Set the bit
            STAA        PORTB
            PULA                    ; Restore LED number
            RTS

offLED      PSHA                    ; Save LED number
            ADDA        #4          ; Convert to bit position (4-7)
            TAB                     ; Transfer to B for bit shifting
            LDAA        #1          ; Start with bit 0
shiftOff    DECB
            BMI         doneOff
            LSLA                    ; Shift left until desired position
            BRA         shiftOff
doneOff     COMA                    ; Complement to create mask
            ANDA        PORTB       ; Clear the bit
            STAA        PORTB
            PULA                    ; Restore LED number
            RTS

***********************************************************************
* LED4 PWM Control Subroutines
***********************************************************************
led4On      LDAA        LightLevel
            CMPA        #100        ; Check if already at max
            BEQ         endOn
            CLRA                    ; Start from 0%
            STAA        LightLevel
fadeUpLoop  JSR         updatePWM   ; Update brightness
            INCA                    ; Increase level
            STAA        LightLevel
            CMPA        #100        ; Check if max reached
            BLO         fadeUpLoop
            BSET        PORTB,#%10000000 ; Set final state
endOn       RTS

led4Off     LDAA        LightLevel
            CMPA        #0          ; Check if already off
            BEQ         endOff
            LDAA        #100        ; Start from 100%
            STAA        LightLevel
fadeDownLoop JSR        updatePWM   ; Update brightness
            DECA                    ; Decrease level
            STAA        LightLevel
            BNE         fadeDownLoop
            BCLR        PORTB,#%10000000 ; Clear final state
endOff      RTS

updatePWM   PSHA
            PSHB
            PSHX
            
            ; ON time calculation
            LDAA        LightLevel  ; Get brightness level
            BEQ         skipOn      ; Skip if 0%
            
            BSET        PORTB,#%10000000 ; LED on
            LDX         #600        ; Base delay count
onOuter     LDAB        #10        ; Inner loop multiplier
onInner     DECB
            BNE         onInner
            DEX
            BNE         onOuter

skipOn      ; OFF time calculation
            BCLR        PORTB,#%10000000 ; LED off
            LDAB        #100
            SUBB        LightLevel  ; Get off-time percentage
            BEQ         skipOff     ; Skip if 100% on
            
            LDX         #600        ; Match on-time base count
offOuter    LDAB        #10        ; Match inner multiplier
offInner    DECB
            BNE         offInner
            DEX
            BNE         offOuter

skipOff     PULX
            PULB
            PULA
            RTS

***********************************************************************
* Typewriter Mode Subroutine
***********************************************************************
typewriter  JSR         getchar     ; Get a character
            CMPA        #CR         ; Check for Enter key
            BEQ         twExit      ; If Enter, exit
            JSR         putchar     ; Echo the character
            BRA         typewriter  ; Loop for next character
twExit      RTS

***********************************************************************
* Utility Subroutines
***********************************************************************
printmsg    PSHA                    ; Save registers
printLoop   LDAA        0,X         ; Get next character
            BEQ         printDone   ; If null, done
            JSR         putchar     ; Print it
            INX                     ; Next character
            BRA         printLoop
printDone   PULA                    ; Restore registers
            RTS

putchar     BRCLR       SCISR1,#%10000000,putchar ; Wait for transmit ready
            STAA        SCIDRL      ; Send character
            RTS

getchar     BRCLR       SCISR1,#%00100000,getchar ; Wait for receive
            LDAA        SCIDRL      ; Get character
            RTS

            END