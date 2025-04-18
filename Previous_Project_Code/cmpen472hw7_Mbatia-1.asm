***********************************************************************
*
* Title:         Simple Calculator Program
* 
* Objective:     CMPEN 472 Homework 7 - Implement a simple integer calculator
*
* Revision:      V1.7 (Final)
*
* Date:          March 15, 2025
*
* Programmer:    Kuria Mbatia
*
* Company:       The Pennsylvania State University
*                School of Electrical Engineering and Computer Science
*
* Algorithm:     Command-line parsing, binary number conversion, arithmetic 
*                calculation, error handling, formatted output display
*
* Register use:  A: Character processing, arithmetic operations
*                B: Counters, arithmetic operations
*                X,Y: Pointers, operand storage
*
* Memory use:    RAM Locations from $3000 for data,
*                RAM Locations from $3100 for program
*
* Input:         Terminal input via SCI port (serial)
*
* Output:        Terminal output via SCI port (serial)
*
* Observation:   This calculator handles 4-digit positive decimal numbers.
*                It processes inputs in the format "NUM1 OP NUM2" where 
*                OP is one of: +, -, *, /.
*                The program validates all inputs and outputs to ensure they
*                stay within the 4-digit range (0-9999 for inputs, -9999 to 9999 
*                for results).
*
* Description:   This program implements a simple calculator that:
*                1. Takes inputs through serial communication
*                2. Parses numeric values and operators without spaces
*                3. Performs arithmetic operations (+, -, *, /)
*                4. Validates all inputs and outputs for 4-digit limits
*                5. Handles error conditions (overflow, division by zero, format errors)
*                6. Displays results in decimal format
*
* Limitations:   1. Maximum of 4 digits per input number (0-9999)
*                2. Only processes single operations (no expressions)
*                3. No spaces or other non-digit characters allowed (except operator)
*                4. Results limited to -9999 to 9999 range
*
* Error handling: 1. Format errors for invalid inputs
*                 2. Overflow errors for out-of-range results
*                 3. Division by zero errors
*
* Algorithm details:
*    1. Parse input string to find the operator position
*    2. Extract and convert the two operands to binary
*    3. Perform the arithmetic operation in 16-bit precision
*    4. Validate that results stay within allowed range
*    5. Format and display the result or appropriate error message
*
* Commands:      Input examples:
*                123+456    (addition)
*                789-23     (subtraction)
*                45*678     (multiplication)
*                999/3      (division)
*                003-678    (leading zeros allowed)
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

MAX_BUF_SIZE EQU        20          ; Maximum buffer size
MAX_DIGITS   EQU        4           ; Maximum digits per operand
MAX_VALUE    EQU        9999        ; Maximum value allowed (4 digits)

ERR_FORMAT  EQU         1           ; Error code: Format error
ERR_DIV_ZERO EQU        2           ; Error code: Division by zero
ERR_OVERFLOW EQU        3           ; Error code: Overflow error

ERR_REASON_DIGIT EQU    1           ; Error reason: Too many digits

***********************************************************************
* Data Section - Variables and Strings
***********************************************************************
            ORG         $3000       ; Start of data section

prompt      DC.B        'Ecalc> ',NULL   ; Command prompt
cmdBuffer   DS.B        MAX_BUF_SIZE     ; Command input buffer
cmdLength   DS.B        1                ; Length of current command
num1        DS.W        1                ; First operand (16-bit)
num2        DS.W        1                ; Second operand (16-bit)
result      DS.W        1                ; Calculation result (16-bit)
operator    DS.B        1                ; Operator character
errorFlag   DS.B        1                ; Error flag (0=no error, other=error)
errorReason DS.B        1                ; Additional error reason code 
tempByte    DS.B        1                ; Temporary storage
opPosition  DS.B        1                ; Position of operator in command
tempCounter DS.B        1                ; Temporary counter
numBuf      DS.B        10               ; Buffer for number conversion
tempResult  DS.W        1                ; Temporary storage for calculations
tempWord    DS.W        1                ; Another temporary word storage
digitCount1 DS.B        1                ; Count of digits in first number 
digitCount2 DS.B        1                ; Count of digits in second number

