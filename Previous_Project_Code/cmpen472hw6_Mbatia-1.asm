***********************************************************************
*
* Title:          Simple Memory Access Program
* 
* Objective:      CMPEN 472 Homework 6
*
* Revision:       V1.7
*
* Date:           Feb. 28, 2025
*
* Programmer:     Kuria Mbatia
*
* Company:        The Pennsylvania State University
*
* Algorithm:      Simple SCI Serial I/O and Memory Access
*
* Register use:   A: Command processing, temp calculations
*                 B: Bit manipulation, counters
*                 X,Y: Pointers and memory access
*                 Z: Not used
*
* Memory use:     $3000-$30FF: Variables and data
*                 $3100-$xxxx: Program
*
* Input:          Terminal input via SCI port
*
* Output:         Terminal output via SCI port
*
* Observation:    This is a command-line memory access program that allows
*                 users to view and modify memory contents.
*
* Commands:       S$xxxx - Show the contents of memory location in word
*                 W$xxxx yyyy - Write data word to memory location
*                 QUIT - Quit program, run 'Type writer' program
*
***********************************************************************
* Parameter Declaration Section
*
* Export Symbols
            XDEF        pstart      ; Program entry point
            ABSENTRY    pstart      ; For absolute assembly

* Symbols and Macros
PORTB       EQU         $0001       ; Port B data register
DDRB        EQU         $0003       ; Port B data direction register

SCIBDH      EQU         $00C8       ; SCI Baud Register High
SCIBDL      EQU         $00C9       ; SCI Baud Register Low
SCICR2      EQU         $00CB       ; SCI Control Register 2
SCISR1      EQU         $00CC       ; SCI Status Register 1
SCIDRL      EQU         $00CF       ; SCI Data Register Low

CR          EQU         $0D         ; ASCII carriage return
LF          EQU         $0A         ; ASCII line feed
SPACE       EQU         $20         ; ASCII space
NULL        EQU         $00         ; ASCII null
DOLLAR      EQU         $24         ; ASCII $ character

; Define safe memory range for the program
SAFE_MEM_START EQU     $0000       ; Start of safe memory area (allow any address)
SAFE_MEM_END   EQU     $FFFF       ; End of safe memory area (allow any address)

MAX_CMD_LEN EQU         16          ; Maximum command length

***********************************************************************
* Data Section - Variables and Strings
***********************************************************************
            ORG         $3000       ; Start of data section

cmdBuffer   DS.B        MAX_CMD_LEN ; Command input buffer
cmdLength   DS.B        1           ; Length of command
address     DS.W        1           ; Memory address for commands
dataValue   DS.W        1           ; Data value for W command
tempByte    DS.B        1           ; Temporary storage
isHexData   DS.B        1           ; Flag for hex/decimal data format
decBuffer   DS.B        6           ; Buffer for decimal conversion
hexValid    DS.B        1           ; Flag to track if all chars are valid hex
digCount    DS.B        1           ; Digit counter for parsing
tempWord    DS.W        1           ; Temporary word storage
debugFlag   DS.B        1           ; Flag for debugging

***********************************************************************
* Program Section
***********************************************************************
            ORG         $3100       ; Start of program section

; Program constants (all message strings in program section to save data space)
msgPrompt   DC.B        '>', NULL
msgLF       DC.B        CR, LF, NULL
welcome1    DC.B        'Welcome to the Simple Memory Access Program!', CR, LF, NULL
welcome2    DC.B        'Enter one of the following commands (examples shown below)', CR, LF, NULL
welcome3    DC.B        'and hit ', $27, 'Enter', $27, '.', CR, LF, CR, LF, NULL
example1    DC.B        '>S$3000                  ;to see the memory content at $3000 and $3001', CR, LF, NULL
example2    DC.B        '>W$3003 $126A            ;to write $126A to memory locations $3003 and $3004', CR, LF, NULL
example3    DC.B        '>W$3003 4714             ;to write $126A to memory location $3003 and $3004', CR, LF, NULL
example4    DC.B        '>QUIT                    ;quit the Simple Memory Access Program', CR, LF, NULL
msgInvCmd   DC.B        'Invalid command. Use one of the following:', CR, LF
            DC.B        ' S$xxxx   - Show memory contents at address xxxx', CR, LF
            DC.B        ' W$xxxx v - Write value v to address xxxx (v can be decimal or $hex)', CR, LF
            DC.B        ' QUIT     - Exit to typewriter mode', CR, LF, NULL
