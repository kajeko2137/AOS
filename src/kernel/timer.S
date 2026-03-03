.section ".text"

.equ TIMER_BASE,      0x20003000
.equ TIMER_CS,        (TIMER_BASE + 0x00) // Control/Status
.equ TIMER_CLO,       (TIMER_BASE + 0x04) // Counter Lower 32-bits
.equ TIMER_C1,        (TIMER_BASE + 0x10) // Compare 1

.equ INTC_BASE,       0x2000B200
.equ INTC_ENABLE_1,   (INTC_BASE + 0x10)  // Interrupt Enable Register 1

.equ TIMER_INTERVAL,  10000  // 10,000 microseconds = 10ms heartbeat

.globl init_timer
init_timer:
    push{lr}

    // Tell interrupt controller to pass Timer 1 through
    ldr r0, =INTC_ENABLE_1
    mov r1, #(1 << 1)
    str r1, [r0]

    // "Zeroing" the timer (setting a given point as 0 and setting up 10ms interrupts)
    ldr r0, =TIMER_CLO
    ldr r1, [r0]
    
    ldr r2, =TIMER_INTERVAL
    add r1, r1, r2

    // Now we write the calculated timestamp (on which the timer needs to throw an interrupt) into the compare register
    ldr r0, =TIMER_C1
    mov r1, #(1 << 1)
    str r1, [r0]

    // There can be a "stale match" so to prevent it, we do the following
    ldr r0, =TIMER_CS
    mov r1, #(1 << 1)
    str r1, [r0]

    pop{pc}

// BEHOLD THE DARK MAGIC INCANTATION TO ENABLE CPU INTERRUPTS!!!
.globl enable_interrupts
enable_interrupts:
    cpsie i 
    bx lr