; Error messages
errFormat   DC.B        'Invalid input format',NULL
errOverflow DC.B        'Overflow error',CR,LF,NULL
errDivZero  DC.B        'Division by zero error',CR,LF,NULL
errDigitMsg DC.B        '	;due to 5th digit',CR,LF,NULL
crlfStr     DC.B        CR,LF,NULL       ; Carriage return and line feed

***********************************************************************
* Program Section
***********************************************************************
            ORG         $3100       ; Start of program section
            
; Define stack size to prevent stack issues
STACK_SIZE  EQU         100         ; Reserve 100 bytes for stack

pstart      LDS         #$4000      ; Initialize stack pointer directly

            ; Initialize hardware
            LDAA        #%11111111  ; Set PORTB as output
            STAA        DDRB
            CLR         PORTB       ; Clear all outputs

            ; Initialize serial port - 9600 baud at 24MHz
            CLR         SCIBDH      ; Set baud rate to 9600
            LDAA        #$9C        ; 24MHz/(16*156) = 9615 baud
            STAA        SCIBDL
            LDAA        #$0C        ; Enable SCI transmitter and receiver
            STAA        SCICR2
            
            ; Display welcome message
            LDX         #welcome
            JSR         printmsg
            LDX         #welcome2
            JSR         printmsg

mainLoop    ; Clear variables for each new calculation
            CLR         cmdLength
            CLR         errorFlag
            CLR         errorReason
            CLR         opPosition
            CLR         digitCount1
            CLR         digitCount2
            CLR         num1
            CLR         num1+1
            CLR         num2
            CLR         num2+1
            CLR         result
            CLR         result+1
            CLR         operator
            
            ; Display prompt
            LDX         #prompt
            JSR         printmsg
            
            ; Get command from user
            JSR         getCommand
            
            ; Check if command was received
            LDAA        cmdLength
            BEQ         mainLoop    ; If empty, start again
            
            ; Process the command
            JSR         parseCommand
            
            ; If no error, perform calculation
            LDAA        errorFlag
            BNE         showError
            
            ; Calculate based on operator
            JSR         calculate
            
            ; Check for calculation errors
            LDAA        errorFlag
            BNE         showError
            
            ; Show the result
            JSR         displayResult
            
            ; Add a small delay for stability
            LDY         #100
mlDelay     DEY
            BNE         mlDelay
            
            ; Explicitly return to main loop
            JMP         mainLoop
            
showError   ; Display appropriate error message
            JSR         displayError
            
            ; Add a small delay for stability
            LDY         #100
seDelay     DEY
            BNE         seDelay
            
            ; Explicitly return to main loop
            JMP         mainLoop

welcome     DC.B        CR,LF,'Simple Calculator Program for CMPEN 472',CR,LF,NULL
welcome2    DC.B        'Enter expressions like 123+456 or 78*9 (max 4 digits per number, negative results supported)',CR,LF,NULL
***********************************************************************
* getCommand: Get command from user via serial input
* Input:      None
* Output:     cmdBuffer, cmdLength
* Registers:  A, B, X, Y all modified
***********************************************************************
getCommand  CLR         cmdLength   ; Reset command length
            
            ; Clear buffer
            LDX         #cmdBuffer
            LDAA        #MAX_BUF_SIZE
gcClear     CLR         0,X
            INX
            DECA
            BNE         gcClear
            
            ; Get command characters
            LDY         #cmdBuffer
            
gcLoop      JSR         getchar     ; Get a character
            CMPA        #CR         ; Check for Enter key
            BEQ         gcDone
            
            ; Check maximum buffer size
            LDAB        cmdLength
            CMPB        #MAX_BUF_SIZE-1
            BHS         gcLoop      ; Buffer full, ignore char
            
            JSR         putchar     ; Echo character
            STAA        0,Y         ; Store in buffer
            INY
            INC         cmdLength
            BRA         gcLoop
            
