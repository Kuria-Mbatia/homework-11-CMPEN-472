****************************************************************************************
*
* Title:          LED Light Blinking
*
* Objective       CMPEN 472 Homwork 2 in-classroom demonstration
*                 program 
*
* Revision:       V1.0 for CodeWarrior 5.2 Debugger Simulation
*
* Date:           Jan 29, 2025
*
* Programmer:     Kuria Mbatia
*
* Company:        Pennsylvania State University
* 
* Algorithm:      Alternates LEDs 1 and 4 when SW1 is not pressed. Cycles LEDs 4->3->2->1
*                 when SW1 is pressed.All LEDs are turned off during mode transitions
*                 *PRESS THE LAST SWITCH (CLOSEST TO THE RIGHT SIDE) TO ALTERNATE BETWEEN MODES
*               
*
* Register use:   A: LED Light on/off state and Switch 1 on/off state
*                 X,Y: Delay loop-counters
*
* Memory Use:     RAM Locations from $3000 for data,
*                 RAM Locations from $3100 for program
*
* Input:          Parameters hard-coded in the program - PORTB
*                 Switch 1 at PORTB bit 0
*                 Switch 2 at PORTB bit 1
*                 Switch 3 at PORTB bit 2
*                 Switch 4 at PORTB bit 3
*
*
* Output:         LED 1 at PORTB bit 4
*                 LED 2 at PORTB bit 5
*                 LED 3 at PORTB bit 6
*                 LED 4 at PORTB bit 7
*
*
* Observation:    When SW1 is pressed, the program enters sequential mode, cycling through
*                 LEDs 4->3->2->1. When SW1 is released, the program immediately exits sequential
*                 mode, turns off all LEDs, & alternates LEDs 1 and 4. .
*
* Note:           All LEDs are turned off coherently during mode transitions to prevent
*                 unintended behavior. The program checks SW1 status after each step in
*                 sequential mode to allow immediate exit if SW1 is released.
*
*
*                 All homework problems must have comments similar to this Homework 2 
*                 program. So, please use this comment formatting for all of your
*                 subsequent CMPEN472 Homework programs.
*
*                 Adding more explanations and comments help you and others to understand
*                 your program later!
*
*
* Comments:       This program is developed and simulated using the CodeWarrior development
*                 software and is targeted for Axiom Manufacturing's CSM-12C128 board running
*                 at 24Mhz.
*
*
*
****************************************************************************************
* Parameter Decleration Section
*
* Export Symbols
            XDEF        pstart  ; export 'pstart' symbol
            ABSENTRY    pstart  ; for assembly entry point
            
* Symbols and Macros
PORTA     EQU           $0000   ; I/O port A Addresses
DDRA      EQU           $0002
PORTB     EQU           $0001   ; I/O port B addresses
DDRB      EQU           $0003   
****************************************************************************************
* Data Section: addresses used [ $3000 to $30FF ] RAM Memory
*
            ORG           $3000         ; Reserved RAM memory starting address
                                        ; for Data in the CMPEN 472 class
Counter1    DC.W          $0100         ; X register counter number for the time delay
                                        ; inner loop for msec
Counter2    DC.W          $00BF         ; Y register counter number for the time delay
                                        ; outer loop for msec 
                                        
                                        ; Remaining data memory space for the stack,
                                        ; up to the program memory start                                      

****************************************************************************************
* Program Section: addresses used [ $3000 to $3FFF ] RAM Memory
*
            ORG       $3100            ; Program start address, in RAM
pstart      LDS       #$3100           ; initialize the stack pointer
             
 ;why this is sectioned off?
 ;LDA        #%11110000                 ; LED 1,2,3,4 at PORTB bit 4,5,6,7 CSM-12C128 Board
            LDAA       #%11111111       ; LED 1,2,3,4 AT PORTB bit 4,5,6,7 for simulation only
            STAA       DDRB             ; set PORTB bit 4,5,6,7 as output
            
            ;LDAA       #%00000000       
            ;STAA       PORTB           ; Turn off LED 1,2,3,4 (all bits in PORTB)
            CLR         PORTB           ; Turn off all LEDS Intitially
                                        ; for smulation only
