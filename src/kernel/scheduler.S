.equ MAX_PROCS_PER_TIER, 256
.equ QUEUE_SIZE,         (MAX_PROCS_PER_TIER * 4) // 4 bytes per process address

// Hardware RNG Peripheral Registers
.equ RNG_CTRL,           0x20104000
.equ RNG_STATUS,         0x20104004
.equ RNG_DATA,           0x20104008

// -----------------------------------------------------------------
// .bss Section: The 5-Array Ring Buffer Memory Layout
// -----------------------------------------------------------------
.section ".bss"
.align 4

// 1. The 5 Physical Buffers
buf0:       .space QUEUE_SIZE
buf1:       .space QUEUE_SIZE
buf2:       .space QUEUE_SIZE
buf3:       .space QUEUE_SIZE
buf_sink:   .space QUEUE_SIZE

// 2. The Tier Pointers
.globl t0, t1, t2, t3, free_buffer
t0:             .space 4
t1:             .space 4
t2:             .space 4
t3:             .space 4
free_buffer:    .space 4

// 3. The Tier Counters
.globl q0_count, q1_count, q2_count, q3_count
q0_count:       .space 4
q1_count:       .space 4
q2_count:       .space 4
q3_count:       .space 4

// 4. The RNG State (Xorshift Seed)
.globl rng_state
rng_state:      .space 4

// -----------------------------------------------------------------
// .rodata Section
// -----------------------------------------------------------------
.section ".rodata"
msg_reschedule: .asciz "[DBG] Reschedule called, halting.\r\n"
msg_tls_init:   .asciz "[DBG] Tiered Lottery Scheduler Initialized.\r\n"

// -----------------------------------------------------------------
// .text Section
// -----------------------------------------------------------------
.section ".text.scheduler"

// Initialize the TLS memory structures and hardware RNG
.globl start_TLS
start_TLS:
    push {lr}

    // 1. Map initial pointers to physical buffers
    ldr r0, =buf0
    ldr r1, =t0
    str r0, [r1]

    ldr r0, =buf1
    ldr r1, =t1
    str r0, [r1]

    ldr r0, =buf2
    ldr r1, =t2
    str r0, [r1]

    // t3 permanently points to the sink accumulator
    ldr r0, =buf_sink
    ldr r1, =t3
    str r0, [r1]

    // buf3 starts as our empty reserve buffer for the 100ms ring rotation
    ldr r0, =buf3
    ldr r1, =free_buffer
    str r0, [r1]

    // Note: q0_count to q3_count are already 0 because _start sterilized .bss

    // 2. Wake up the Hardware RNG
    ldr r0, =RNG_CTRL
    mov r1, #1
    str r1, [r0]            // Enable RNG hardware

1:  // 3. Spin-wait for the silicon to collect enough entropy
    ldr r0, =RNG_STATUS
    ldr r1, [r0]
    lsr r1, r1, #24         // Entropy word count is in the top 8 bits
    cmp r1, #0
    beq 1b                  // If 0 words available, loop and wait

    // 4. Read the true random seed and store it
    ldr r0, =RNG_DATA
    ldr r1, [r0]
    ldr r2, =rng_state
    str r1, [r2]

    // 5. Print success message
    ldr r0, =msg_tls_init
    bl uart_puts

    pop {pc}


// Temporarily keeping your placeholder for the timer interrupt
.globl reschedule
reschedule:
    ldr r0, =msg_reschedule
    bl uart_puts
    b halt