gcDone      ; Null-terminate buffer
            CLR         0,Y
            
            ; Print newline
            LDAA        #CR
            JSR         putchar
            LDAA        #LF
            JSR         putchar
            
            RTS

***********************************************************************
* parseCommand: Parse the command into numbers and operator
* Input:      cmdBuffer, cmdLength
* Output:     num1, num2, operator, errorFlag
* Registers:  All modified
***********************************************************************
parseCommand
            ; Check minimum length (need at least 3 chars: digit, op, digit)
            LDAA        cmdLength
            CMPA        #3
            BHS         pcCheckLen
            
            ; Command too short
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS
            
pcCheckLen  ; Check if command is too long (max 9 chars: 4+1+4)
            LDAA        cmdLength
            CMPA        #10     ; Allow slightly longer inputs to be safe (9+1)
            BLS         pcFindOp
            
            ; Command too long - check if this is due to 5 digit values
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            LDAA        #ERR_REASON_DIGIT
            STAA        errorReason
            RTS
            
pcFindOp    ; Find the operator in the command
            LDX         #cmdBuffer
            CLR         opPosition
            
pcOpLoop    LDAA        0,X         ; Get character
            BEQ         pcOpNotFound
            
            ; Check if it's an operator
            CMPA        #'+'
            BEQ         pcOpFound
            CMPA        #'-'
            BEQ         pcOpFound
            CMPA        #'*'
            BEQ         pcOpFound
            CMPA        #'/'
            BEQ         pcOpFound
            
            ; Check if it's a digit (must be 0-9)
            CMPA        #'0'
            BLO         pcInvalidChar
            CMPA        #'9'
            BHI         pcInvalidChar
            
            ; Valid digit, continue
            INX
            INC         opPosition
            BRA         pcOpLoop
            
pcInvalidChar
            ; Found invalid character
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS
            
pcOpFound   ; Operator found
            STAA        operator    ; Store the operator
            
            ; Make sure operator isn't first character
            LDAA        opPosition
            BEQ         pcInvalidChar  ; If op at position 0, error
            
            ; Check if we have characters after the operator
            LDAB        opPosition
            INCB        ; Position after operator
            CMPB        cmdLength
            BEQ         pcInvalidChar  ; If op is the last character, error

            ; Check if first number has too many digits
            LDAA        opPosition
            STAA        digitCount1  ; Store digit count for first number
            CMPA        #MAX_DIGITS+1
            BLO         pcCheckSecond  ; If <= 4 digits, check second number
            
            ; First number has 5+ digits
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            LDAA        #ERR_REASON_DIGIT
            STAA        errorReason
            RTS
            
pcCheckSecond
            ; Check if second number has too many digits
            LDAA        cmdLength
            SUBA        opPosition   ; Length - operator position
            DECA        ; Subtract 1 for the operator itself
            STAA        digitCount2  ; Store digit count for second number
            CMPA        #MAX_DIGITS+1
            BLO         pcParseNums  ; If <= 4 digits, parse both numbers
            
            ; Second number has 5+ digits
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            LDAA        #ERR_REASON_DIGIT
            STAA        errorReason
            RTS
            
pcParseNums ; Parse first number
            JSR         parseNum1
            
            ; Check for error
            LDAA        errorFlag
            BNE         pcDone
            
            ; Parse second number
            JSR         parseNum2
            
pcDone      RTS
            
pcOpNotFound
            ; No operator found
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS

***********************************************************************
* parseNum1: Parse the first number from cmdBuffer
* Input:      cmdBuffer, opPosition
* Output:     num1, errorFlag
* Registers:  All modified
***********************************************************************
parseNum1   
            ; Clear result
            CLRA
            CLRB
            STD         num1
            
pn1Continue ; Parse the digits before operator
            LDX         #cmdBuffer
            
