# System Patterns

## System Architecture
The system follows a command-driven architecture with interrupt-based timing and I/O operations:

```mermaid
graph TD
    A[Main Program Loop] --> B[Command Parser]
    B --> C[Command Handlers]
    C --> D[ADC Command]
    C --> E[Clock Commands]
    C --> F[Wave Generation Commands]
    
    G[Interrupt System] --> H[RTI for Clock]
    G --> I[Timer OC5 for ADC Sampling]
    
    D --> I
    I --> J[ADC Hardware]
    J --> I
    I --> K[Terminal Output]
    
    H --> L[7-Segment Display]
```

## Core Design Patterns

### Command Pattern
- User input is processed as commands ('adc', 't', 'gw', etc.)
- Each command has a dedicated handler function
- Command parser validates format before execution
- Error handling for invalid commands

### State Machine
- System maintains state flags for various operations
- ADC_ACTIVE flag indicates ADC sampling in progress
- State transitions manage mode changes
- Prevents conflicting operations

### Interrupt-Driven Processing
- RTI manages clock with 1-second updates
- Timer OC5 manages ADC sampling at 8kHz
- Prioritized interrupt handling
- Non-blocking operation for UI responsiveness

### Producer-Consumer Pattern
- ADC interrupt produces sample data
- Terminal output consumes and displays data
- Timing-critical operation management
- Buffer management if needed

## Critical Components

### ADC Subsystem
- 8-bit single conversion mode
- Channel 7 input for analog signal
- Timer-driven sampling at precise 8kHz rate
- 2048 samples per acquisition cycle

### Timing System
- RTI for 1-second clock updates
- Timer OC5 for 125μs ADC sampling
- Precise timing critical for proper signal representation

### User Interface
- Terminal-based command input
- Decimal output format for ADC values
- 7-segment display for clock visualization
- Error message system for user feedback

## Data Flow

```mermaid
graph LR
    A[Analog Signal] --> B[ADC Hardware]
    B --> C[ADC Result Register]
    C --> D[Timer OC5 ISR]
    D --> E[Binary to Decimal Conversion]
    E --> F[Terminal Output]
    
    G[User Input] --> H[Command Parser]
    H --> I[Command Handler]
    I --> J[System State Changes]
    
    K[RTI] --> L[Clock Update]
    L --> M[7-Segment Display]
```

## Integration Patterns

### Module Initialization
- ADC initialization at startup
- Timer configuration but interrupt disabled until needed
- Command handlers registered with parser

### Command Execution
- Valid commands trigger specific handlers
- 'adc' command initiates sampling sequence
- State management prevents conflicting operations

### Interrupt Coordination
- Multiple interrupt sources (RTI, Timer OC5) coexist
- Prioritization to maintain real-time operation
- Critical sections protected as needed

### Error Handling
- Command format validation
- Hardware initialization checks
- Timeout mechanisms for hardware operations
- Recovery procedures for error conditions 