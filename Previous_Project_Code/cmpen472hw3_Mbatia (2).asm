************************************************************************
* Title:        LED PWM Control Implementation
*
* Objective:    CMPEN 472 Homework 3 implementation
*              LED dimming using PWM technique
*
* Revision:     V1.0
*
* Date:         February 5, 2025
*
* Programmer:   Kuria Mbatia
*
* Company:      The Pennsylvania State University
*              Department of Computer Science and Engineering
*
* Program:      LED PWM Control Demo using 10µsec timing
*              - LED 1 ON (100%)
*              - LED 2 OFF (0%)
*              - LED 3 ON (100%)
*              - LED 4 PWM controlled:
*                  SW1 not pressed: 5% duty cycle (0.05ms on, 0.95ms off)
*                  SW1 pressed: 25% duty cycle (0.25ms on, 0.75ms off)
*
* Algorithm:    Simple Parallel I/O use with PWM timing control
*
* Register use: A: LED Light on/off state and Switch on/off state
*              X,Y: PWM loop counters
*
* Memory use:   RAM Locations from $3000 for data,
*              RAM Locations from $3100 for program
************************************************************************

* Parameter Declaration Section
* Export Symbols
            XDEF             pstart  ; export 'pstart' symbol
            ABSENTRY         pstart  ; for assembly entry point

* Symbols and Macros
PORTA       EQU     $0000   ; i/o port A addresses
DDRA        EQU     $0002
PORTB       EQU     $0001   ; i/o port B addresses
DDRB        EQU     $0003

************************************************************************
* Data Section: address used [ $3000 to $3FFF ] RAM memory
*
            ORG     $3000   ; Reserved RAM memory starting address
                           ; for Data for CMPEN 472 class
ON_COUNT    DC.B    5      ; 5% duty cycle counter when SW1 not pressed
OFF_COUNT   DC.B    95     ; 95% off time counter when SW1 not pressed
ON_COUNT_P  DC.B    25     ; 25% duty cycle counter when SW1 pressed
OFF_COUNT_P DC.B    75     ; 75% off time counter when SW1 pressed

************************************************************************
* Program Section: address used [ $3100 to $3FFF ] RAM memory
*
            ORG     $3100   ; Program start address, in RAM
pstart      LDS     #$3100  ; initialize the stack pointer

            ; Initialize ports
            LDAA    #%11110001 ; Set LED pins as outputs (4-7) and SW1 pin
            STAA    DDRB
            
            ; Initial LED states
            LDAA    #%01010000 ; LED 1 & 3 ON, LED 2 OFF (bits 4,5,6)
            STAA    PORTB
            

mainLoop    
            ; Check SW1 state (bit 0)
            ;BCLR    PORTB, #%01010000
            ;DO not set the BCLR as it clears every LED state & doesn't maintain anything
            LDAA    PORTB
            ANDA    #%00000001
            BNE     pwm_25   ; If pressed (1), do 25% duty cycle
            ;CHeck sw1 at end, but can be added anywhere... we then go to pwm_5 by default
            
            ; 5% duty cycle (SW1 not pressed)
pwm_5       LDAA    #%10000000  ; Turn on LED 4
            ORAA    PORTB
            STAA    PORTB
            
            LDAB    ON_COUNT    ; Load 5 for ON time
            JSR     delayN10us  ; Delay 5 * 10us = 50us
            
            LDAA    #%01111111  ; Turn off LED 4
            ANDA    PORTB
            STAA    PORTB
            
            LDAB    OFF_COUNT   ; Load 95 for OFF time
            JSR     delayN10us  ; Delay 95 * 10us = 950us
            
            BRA     mainLoop    ; cont cycle (i.e. doens't end)

            ; 25% duty cycle (SW1 pressed)
pwm_25      LDAA    #%10000000  ; Turn on LED 4
            ORAA    PORTB
            STAA    PORTB
            
            LDAB    ON_COUNT_P  ; Load 25 for ON time
            JSR     delayN10us  ; Delay 25 * 10us = 250us
            
            LDAA    #%01111111  ; Turn off LED 4
            ANDA    PORTB
            STAA    PORTB
            
            LDAB    OFF_COUNT_P ; Load 75 for OFF time
            JSR     delayN10us  ; Delay 75 * 10us = 750us
            
            BRA     mainLoop    ;GO back

************************************************************************
* Subroutine Section
*
* delayN10us - Delays N*10 microseconds, where N is in accumulator B
* Uses 24MHz bus clock
*
* Bus clock is 24MHz = 24 cycles per microsecond
* Need 240 cycles for 10us --> From in class
* Each loop takes 4 cycles (1 for DEX, 3 for BNE)
* So need 60 iterations to get 240 cycles (60 * 4 = 240)
*
************************************************************************
delayN10us  
            PSHX             ; Save X
delay10Loop LDX     #60     ; 10us = 240 cycles (24MHz clock), rem static to an extent
delay1      DEX             ; 1 cycle
            BNE     delay1  ; 3 cycles
            DECB            ; Decrement counter
            BNE     delay10Loop
            PULX            ; Restore X
            RTS

            END