pn1Loop     LDAA        0,X         ; Get character
            BEQ         pn1Done     ; End of string
            
            ; Check if reached operator
            CMPA        operator
            BEQ         pn1Done
            
            ; Check if it's a digit
            CMPA        #'0'
            BLO         pn1Error    ; Not a digit
            CMPA        #'9'
            BHI         pn1Error    ; Not a digit
            
            ; Multiply current num1 by 10 (D=D*10)
            LDD         num1
            
            ; D = D * 10 = D*8 + D*2
            STD         tempResult  ; Save original
            LSLD                    ; D * 2
            STD         num1        ; Save D*2
            LDD         tempResult  ; Get original
            LSLD                    ; D * 2
            LSLD                    ; D * 4
            LSLD                    ; D * 8
            ADDD        num1        ; D*8 + D*2 = D*10
            STD         num1        ; Save result
            
            ; Convert digit and add
            LDAA        0,X         ; Get digit again
            SUBA        #'0'        ; Convert to binary
            TAB                     ; Transfer A to B (put digit in low byte)
            CLRA                    ; Clear high byte
            ADDD        num1        ; Add to result
            STD         num1        ; Save updated result
            
            ; Continue with next digit
            INX
            BRA         pn1Loop
            
pn1Error    LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS
            
pn1Done     ; Check if number exceeds the maximum allowed value (9999)
            LDD         num1
            CPD         #MAX_VALUE
            BLS         pn1Ok       ; If num1 <= MAX_VALUE, it's OK
            
            ; Number too large - must be a 5+ digit number
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            LDAA        #ERR_REASON_DIGIT
            STAA        errorReason
            RTS
            
pn1Ok       RTS

***********************************************************************
* parseNum2: Parse the second number from cmdBuffer
* Input:      cmdBuffer, opPosition
* Output:     num2, errorFlag
* Registers:  All modified
***********************************************************************
parseNum2   
            ; Clear result
            CLRA
            CLRB
            STD         num2
            
pn2Continue ; Position X at first digit of second number
            LDX         #cmdBuffer
            LDAB        opPosition
            INCB        ; Skip operator
            ABX         ; X now points to second number
            
pn2Loop     LDAA        0,X         ; Get character
            BEQ         pn2Done     ; End of string
            
            ; Check if it's a digit
            CMPA        #'0'
            BLO         pn2Error    ; Not a digit
            CMPA        #'9'
            BHI         pn2Error    ; Not a digit
            
            ; Multiply current num2 by 10 (D=D*10)
            LDD         num2
            
            ; D = D * 10 = D*8 + D*2
            STD         tempResult  ; Save original
            LSLD                    ; D * 2
            STD         num2        ; Save D*2
            LDD         tempResult  ; Get original
            LSLD                    ; D * 2
            LSLD                    ; D * 4
            LSLD                    ; D * 8
            ADDD        num2        ; D*8 + D*2 = D*10
            STD         num2        ; Save result
            
            ; Convert digit and add
            LDAA        0,X         ; Get digit again
            SUBA        #'0'        ; Convert to binary
            TAB                     ; Transfer A to B (put digit in low byte)
            CLRA                    ; Clear high byte
            ADDD        num2        ; Add to result
            STD         num2        ; Save updated result
            
            ; Continue with next digit
            INX
            BRA         pn2Loop
            
pn2Error    LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS
            
pn2Done     ; Check if number exceeds the maximum allowed value (9999)
            LDD         num2
            CPD         #MAX_VALUE
            BLS         pn2Ok       ; If num2 <= MAX_VALUE, it's OK
            
            ; Number too large - must be a 5+ digit number
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            LDAA        #ERR_REASON_DIGIT
            STAA        errorReason
            RTS
            
pn2Ok       RTS