msgInvAddr  DC.B        'invalid input, address', CR, LF, NULL
msgInvData  DC.B        'invalid input, data', CR, LF, NULL
msgQuit     DC.B        'Type-writing now, hit any keys:', CR, LF, NULL
spaceArrow  DC.B        ' => ', NULL

pstart      LDS         #$4000      ; Initialize stack pointer to the end of memory

            ; Initialize hardware
            LDAA        #%11111111  ; Set PORTB as output
            STAA        DDRB
            CLR         PORTB       ; Clear all outputs

            ; Initialize serial port - FIXED VALUES FOR 9600 BAUD AT 24MHZ
            CLR         SCIBDH      ; Set baud rate high byte to 0
            LDAA        #$9C        ; Low byte value for 9600 baud at 24MHz (156)
            STAA        SCIBDL      ; 24MHz/(16*156) = 9615 baud (close to 9600)
            LDAA        #$0C        ; Enable SCI transmitter and receiver
            STAA        SCICR2

            ; Clear all variables to make sure we start clean
            LDX         #cmdBuffer
            LDY         #debugFlag  ; End of variables
            
clearVars   CLR         0,X         ; Clear this variable
            INX                     ; Next variable
            CPX         Y           ; Reached the end?
            BLS         clearVars   ; If not, continue clearing
            
            ; Show welcome message and instructions
            LDX         #welcome1
            JSR         printmsg
            LDX         #welcome2
            JSR         printmsg
            LDX         #welcome3
            JSR         printmsg
            
            ; Show example commands
            LDX         #example1
            JSR         printmsg
            LDX         #example2
            JSR         printmsg
            LDX         #example3
            JSR         printmsg
            LDX         #example4
            JSR         printmsg

mainLoop    LDX         #msgPrompt  ; Show prompt
            JSR         printmsg
            
            JSR         getCommand  ; Get command from user
            TST         cmdLength   ; Check if command received
            BEQ         mainLoop    ; If empty command, restart
            
            JSR         processCmd  ; Process the command
            
            BRA         mainLoop    ; Return to main loop

***********************************************************************
* getCommand: Get command from user via serial input
*             Stores command in cmdBuffer and length in cmdLength
* Input:      None
* Output:     cmdBuffer, cmdLength
* Registers:  A, B, X, Y all modified
***********************************************************************
getCommand  CLR         cmdLength   ; Reset command length
            
            ; Clear the entire command buffer first for safety
            LDX         #cmdBuffer
            LDY         #MAX_CMD_LEN
gcClearLoop CLR         0,X         ; Clear this byte
            INX                     ; Next byte
            DEY                     ; Decrement counter
            BNE         gcClearLoop ; If not done, continue
            
            ; Now get the command
            LDY         #cmdBuffer  ; Reset to start of buffer
            
gcLoop      JSR         getchar     ; Get a character
            CMPA        #CR         ; Check for Enter key
            BEQ         gcDone      ; If so, done
            
            ; Check maximum command length
            LDAB        cmdLength
            CMPB        #MAX_CMD_LEN-1  ; Ensure space for null
            BHS         gcLoop      ; Ignore if too long
            
            JSR         putchar     ; Echo character
            STAA        0,Y         ; Store in buffer
            INY                     ; Next buffer position
            INC         cmdLength   ; Count the character
            BRA         gcLoop      ; Get next character
            
