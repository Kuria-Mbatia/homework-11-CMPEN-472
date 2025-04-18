************************************************
* Title: StarFill (in Memory lane)
*
* Objective: CSE472 Homework 1 in-class-room demonstration
*           program
*
* Revision:  V1.0
*
* Date:      Jan 15, 2025
*
* Programmer: Kuria Mbatia
*
* Company: The Pennsylvania State University
* Electrical Engineering and Computer Science
*
* Algorithm: Simple while-loop demo of HCS12 assembly program
*
* Register use: A accumulator: character data to be filled
*              B accumulator: counter, number of filled locations
*              X register:    memory address pointer
*
* Memory use: RAM Locations from $3000 to $30E0
*
* Input: Parameters hard coded in the program
*
* Output: Data filled in memory locations,
* from $3000 to $3009 changed
*
* Observation: This program is designed for instruction purpose.
* This program can be used as a 'loop' template
*
* Note: This is a good example of program comments
* All Homework programs MUST have comments similar
* to this Homework 1 program. So, please use this
* comment format for all your subsequent CMPEN 472
* Homework programs.
*
* Adding more explanations and comments help you and
* others to understand your program later.
*
* Comments: This program is developed and simulated using CodeWorrior
* development software.
*
************************************************
* Parameter Declearation Section
*
* Export Symbols
        XDEF    pgstart ; export 'pgstart' symbol
        ABSENTRY pgstart ; for assembly entry point
* Symbols and Macros
PORTA   EQU     $0000   ; i/o port addresses
PORTB   EQU     $0001
DDRA    EQU     $0002
DDRB    EQU     $0003
************************************************
* Data Section
*
        ORG     $3000   ;reserved memory starting address
here    DS.B    $E1     ;225 memory locations reserved
count   DC.B    $E1     ;constant, star count = 225
*
************************************************
* Program Section
*
        ORG     $3100   ;Program start address, in RAM
pgstart ldaa    #$2A    ;load '*' into accumulator A
        ldab    #$E1    ;load star counter into B
        ldx     #$3000  ;load address pointer into X
loop    staa    0,x     ;put a star
        inx             ;point to next location
        decb            ;decrease counter
        bne     loop    ;if not done, repeat
done    bra     done    ;task finished,
                       ; do nothing
*
* Add any subroutines here
*
        END             ;last line of a file