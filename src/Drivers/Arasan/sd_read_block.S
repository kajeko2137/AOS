// reads a 512-byte block from the SD Card into RAM

.section ".text"
.equ EMMC_BASE,      0x20300000
.equ EMMC_INTERRUPT, (EMMC_BASE + 0x30)
// Additional EMMC Registers for Data Transfer
.equ EMMC_BLKSIZECNT, (EMMC_BASE + 0x04) // Block Size and Count
.equ EMMC_DATA,       (EMMC_BASE + 0x20) // Data FIFO Port

// CMD17 Configuration for BCM2835
// [29:24] Index: 17 (0x11)
// [21] Data Present: 1
// [17:16] Response Type: 48-bit (2)
// [4] Transfer Direction: 1 (Card to Host Read)
.equ CMD17_CMDTM,     0x11220010 

// -------------------------------------------------------------
// Read a 512-byte block from the SD Card into RAM
// r0 = Sector Number (Block Address)
// r1 = Destination RAM Address (Buffer)
// Returns: r0 = 0 on success, -1 on failure
// -------------------------------------------------------------
.globl sd_read_block
sd_read_block:
    push {r4-r6, lr}
    mov r4, r0              // r4 = Sector Number
    mov r5, r1              // r5 = RAM Destination Pointer

    // 1. Configure the Block Size and Count
    // The register expects: (Block Count << 16) | Block Size
    // We want 1 block of 512 bytes (0x200).
    ldr r0, =EMMC_BLKSIZECNT
    ldr r1, =((1 << 16) | 512)
    str r1, [r0]

    // 2. Transmit CMD17 (READ_SINGLE_BLOCK)
    ldr r0, =CMD17_CMDTM
    mov r1, r4              // Argument is the Sector Number
    bl sd_send_command
    cmp r0, #0
    bne .read_fail          // If command failed, abort

    // 3. The FIFO Siphon Loop
    ldr r2, =EMMC_INTERRUPT
    ldr r4, =EMMC_DATA
    mov r6, #128            // Loop counter: 128 words (512 bytes)

.wait_for_data:
    // Check if Data is Ready to be read from the FIFO
    ldr r3, [r2]
    
    // Check for Errors (Bit 16)
    tst r3, #(1 << 16)
    bne .read_fail
    
    // Check for Buffer Read Ready (Bit 5)
    tst r3, #(1 << 5)
    beq .wait_for_data      // Spin-wait until the FIFO has data

    // Acknowledge the Read Ready interrupt by writing 1 to Bit 5
    mov r3, #(1 << 5)
    str r3, [r2]

.pump_fifo:
    // Read one 32-bit word from the hardware FIFO
    ldr r3, [r4]
    
    // Store it into our RAM buffer and increment the pointer by 4 bytes
    str r3, [r5], #4        
    
    subs r6, r6, #1         // Decrement our word counter
    bne .pump_fifo          // If not 0, grab the next word

    // 4. Wait for the Transfer Complete Signal
.wait_transfer_done:
    ldr r3, [r2]
    tst r3, #(1 << 1)       // Bit 1 is Transfer Complete
    beq .wait_transfer_done

    // Acknowledge Transfer Complete
    mov r3, #(1 << 1)
    str r3, [r2]

    mov r0, #0              // Success
    pop {r4-r6, pc}

.read_fail:
    // Clear error flags and return -1
    ldr r2, =EMMC_INTERRUPT
    ldr r3, =0xFFFF0000
    str r3, [r2]
    mov r0, #-1             // Failure
    pop {r4-r6, pc}