gcDone      CLR         0,Y         ; Null-terminate buffer
            
            ; Print newline
            LDX         #msgLF
            JSR         printmsg
            
            RTS

***********************************************************************
* processCmd: Process the command in cmdBuffer
* Input:      cmdBuffer, cmdLength
* Output:     None
* Registers:  All modified
***********************************************************************
processCmd  LDX         #cmdBuffer  ; Point to command

            ; Check command length first
            LDAA        cmdLength
            CMPA        #1         ; At least 1 character needed
            BLO         invalidCmd
            
            ; Check first character - should be S, W, or Q (case insensitive)
            LDAA        0,X         ; Get first character
            
            ; Convert to uppercase for case-insensitive comparison
            CMPA        #'a'        ; Check if lowercase
            BLO         pcNotLower
            CMPA        #'z'
            BHI         pcNotLower
            SUBA        #$20        ; Convert to uppercase (a-z to A-Z)
            STAA        0,X         ; Store back to command buffer
            
pcNotLower  ; Now it's uppercase if it was lowercase
            CMPA        #'S'        ; Is it S command?
            BEQ         procShowCmd
            
            CMPA        #'W'        ; Is it W command?
            BEQ         procWriteCmd
            
            CMPA        #'Q'        ; Is it Q?
            BNE         invalidCmd  ; If not S, W, or Q, invalid command
            
            ; Check if command is "QUIT"
            LDAB        cmdLength
            CMPB        #4          ; Must be exactly 4 chars for QUIT
            BNE         invalidCmd
            
            LDAA        1,X         ; Second character
            CMPA        #'U'
            BNE         invalidCmd
            LDAA        2,X         ; Third character
            CMPA        #'I'
            BNE         invalidCmd
            LDAA        3,X         ; Fourth character
            CMPA        #'T'
            BNE         invalidCmd
            
doQuit      ; QUIT command - go to typewriter mode
            LDX         #msgQuit
            JSR         printmsg
            JSR         typewriter
            RTS

invalidCmd  LDX         #msgInvCmd   ; Invalid command message
            JSR         printmsg
            RTS

procShowCmd ; Process S command - format should be S$xxxx
            ; Check for minimum command length - need at least "S$X"
            LDAA        cmdLength
            CMPA        #3
            BLO         invalidCmd
            
            LDAA        1,X         ; Second character should be $
            CMPA        #DOLLAR
            BNE         invalidCmd
            
            ; Parse memory address
            LEAY        2,X         ; Skip S$
            STY         tempByte    ; Store pointer position
            JSR         parseHexValue
            BCC         invalidAddr ; If carry clear, invalid address
            
            ; Address is now in D
            STD         address     ; Store parsed address
            
            ; Execute show memory command
            JSR         showMemory
            RTS

invalidAddr LDX         #msgInvAddr  ; Invalid address message
            JSR         printmsg
            RTS

procWriteCmd ; Process W command - format should be W$xxxx data
            ; Check for minimum command length - need at least "W$X Y"
            LDAA        cmdLength
            CMPA        #5
            BLO         invalidCmd
            
            LDAA        1,X         ; Second character should be $
            CMPA        #DOLLAR
            BNE         invalidCmd
            
            ; Parse memory address
            LEAY        2,X         ; Skip W$
            STY         tempByte    ; Store pointer position
            JSR         parseHexValue
            BCC         invalidAddr ; If carry clear, invalid address
            
            ; Address is now in D
            STD         address     ; Store parsed address
            
            ; Now find the space after the address
            LDY         tempByte    ; Get current position
            
findSpace   LDAA        0,Y         ; Get character
            CMPA        #NULL       ; End of string?
            BEQ         invalidData ; No data provided
            CMPA        #SPACE      ; Space?
            BEQ         foundSpace  ; Yes, found it
            INY                     ; Next character
            BRA         findSpace
            
