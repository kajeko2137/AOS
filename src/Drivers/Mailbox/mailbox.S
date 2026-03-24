// BCM2835 GPU Mailbox Interface
// Communicates with the VideoCore GPU via the property tag channel.

.section ".text"

// Mailbox Register Addresses (ARM physical)
.equ MBOX_BASE,     0x2000B880
.equ MBOX_READ,     (MBOX_BASE + 0x00)  // Mailbox 0 Read (GPU -> ARM)
.equ MBOX_STATUS,   (MBOX_BASE + 0x18)  // Mailbox 0 Status
.equ MBOX_WRITE,    (MBOX_BASE + 0x20)  // Mailbox 1 Write (ARM -> GPU)

.equ MBOX_FULL,     0x80000000           // Status bit: mailbox is full
.equ MBOX_EMPTY,    0x40000000           // Status bit: mailbox is empty
.equ MBOX_CHANNEL,  8                    // Property Tags channel

.equ MBOX_SUCCESS,  0x80000000           // Response code: request successful

// -----------------------------------------------------------------
// mbox_call: Send a property tag message to the GPU and wait for reply
// Input:  r0 = physical address of the message buffer (16-byte aligned)
// Output: r0 = 0 on success, -1 on failure
// -----------------------------------------------------------------
.globl mbox_call
mbox_call:
    push {r4, lr}
    mov r4, r0                      // Save buffer address

    // 1. Wait until the mailbox is not full
    ldr r1, =MBOX_STATUS
1:  ldr r2, [r1]
    tst r2, #MBOX_FULL
    bne 1b

    // 2. Write the buffer address OR'd with channel 8 to the write register
    // The bottom 4 bits are the channel, the upper 28 bits are the address.
    // Buffer MUST be 16-byte aligned so bottom 4 bits are free.
    orr r0, r4, #MBOX_CHANNEL
    ldr r1, =MBOX_WRITE
    str r0, [r1]

    // 3. Wait for the GPU's response
    ldr r1, =MBOX_STATUS
    ldr r3, =MBOX_READ
2:  ldr r2, [r1]
    tst r2, #MBOX_EMPTY
    bne 2b                          // Wait until mailbox is not empty

    // 4. Read the response. Check it matches our channel.
    ldr r2, [r3]
    and r0, r2, #0xF                // Extract channel from bottom 4 bits
    cmp r0, #MBOX_CHANNEL
    bne 2b                          // Wrong channel, keep reading

    // 5. Check the response code in the buffer
    ldr r0, [r4, #4]                // mailbuffer[1] = response code
    ldr r1, =MBOX_SUCCESS
    cmp r0, r1
    bne .mbox_fail

    mov r0, #0                      // Return 0 = success
    pop {r4, pc}

.mbox_fail:
    mov r0, #-1                     // Return -1 = failure
    pop {r4, pc}

// -----------------------------------------------------------------
// mbox_sd_power_cycle: Power OFF then ON the SD card via GPU
// Output: r0 = 0 on success
// -----------------------------------------------------------------
.globl mbox_sd_power_cycle
mbox_sd_power_cycle:
    push {lr}

    // --- Power OFF ---
    ldr r0, =mbox_buf
    // Header
    mov r1, #32                     // Buffer size: 8 words × 4 bytes
    str r1, [r0, #0]
    mov r1, #0                      // Request code
    str r1, [r0, #4]
    // Tag: Set Power State (0x00028001)
    ldr r1, =0x00028001
    str r1, [r0, #8]
    mov r1, #8                      // Value buffer size
    str r1, [r0, #12]
    mov r1, #8                      // Request: value length = 8
    str r1, [r0, #16]
    mov r1, #0                      // Device ID 0 = SD Card
    str r1, [r0, #20]
    mov r1, #2                      // State: OFF (bit 1 = wait for stable)
    str r1, [r0, #24]
    mov r1, #0                      // End tag
    str r1, [r0, #28]

    bl mbox_call
    cmp r0, #0
    bne .power_cycle_fail

    // Wait ~5ms for power to settle
    ldr r0, =50000
    bl delay

    // --- Power ON ---
    ldr r0, =mbox_buf
    mov r1, #32
    str r1, [r0, #0]
    mov r1, #0 
    str r1, [r0, #4]
    ldr r1, =0x00028001
    str r1, [r0, #8]
    mov r1, #8
    str r1, [r0, #12]
    mov r1, #8
    str r1, [r0, #16]
    mov r1, #0                      // Device ID 0 = SD Card
    str r1, [r0, #20]
    mov r1, #3                      // State: ON + wait for stable
    str r1, [r0, #24]
    mov r1, #0
    str r1, [r0, #28]

    bl mbox_call
    // r0 already holds 0 or -1
    pop {pc}

.power_cycle_fail:
    mov r0, #-1
    pop {pc}

// -----------------------------------------------------------------
// mbox_get_emmc_clock: Query the EMMC base clock rate from the GPU
// Output: r0 = clock rate in Hz (e.g. 250000000), or 0 on failure
// -----------------------------------------------------------------
.globl mbox_get_emmc_clock
mbox_get_emmc_clock:
    push {lr}

    ldr r0, =mbox_buf
    // Header
    mov r1, #32                     // Buffer size: 8 words × 4 bytes
    str r1, [r0, #0]
    mov r1, #0                      // Request code
    str r1, [r0, #4]
    // Tag: Get Clock Rate (0x00030002)
    ldr r1, =0x00030002
    str r1, [r0, #8]
    mov r1, #8                      // Value buffer size
    str r1, [r0, #12]
    mov r1, #4                      // Request: value length = 4
    str r1, [r0, #16]
    mov r1, #1                      // Clock ID 1 = EMMC
    str r1, [r0, #20]
    mov r1, #0                      // Space for returned rate
    str r1, [r0, #24]
    mov r1, #0                      // End tag
    str r1, [r0, #28]

    bl mbox_call
    cmp r0, #0
    bne .clock_fail

    // Read the returned clock rate from mailbuffer[6]
    ldr r0, =mbox_buf
    ldr r0, [r0, #24]              // Word 6 = clock rate in Hz
    pop {pc}

.clock_fail:
    mov r0, #0                      // Return 0 = failure
    pop {pc}

// -----------------------------------------------------------------
// Message buffer — must be 16-byte aligned
// -----------------------------------------------------------------
.section ".data"
.align 4                            // 2^4 = 16-byte alignment
mbox_buf: .space 64                  // 64 bytes for property tag messages