***********************************************************************
* calculate: Perform calculation based on operator
* Input:      num1, num2, operator
* Output:     result, errorFlag
* Registers:  All modified
***********************************************************************
calculate   
            LDAA        operator
            
            CMPA        #'+'
            BEQ         calcAdd
            CMPA        #'-'
            BEQ         calcSub
            CMPA        #'*'
            BEQ         calcMul
            CMPA        #'/'
            BEQ         calcDiv
            
            ; Invalid operator (shouldn't happen)
            LDAA        #ERR_FORMAT
            STAA        errorFlag
            RTS
            
calcAdd     ; Addition: result = num1 + num2
            ; Calculate the result
            LDD         num1        ; Load first operand
            ADDD        num2        ; Add second operand
            
            ; Check for positive overflow (result > 9999)
            CPD         #10000      ; Compare with 10000 (0x2710)
            BHS         calcOverflow  ; If result >= 10000, it's an overflow error
            
            ; Store result
            STD         result
            RTS
            
calcSub     ; Subtraction: result = num1 - num2
            LDD         num1
            SUBD        num2        ; Perform subtraction, result can be negative
            
            ; Check for negative overflow (result < -9999)
            CPD         #$D8F1      ; -9999 = 0xD8F1 in two's complement
            BLT         calcOverflow  ; If result < -9999, it's an overflow error
            
            STD         result
            RTS
            
calcMul     ; Simple multiplication implementation
            LDD         num1
            LDY         num2
            EMUL                    ; Y:D = D * Y (32-bit result in Y:D)
            
            ; Check for overflow - high word must be 0
            CPY         #0
            BNE         calcOverflow  ; High word not zero means overflow
            
            ; Check if result > 9999
            CPD         #10000      ; Compare with 10000 (0x2710)
            BHI         calcOverflow  ; If result > 9999, it's an overflow error
            
            ; Store result
            STD         result
            RTS
            
calcDiv     ; Division implementation
            ; Check for division by zero
            LDD         num2
            BEQ         calcDivZero   ; If divisor is zero, error
            
            ; Perform division
            LDD         num1
            LDX         num2
            IDIV                    ; X = D / X, D = D % X (quotient in X)
            
            ; Store result (quotient)
            STX         result
            RTS
            
calcDivZero ; Division by zero error
            LDAA        #ERR_DIV_ZERO
            STAA        errorFlag
            RTS
            
calcOverflow
            ; Overflow error
            LDAA        #ERR_OVERFLOW
            STAA        errorFlag
            RTS

***********************************************************************
* displayResult: Display calculation result
* Input:      cmdBuffer, result
* Output:     Terminal display
* Registers:  All modified
***********************************************************************
displayResult
            ; Re-echo the original command
            LDX         #cmdBuffer
            JSR         printmsg
            
            ; Print " = " for result
            LDAA        #' '
            JSR         putchar
            LDAA        #'='
            JSR         putchar
            LDAA        #' '
            JSR         putchar
            
            ; Print decimal result
            LDX         #result
            JSR         printDecimalWord
            
            ; Print newline
            LDAA        #CR
            JSR         putchar
            LDAA        #LF
            JSR         putchar
            
            RTS

***********************************************************************
* printDecimalWord: Print a 16-bit word in decimal format
* Input:      X - pointer to 16-bit word
* Output:     Terminal display
* Registers:  All modified, X preserved
***********************************************************************
printDecimalWord
            PSHX                    ; Save X
            PSHY                    ; Save Y
            
            ; Load the 16-bit value into D
            LDD         0,X
            
            ; Check if number is negative (high bit set)
            TSTA                    ; Test high byte
            BPL         pdwPositive ; Branch if positive (bit 7 clear)
            
            ; Handle negative number
            PSHD                    ; Save negative value
            LDAA        #'-'        ; Load minus sign
            JSR         putchar     ; Print minus sign
            PULD                    ; Restore negative value
            
            ; Convert to positive by negating (2's complement)
            COMA                    ; One's complement of A
            COMB                    ; One's complement of B
            ADDD        #1          ; Add 1 for two's complement
            
pdwPositive  ; Now proceed with normal decimal conversion
            ; Clear the buffer for storing digits
            LDX         #numBuf
            CLR         0,X         ; Ensure null termination
            
            ; Special case for zero
            CPD         #0
            BNE         pdwNonZero
            
            ; Just print "0" for the value zero
            LDAA        #'0'
            JSR         putchar
            BRA         pdwDone
            
pdwNonZero  ; Set up buffer index
            LDY         #numBuf
            
            ; Convert to decimal by repeatedly dividing by 10
pdwLoop     LDX         #10        ; Divisor = 10
            IDIV                   ; D / X -> X=quotient, D=remainder
            
            ; Convert remainder to ASCII and store it
            ADDB        #'0'       ; Convert to ASCII
            STAB        0,Y        ; Store in buffer
            INY                    ; Move to next buffer position
            CLR         0,Y        ; Ensure null termination
            
            ; Move quotient to D and continue if not zero
            XGDX                   ; X->D (quotient becomes new dividend)
            CPD         #0
            BNE         pdwLoop
            
            ; Print digits in reverse order (back to front)
            LDY         #numBuf    ; Reset to start of buffer
pdwFindEnd  LDAA        0,Y        ; Get character
            BEQ         pdwPrintLoop ; If null, we've found the end
            INY                    ; Otherwise, move to next char
            BRA         pdwFindEnd
            
pdwPrintLoop
            ; Y now points to the null terminator, start printing from Y-1 backwards
            DEY                    ; Move back one position
            LDAA        0,Y        ; Get the digit
            JSR         putchar    ; Print it
            
            ; Check if we've reached the start of buffer
            CPY         #numBuf
            BNE         pdwPrintLoop
            
pdwDone     PULY                   ; Restore Y
            PULX                   ; Restore X
            RTS

***********************************************************************
* displayError: Display appropriate error message
* Input:      cmdBuffer, errorFlag
* Output:     Terminal display
* Registers:  All modified
***********************************************************************
displayError
            ; Re-echo the input command
            LDX         #cmdBuffer
            JSR         printmsg
            
            ; Print newline
            LDX         #crlfStr
            JSR         printmsg
            
            ; Select appropriate error message based on errorFlag
            LDAA        errorFlag
            CMPA        #ERR_FORMAT
            BNE         deCheckDivZero
            
            ; Format error
            LDX         #errFormat
            JSR         printmsg
            
            ; Check if error is due to 5th digit
            LDAA        errorReason
            CMPA        #ERR_REASON_DIGIT
            BNE         deNewLine
            
            ; Print 5th digit message
            LDX         #errDigitMsg
            JSR         printmsg
            BRA         deRTS
            
deNewLine   ; Just print newline for regular format error
            LDX         #crlfStr
            JSR         printmsg
            BRA         deRTS
            
deCheckDivZero
            CMPA        #ERR_DIV_ZERO
            BNE         deCheckOverflow
            
            ; Division by zero error
            LDX         #errDivZero
            BRA         dePrintMsg
            
deCheckOverflow
            ; Must be overflow error
            LDX         #errOverflow
            
dePrintMsg  ; Print the error message
            JSR         printmsg
            
deRTS       RTS

***********************************************************************
* Utility Subroutines
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
putchar     PSHA                   ; Save A
putchLoop   LDAA        SCISR1     ; Get status
            ANDA        #$80       ; Check TDRE bit
            BEQ         putchLoop  ; Wait until transmitter ready
            PULA                   ; Restore A
            STAA        SCIDRL     ; Send character
            RTS
            
***********************************************************************
* getchar: Get one character from the terminal
* Input:      None
* Output:     A - received character
* Registers:  A modified
***********************************************************************
getchar     LDAA        SCISR1     ; Get status
            ANDA        #$20       ; Check RDRF bit
            BEQ         getchar    ; Wait until receiver has data
            LDAA        SCIDRL     ; Get character
            RTS

            END         ; End of program