foundSpace  ; Found space, now skip any additional spaces
skipSpaces  INY                     ; Skip this space
            LDAA        0,Y         ; Get next character
            CMPA        #SPACE      ; Another space?
            BEQ         skipSpaces  ; Yes, skip it
            CMPA        #NULL       ; End of string?
            BEQ         invalidData ; No data provided
            
            ; Now check if data starts with $ (hex)
            CMPA        #DOLLAR
            BEQ         parseHexData
            
            ; Parse as decimal
            STY         tempByte    ; Store pointer position
            JSR         parseDecValue
            BCC         invalidData ; If carry clear, invalid data
            
            STD         dataValue   ; Store parsed data
            
            ; Verify we reached end of command or space
            LDY         tempByte    ; Get current position after parsing
            LDAA        0,Y
            CMPA        #NULL       ; End of string?
            BEQ         execWrite   ; Ok
            CMPA        #SPACE      ; Space?
            BEQ         execWrite   ; Ok
            BRA         invalidData ; Extra characters after value
            
parseHexData
            ; Skip $ and parse hex value
            INY                     ; Skip $
            STY         tempByte    ; Store pointer position
            JSR         parseHexValue
            BCC         invalidData ; If carry clear, invalid data
            
            STD         dataValue   ; Store parsed data
            
            ; Verify we reached end of command or space
            LDY         tempByte    ; Get current position after parsing
            LDAA        0,Y
            CMPA        #NULL       ; End of string?
            BEQ         execWrite   ; Ok
            CMPA        #SPACE      ; Space?
            BEQ         execWrite   ; Ok
            BRA         invalidData ; Extra characters after value
            
execWrite   ; Execute write memory command
            JSR         writeMemory
            RTS

invalidData LDX         #msgInvData  ; Invalid data message
            JSR         printmsg
            RTS

***********************************************************************
* parseHexValue: Parse a hex number from address in tempByte
* Input:      tempByte - Address of string to parse
* Output:     D - Parsed hex value
*             tempByte - Updated to point after parsed value
*             Carry flag - set if valid, clear if invalid
* Registers:  A, B, X, Y modified
***********************************************************************
parseHexValue
            ; Clear result values
            CLR         digCount    ; Reset digit counter
            CLRA                    ; Clear A
            CLRB                    ; Clear B
            STD         tempWord    ; Store initial value = 0
            
            ; First check if we have valid hex digits
            LDY         tempByte    ; Get starting position
            
phvCheck    LDAA        0,Y         ; Get character
            CMPA        #NULL       ; End of string?
            BEQ         phvCheckDone
            CMPA        #SPACE      ; Space?
            BEQ         phvCheckDone
            
            ; Check if valid hex digit
            JSR         isHexDigit
            BCC         phvError    ; Invalid character
            
            INY                     ; Next character
            INC         digCount    ; Count this digit
            
            ; Make sure we don't have too many digits (max 4 for 16-bit value)
            LDAB        digCount
            CMPB        #5
            BHS         phvError    ; Too many digits
            
            BRA         phvCheck    ; Continue checking
            
phvCheckDone
            ; If no digits, error
            LDAA        digCount
            BEQ         phvError    ; No digits parsed
            
            ; Valid digits, now convert to value
            ; Reset for actual parsing
            CLR         digCount    ; Reset digit counter
            LDY         tempByte    ; Reset to start position
            
            ; Clear result
            CLRA                    ; Clear A
            CLRB                    ; Clear B
            STD         tempWord    ; Make sure tempWord is cleared
            
; Main conversion loop            
phvLoop     LDAA        0,Y         ; Get character
            CMPA        #NULL       ; End of string?
            BEQ         phvDone
            CMPA        #SPACE      ; Space?
            BEQ         phvDone
            
            ; Get the current accumulated value
            LDD         tempWord
            
            ; Multiply current result by 16
            ; D = D * 16
            LSLD                    ; D * 2
            LSLD                    ; D * 4
            LSLD                    ; D * 8
            LSLD                    ; D * 16
            
            ; Save the shifted value
            STD         tempWord
            
            ; Convert current digit to value
            LDAB        0,Y         ; Get digit
            
            ; Handle 0-9
            CMPB        #'9'
            BHI         phvAlpha    ; It's A-F or a-f
            
            SUBB        #'0'        ; Convert 0-9 to value
            BRA         phvAddDigit
            
