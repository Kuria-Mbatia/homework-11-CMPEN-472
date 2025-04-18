# Active Context

## Current Focus
Implementation of ADC functionality in existing waveform generator program

## Detailed Implementation Plan

### Phase 1: ADC Setup and Initialization
1. Add ADC Register Definitions
   - ATDCTL2 ($0082): Control Register 2
   - ATDCTL3 ($0083): Control Register 3
   - ATDCTL4 ($0084): Control Register 4
   - ATDCTL5 ($0085): Control Register 5
   - ATDSTAT0 ($0086): Status Register
   - ATDDR0H ($0090): Result Register High
   - ATDDR0L ($0091): Result Register Low

2. Add ADC Variables
   - ADC_ACTIVE: Flag indicating ADC sampling is in progress
   - ADC_COUNTER: Counter for tracking samples (0-2047)
   - ADC_BUFFER: Storage for ADC results if needed
   - ADC_FINISHED_MSG: Message for display after sampling completes

3. Configure ADC Registers
   - ATDCTL2 = %11000000 (Enable ADC, clear flags, disable ADC interrupts)
   - ATDCTL3 = %00001000 (Single conversion per sequence)
   - ATDCTL4 = %10000111 (8-bit, prescaler for appropriate timing)
   - ATDCTL5 = %10000111 (Right-justified, unsigned, single conversion, channel 7)

### Phase 2: Timer Setup for 8kHz Sampling
1. Configure Timer Channel 1 for Output Compare
   - Calculate 125μs timing (8kHz) based on 24MHz bus clock
   - 24MHz ÷ 8000Hz = 3000 clock cycles per sample
   - Set up TC1 with appropriate compare value
   - Configure OC5 interrupt vector

2. Implement Timer OC5 Interrupt Service Routine
   - Update compare register for next interrupt
   - Read ADC result from previous conversion
   - Convert to decimal and output to terminal
   - Start next ADC conversion
   - Track sample count and disable when complete

### Phase 3: Command Integration
1. Add 'adc' Command Recognition
   - Parse 'adc' command from terminal input
   - Verify command format (exactly 'adc')
   - Display error for invalid format

2. ADC Command Execution Sequence
   - Print acknowledgment message
   - Initialize ADC_COUNTER to 0
   - Set ADC_ACTIVE flag to 1
   - Configure ADC for first sample
   - Start first ADC conversion
   - Enable Timer Channel 1 interrupt

### Phase 4: Data Handling and Output
1. Binary to Decimal Conversion
   - Extract hundreds, tens, and ones digits
   - Convert each digit to ASCII
   - Format output appropriately

2. Terminal Output Management
   - Send decimal values to terminal via SCI
   - Maintain consistent timing
   - Ensure output doesn't affect sampling timing

3. ADC Completion Handling
   - Print "Finished" message after 2048 samples
   - Disable Timer OC5 interrupt
   - Return to command prompt

### Phase 5: Integration with Existing Functionality
1. Ensure Clock Continuation
   - Digital clock must run during ADC operation
   - 7-segment display must update every second
   - RTI and Timer OC5 interrupts must coexist

2. Maintain Command Functionality
   - Preserve all existing commands
   - Ensure proper state management after ADC completion
   - Handle interruptions or errors gracefully

3. Error Handling
   - ADC initialization failures
   - Conversion timeouts
   - Command format errors

## Execution Flow
1. Program Startup:
   - Initialize stack, I/O, SCI, RTI (existing code)
   - Initialize ADC and Timer modules
   - Set ADC_ACTIVE to 0 (inactive)
   
2. Command Processing:
   - Parse user input (existing code)
   - On 'adc' command:
     - Start 2048-sample ADC sequence
     - Enable Timer OC5 interrupt
   
3. Timer OC5 Interrupt:
   - Read ADC result
   - Convert to decimal and output
   - Increment sample counter
   - When 2048 samples complete:
     - Print "Finished"
     - Disable interrupt

4. RTI Interrupt:
   - Continue clock functionality
   - Update 7-segment display

## Current Status
- Project requirements analyzed
- Implementation plan created and detailed
- Technical context documented
- Ready to begin implementation 