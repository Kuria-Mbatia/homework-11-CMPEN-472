************************************************************************
* Title:        LED Control Implementation
*
* Objective:    CMPEN 472 Homework 4
*               LED dimming using timing control
* Revision:     V1.0 for Codewarrior 5.2 Debugger Simultion
*
*
* Date:         February 14, 2025
*
* Programmer:   Kuria Mbatia
*
* Company:      The Pennsylvania State University
*               Department of Computer Science and Engineering
*
*
* Description:  This program demonstrates LED control and dimming effects:
*               1. Sets initial LED states:
*                 - LED 1: ON  (100% brightness)
*                 - LED 2: OFF (0% brightness)
*                 - LED 3: ON  (100% brightness)
*               2. Controls LED 4 in a continuous cycle:
*                 - Fades from 0% to 100% brightness in 0.4 seconds
*                 - Fades from 100% to 0% brightness in 0.4 seconds
*                 - Repeats this pattern indefinitely
*
* Timing:       Using HC12 with 24MHz bus clock
*              - Each CPU cycle = 1/24MHz = 41.67 nanoseconds
*              - Basic delay loop: 4 cycles per iteration
*                  (1 cycle for DEX, 3 cycles for BNE)
*              - Inner loop (Counter1 = $00FF = 255):
*                  255 iterations * 4 cycles = 1,020 cycles
*              - Outer loop (Counter2 = $01E0 = 480):
*                  480 iterations * 1,020 cycles = 489,600 cycles
*              - Total time per step:
*                  489,600 cycles * 41.67ns = 20.4ms
*              - Using 20 steps for 0.4 second fade:
*                  20.4ms * 20 steps = 0.408 seconds
*
* Register use: A: LED control and port operations
*               B: Loop counting for fade steps
*               X,Y: Delay loop counters
*
* Memory use:   RAM Locations from $3000 for data
*               RAM Locations from $3100 for program
************************************************************************

* Parameter Declaration Section
* Export Symbols
            XDEF        pstart      ; export 'pstart' symbol
            ABSENTRY    pstart      ; for assembly entry point

* Symbols and Macros
PORTA       EQU     $0000          ; i/o port A addresses
DDRA        EQU     $0002
PORTB       EQU     $0001          ; i/o port B addresses
DDRB        EQU     $0003

************************************************************************
* Data Section: address used [ $3000 to $3FFF ] RAM memory
*
            ORG     $3000          ; Reserved RAM memory starting address
Counter1    DC.W    $00FF          ; Inner loop count (255) for timing
Counter2    DC.W    $01E0          ; Outer loop count (480) for timing
StepCount   DC.B    20             ; Number of steps for 0.4 sec fade

************************************************************************
* Program Section: address used [ $3100 to $3FFF ] RAM memory
*
            ORG     $3100          ; Program start address, in RAM
pstart      LDS     #$3100         ; initialize the stack pointer

            ; Initialize ports
            LDAA    #%11110000     ; LED pin outputs (4-7)
            STAA    DDRB
            
            ; Set initial LED states
            LDAA    #%01010000     ; LED 1 & 3 ON, LED 2 OFF
            STAA    PORTB

mainLoop    
            JSR     dimUp          ; Fade LED 4 up (0.4 seconds)
            JSR     dimDown        ; Fade LED 4 down (0.4 seconds)
            BRA     mainLoop       ; Repeat

************************************************************************
* Subroutine Section
************************************************************************

************************************************************************
* dimUp - (Overview) Fades LED 4 from 0% to 100% over 0.4 seconds
* Uses A for LED control, B for step counting
* Preserves other registers
************************************************************************
dimUp       PSHA
            PSHB
            PSHX
            PSHY
            
            LDAB    StepCount      ; Load number of steps
fadeUpLoop  
            ; Turn on LED 4
            LDAA    PORTB
            ORAA    #%10000000     ; Set bit 7
            STAA    PORTB
            
            JSR     delayLoop      ; Delay for ON time
            
            ; Turn off LED 4
            LDAA    PORTB
            ANDA    #%01111111     ; Clear bit 7
            STAA    PORTB
            
            JSR     delayLoop      ; Delay for OFF time
            
            DECB                   ; Next step
            BNE     fadeUpLoop     ; Continue until all steps done
            
            PULY
            PULX
            PULB
            PULA
            RTS

************************************************************************
* dimDown -  (Overview) Fades LED 4 from 100% to 0% over 0.4 seconds
* Uses accumulator A for LED control, accumulator B for step counting
* Keep other registers
************************************************************************
dimDown     PSHA
            PSHB
            PSHX
            PSHY
            
            LDAB    StepCount      ; Load number of steps
fadeDnLoop  
            ; Turn on LED 4
            LDAA    PORTB
            ORAA    #%10000000     ; Set bit 7
            STAA    PORTB
            
            JSR     delayLoop      ; Delay for ON time
            
            ; Turn off LED 4
            LDAA    PORTB
            ANDA    #%01111111     ; Clear bit 7
            STAA    PORTB
            
            JSR     delayLoop      ; Delay for OFF time
            
            DECB                   ; Next step
            BNE     fadeDnLoop     ; Continue until all steps done
            
            PULY
            PULX
            PULB
            PULA
            RTS

************************************************************************
* delayLoop - (Overview) Provides base delay unit for LED dimming
* 
* Timing calculation:
* - 24MHz bus clock = 41.67ns per cycle
* - Inner loop (DEX + BNE) = 4 cycles
* - Counter1 = $00FF (255 decimal):
*   255 iterations * 4 cycles = 1,020 cycles
* - Counter2 = $01E0 (480 decimal):
*   480 iterations * 1,020 cycles = 489,600 cycles total
* - Total time: 489,600 * 41.67ns = 20.4ms per step
* 
* Use X,Y registers for counting
* Keep other registers
************************************************************************
delayLoop   PSHX
            PSHY
            
            LDY     Counter2       ; Load outer loop counter
dly1Loop    LDX     Counter1       ; Load inner loop counter
dlymsLoop   DEX                    ; Decrement inner counter
            BNE     dlymsLoop      ; If not zero, keep counting
            
            DEY                    ; Decrement outer counter
            BNE     dly1Loop       ; If not zero, keep counting
            
            PULY
            PULX
            RTS

            END