phvAlpha    ; Handle A-F and a-f
            CMPB        #'F'
            BHI         phvLower    ; It's a-f
            
            ; A-F
            SUBB        #'A'        ; Subtract 'A'
            ADDB        #$0A        ; Add 10 (A=10, B=11, etc.)
            BRA         phvAddDigit
            
phvLower    ; a-f
            SUBB        #'a'        ; Subtract 'a'
            ADDB        #$0A        ; Add 10 (a=10, b=11, etc.)
            
phvAddDigit ; Add current digit value to result
            CLRA                    ; Clear A (high byte)
            ADDD        tempWord    ; Add digit to shifted value
            STD         tempWord    ; Save result
            
            INY                     ; Next character
            INC         digCount    ; Count this digit
            
            ; Check if we have enough digits
            LDAA        digCount
            CMPA        #5          ; Max 4 hex digits (16-bit value)
            BHS         phvDone     ; Done if we have 4 digits
            
            BRA         phvLoop     ; Process next digit
            
phvDone     ; Success - return result in D
            STY         tempByte    ; Update position pointer
            LDD         tempWord    ; Get final result
            
            SEC                     ; Set carry to indicate success
            RTS
            
phvError    ; Error - invalid hex number
            CLRA                    ; Clear high byte
            CLRB                    ; Clear low byte
            CLC                     ; Clear carry to indicate error
            RTS

***********************************************************************
* parseDecValue: Parse a decimal number from address in tempByte
* Input:      tempByte - Address of string to parse
* Output:     D - Parsed decimal value
*             tempByte - Updated to point after parsed value
*             Carry flag - set if valid, clear if invalid
* Registers:  A, B, X, Y modified
***********************************************************************
parseDecValue
            ; Clear result values
            CLR         digCount    ; Reset digit counter
            CLRA                    ; Clear A
            CLRB                    ; Clear B
            STD         tempWord    ; Store initial value = 0
            
            ; First check if we have valid decimal digits
            LDY         tempByte    ; Get starting position
            
pdvCheck    LDAA        0,Y         ; Get character
            CMPA        #NULL       ; End of string?
            BEQ         pdvCheckDone
            CMPA        #SPACE      ; Space?
            BEQ         pdvCheckDone
            
            ; Check if valid decimal digit
            JSR         isDecDigit
            BCC         pdvError    ; Invalid character
            
            INY                     ; Next character
            INC         digCount    ; Count this digit
            
            ; Make sure we don't have too many digits (max 5 for 16-bit value)
            LDAB        digCount
            CMPB        #6
            BHS         pdvError    ; Too many digits
            
            BRA         pdvCheck    ; Continue checking
            
pdvCheckDone
            ; If no digits, error
            LDAA        digCount
            BEQ         pdvError    ; No digits parsed
            
            ; Valid digits, now convert to value
            ; Reset for actual parsing
            CLR         digCount    ; Reset digit counter
            LDY         tempByte    ; Reset to start position
            
            ; Clear result
            CLRA                    ; Clear A
            CLRB                    ; Clear B
            STD         tempWord    ; Ensure tempWord is cleared
            