mainLoop 
            ;Regular mode to alternate LED 4 & LED 1 off & on
            LDAA        PORTB
            ANDA        #%00000001
            BNE         sw1pressed      ; If switch pressed go to sequential 
           
            BSET       PORTB,%10000000  ; Turn on LED 4 at PORTB bit 7
            BCLR       PORTB,%00010000  ; Turn off LED 1 at PORTB bit 4
            JSR        delay1sec        ; Wait for 1 second
            
            BCLR       PORTB,%10000000  ; Turn off LED 4 at PORTB bit 7
            BSET       PORTB,%00010000  ; Turn on LED 1 at PORTB bit 4
            JSR        delay1sec        ; Wait for 1 second
            
            BRA         mainLoop

sw1pressed:
            ;Sequential mode: Cycle LEDs 4->3->2->1
            BSET        PORTB,%10000000  ; Turn on LED 4 at PORTB bit 7
            BCLR        PORTB,%01110000  ; Turn off all other LED's
            JSR         delay1sec
            JSR         checkSW1Released ; Check if SW1 released mid-sequence
            
            BSET        PORTB, %01000000 ; LED3 on at PORTB bit 6
            BCLR        PORTB, %10110000 ; Turn off others
            JSR         delay1sec
            JSR         checkSW1Released ; Check if SW1 released mid-sequence

            BSET        PORTB, %00100000 ; LED2 on at PORTB bit 5
            BCLR        PORTB, %11010000 ; Turn off others
            JSR         delay1sec
            JSR         checkSW1Released ; Check if SW1 released mid-sequence

            BSET        PORTB, %00010000 ; LED1 on at PORTB bit 4
            BCLR        PORTB, %11100000 ; Turn off others
            JSR         delay1sec
            JSR         checkSW1Released ; Final check

            BRA         sw1pressed ; Repeat sequence while SW1 held

****************************************************************************************
* Unused portion's from the original code, this can be ignored        
;sw1notpsh   BCLR       PORTB,%00000001  ; turn off LED 1 at PORTB bit 4
            ;BRA        mainLoop
                     
;sw1pushed   BSET       PORTB,%00010000  ; turn on LED 1 at PORTB bit 4
            ;BRA        mainLoop
****************************************************************************************
checkSW1Released:
            LDAA        PORTB            ; Check SW1 status
            STAA        PORTB            ; Turn off LED 1,2,3,4 (all bits in PORTB)
            BCLR        PORTB, %11110000 ; Clear LED ports, to double check
            ANDA        #%00000001
            BEQ         exitSequence     ;If released, return to main loop
            RTS

exitSequence:
            PULY                   ; Clean up return address from JSR
            BRA         mainLoop   ; Exit to alternate blinking
****************************************************************************************
* Subroutine Section: addresses used [ $3000 to $3FFF ] RAM Memory
*

;**************************************************************
; delay1sec subroutine
;
; Please be sure to include your comments here!
;
delay1sec
           PSHY                         ; Save Y
           LDY        Counter2          ; long delay...
           
dly1Loop   JSR        delayMS           ; Total time delay = ( Y * delayMS)  
           DEY
           BNE        dly1Loop
           
           PULY                         ; restore Y
           RTS                          ; Return

;**************************************************************
; delayMS subroutine  
;
; This subroutine causes a few MSEC in delay
; 
; Input: a 16bit count number in 'Counter1'
; Output: Time delay, it is just a CPU Cycle wasted
; Registers in use: X register, as counter
; Memory locations in use: a 16bit input number at 'Counter1'
;
; Comments: one can add more NOP instructions to longthen the delay time
;

delayMS   PSHX                          ; Save X
          LDX         Counter1          ; Short delay
          
dlyMSLoop NOP                           ; total time delay = ( X * NOP )
          DEX
          BNE         dlyMSLoop
          
          PULX                          ; Restore X
          RTS                           ; return
          
                          
*
* Add any subroutines here
*
          end                           ; Last line of the file