; Main conversion loop            
pdvLoop     LDAA        0,Y         ; Get character
            CMPA        #NULL       ; End of string?
            BEQ         pdvDone
            CMPA        #SPACE      ; Space?
            BEQ         pdvDone
            
            ; Multiply current result by 10
            ; D = D * 10
            
            ; Get current value
            LDD         tempWord
            
            ; Method: D*10 = (D*8) + (D*2)
            ; Save D for later
            STD         tempWord    ; Save original value
            
            ; Compute D*2
            LSLD                    ; D = D * 2
            
            ; Save D*2
            XGDX                    ; X = D*2, swap D and X
            
            ; Get original value again
            LDD         tempWord
            
            ; Compute D*8
            LSLD                    ; D = D * 2  (now D*2)
            LSLD                    ; D = D * 2  (now D*4)
            LSLD                    ; D = D * 2  (now D*8)
            
            ; Add D*2 to get D*10
            ADDD        2,SP+       ; D = D*8 + D*2 = D*10 (retrieve D*2 from stack)
            
            ; Save D*10
            STD         tempWord
            
            ; Get the current digit
            LDAA        0,Y         ; Get the digit character
            SUBA        #'0'        ; Convert ASCII to value (0-9)
            TAB                     ; Copy to B
            CLRA                    ; Clear A for 16-bit addition
            
            ; Add digit to result
            ADDD        tempWord    ; D = D*10 + digit
            STD         tempWord    ; Save result
            
            INY                     ; Next character
            INC         digCount    ; Count this digit
            
            ; Check if we're going to overflow a 16-bit value
            LDAA        digCount
            CMPA        #6          ; Max 5 decimal digits (65535 is highest 16-bit value)
            BHS         pdvError    ; Too many digits - would overflow
            
            BRA         pdvLoop     ; Continue with next digit
            
pdvDone     ; Success - return result in D
            STY         tempByte    ; Update position pointer
            LDD         tempWord    ; Get final result
            
            ; No need for additional checks - if the value fits in D register,
            ; it's automatically within the 0-65535 range
            
            SEC                     ; Set carry to indicate success
            RTS
            
pdvError    ; Error - invalid decimal number
            CLRA                    ; Clear A
            CLRB                    ; Clear B
            CLC                     ; Clear carry to indicate error
            RTS

***********************************************************************
* isHexDigit: Check if A contains a valid hex digit
* Input:      A - ASCII character to check
* Output:     Carry flag - set if valid hex digit, clear if not
* Registers:  A preserved
***********************************************************************
isHexDigit  PSHA                    ; Save A
            
            CMPA        #'0'
            BLO         notHexDigit
            CMPA        #'9'
            BLS         validHexDigit
            CMPA        #'A'
            BLO         notHexDigit
            CMPA        #'F'
            BLS         validHexDigit
            CMPA        #'a'
            BLO         notHexDigit
            CMPA        #'f'
            BLS         validHexDigit
            
notHexDigit CLC                     ; Clear carry - not a hex digit
            PULA                    ; Restore A
            RTS
            
validHexDigit
            SEC                     ; Set carry - valid hex digit
            PULA                    ; Restore A
            RTS

***********************************************************************
* isDecDigit: Check if A contains a valid decimal digit
* Input:      A - ASCII character to check
* Output:     Carry flag - set if valid decimal digit, clear if not
* Registers:  A preserved
***********************************************************************
isDecDigit  PSHA                    ; Save A
            
            CMPA        #'0'
            BLO         notDecDigit
            CMPA        #'9'
            BLS         validDecDigit
            
notDecDigit CLC                     ; Clear carry - not a decimal digit
            PULA                    ; Restore A
            RTS
            
validDecDigit
            SEC                     ; Set carry - valid decimal digit
            PULA                    ; Restore A
            RTS

***********************************************************************
* showMemory: Display memory contents for S command
* Input:      address - Memory address to display
* Output:     Terminal display
* Registers:  All modified
***********************************************************************
showMemory  
            ; Display memory at address in the format:
            ; $3000 => %0001001001101010 $126A 4714
            
            ; Print space at beginning of line for better alignment
            LDAA        #SPACE
            JSR         putchar
            
            ; Print the address with $ prefix
            LDAA        #DOLLAR
            JSR         putchar
            
            ; Print the address
            LDD         address      ; Get the address to display
            JSR         printWordHex ; Print address in hex
            
            ; Print " => "
            LDX         #spaceArrow
            JSR         printmsg
            
            ; Read memory from the address - fail
            LDX         address      ; Load X with the address pointer
            LDAA        0,X          ; Read high byte from memory
            LDAB        1,X          ; Read low byte from memory
            STD         dataValue    ; Store the memory content
            
            ; Print binary format with % prefix
            LDAA        #'%'
            JSR         putchar
            
            ; Print high byte in binary
            LDAA        dataValue    ; Get high byte
            JSR         printByteBin
            
            ; Print low byte in binary
            LDAA        dataValue+1  ; Get low byte
            JSR         printByteBin
            
            ; Print spaces (exactly 4 spaces)
            LDAA        #SPACE
            JSR         putchar
            JSR         putchar
            JSR         putchar
            JSR         putchar
            
            ; Print hex format with $ prefix
            LDAA        #DOLLAR
            JSR         putchar
            
            ; Print data in hex
            LDD         dataValue    ; Load data value
            JSR         printWordHex
            
            ; Print spaces (exactly 4 spaces)
            LDAA        #SPACE
            JSR         putchar
            JSR         putchar
            JSR         putchar
            JSR         putchar
            
            ; Print decimal value
            LDD         dataValue    ; Load data value
            JSR         printWordDec
            
            ; Print newline
            LDX         #msgLF
            JSR         printmsg
            
            RTS

***********************************************************************
* writeMemory: Write to memory for W command
* Input:      address - Memory address to write to
*             dataValue - Data value to write
* Output:     Terminal display showing written data
* Registers:  All modified
***********************************************************************
writeMemory            ;Fail
            ; Use address and data that were already validated in command processing
            
            ; Write the data value to memory - using address from command
            LDD         dataValue    ; Get the data value to write
            LDX         address      ; Get the memory address
            STAA        0,X          ; Store high byte at address
            STAB        1,X          ; Store low byte at address+1
            
            ; Now display the result 
            JSR         showMemory
            RTS

***********************************************************************
* printByteBin: Print a byte in binary format (8 bits)
* Input:      A - byte to print
* Output:     Terminal display
* Registers:  A, B modified
***********************************************************************
printByteBin
            PSHA                    ; Save original value
            LDAB        #8          ; 8 bits to print
            
pBinLoop    PSHA                    ; Save current value
            ANDA        #$80        ; Mask high bit
            BEQ         pBinZero
            
            LDAA        #'1'        ; Print 1 for set bit
            BRA         pBinNext
            
pBinZero    LDAA        #'0'        ; Print 0 for clear bit
            
pBinNext    JSR         putchar
            PULA                    ; Restore value
            ASLA                    ; Shift left for next bit
            DECB                    ; Count bits
            BNE         pBinLoop    ; Loop for all 8 bits
            
            PULA                    ; Restore original value
            RTS

***********************************************************************
* printByteHex: Print a byte in hexadecimal format
* Input:      A - byte to print
* Output:     Terminal display
* Registers:  A, B modified
***********************************************************************
printByteHex
            PSHA                    ; Save original value
            
            ; Print high nibble
            TAB                     ; Copy to B
            LSRB                    ; Shift right four times
            LSRB
            LSRB
            LSRB
            ANDB        #$0F        ; Mask to 4 bits
            ADDB        #'0'        ; Convert to ASCII
            CMPB        #'9'+1
            BLO         pHex1
            ADDB        #7          ; Adjust for A-F
pHex1       TBA                     ; Transfer B to A
            JSR         putchar
            
            ; Print low nibble
            PULA                    ; Restore value
            ANDA        #$0F        ; Mask to low 4 bits
            ADDA        #'0'        ; Convert to ASCII
            CMPA        #'9'+1
            BLO         pHex2
            ADDA        #7          ; Adjust for A-F
pHex2       JSR         putchar
            
            RTS

***********************************************************************
* printWordHex: Print a 16-bit word in hexadecimal format
* Input:      D - word to print
* Output:     Terminal display
* Registers:  A, B modified
***********************************************************************
printWordHex
            PSHA                    ; Save high byte
            JSR         printByteHex ; Print high byte
            
            TBA                     ; Transfer B (low byte) to A
            JSR         printByteHex ; Print low byte
            
            PULA                    ; Restore original high byte
            RTS

***********************************************************************
* printWordDec: Print a 16-bit word in decimal format
* Input:      D - word to print
* Output:     Terminal display
* Registers:  All modified
***********************************************************************
printWordDec
            ; Simplified and corrected version for 16-bit unsigned values
            PSHX                    ; Save X
            PSHY                    ; Save Y
            
            ; Store the original number
            STD         tempWord    ; Save the value
            
            ; Special case for zero
            CPD         #0
            BNE         pwdNonZero
            
            LDAA        #'0'        ; Load ASCII '0'
            JSR         putchar
            BRA         pwdDone
            
pwdNonZero  
            ; Format: We'll convert to string by repeated division by 10
            ; We'll push each digit onto the stack then pop them all to print
            LDAB        #0          ; Initialize digit counter
            
pwdLoop     
            ; Divide by 10: D / 10
            TFR         D,Y         ; Y = D (the value to divide)
            LDD         #10         ; Divisor = 10
            IDIV                    ; Y/D -> Y=quotient, D=remainder
            TFR         Y,X         ; X = quotient
            
            ; Convert remainder to ASCII and push onto stack
            ADDB        #'0'        ; Convert to ASCII
            PSHB                    ; Push onto stack
            INCB                    ; Increment digit counter
            XGDX                    ; D = quotient
            
            ; If quotient is zero, we're done
            CPD         #0
            BNE         pwdLoop     ; If not zero, continue
            
            ; Print digits in reverse order (pop from stack)
pwdPrint    PULB                    ; Get digit from stack
            TBA                     ; Transfer to A
            JSR         putchar     ; Print it
            DECB                    ; Decrement counter
            BNE         pwdPrint    ; Continue until all digits printed
            
pwdDone     PULY                    ; Restore Y
            PULX                    ; Restore X
            LDD         tempWord    ; Restore original value
            RTS

***********************************************************************
* typewriter: Simple typewriter program
* Input:      None
* Output:     Echo input characters until reset
* Registers:  A modified
***********************************************************************
typewriter  JSR         getchar     ; Get a character
            JSR         putchar     ; Echo the character
            BRA         typewriter  ; Loop forever

***********************************************************************
* Utility Subroutines
***********************************************************************

***********************************************************************
* printmsg: Print a null-terminated string
* Input:      X - pointer to string
* Output:     Terminal display
* Registers:  A modified, X preserved
***********************************************************************
printmsg    PSHX                    ; Save X
pmsgLoop    LDAA        0,X         ; Get character
            BEQ         pmsgDone    ; If null, done
            JSR         putchar     ; Print it
            INX                     ; Next character
            BRA         pmsgLoop    ; Continue
pmsgDone    PULX                    ; Restore X
            RTS

***********************************************************************
* putchar: Send one character to the terminal
* Input:      A - character to send
* Output:     Terminal display
* Registers:  A preserved
***********************************************************************
putchar     PSHA                    ; Save A
pcharLoop   LDAA        SCISR1      ; Get status
            ANDA        #$80        ; Check TDRE bit
            BEQ         pcharLoop   ; Wait until transmitter ready
            PULA                    ; Restore A
            STAA        SCIDRL      ; Send character
            RTS

***********************************************************************
* getchar: Get one character from the terminal
* Input:      None
* Output:     A - received character
* Registers:  A modified
***********************************************************************
getchar     LDAA        SCISR1      ; Get status
            ANDA        #$20        ; Check RDRF bit
            BEQ         getchar     ; Wait until receiver has data
            LDAA        SCIDRL      ; Get character
            RTS

            END                     ; End of program