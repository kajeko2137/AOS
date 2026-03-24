.section ".text"
// -------------------------------------------------------------
// The Boot Manager: Checks the flag and claims space
// -------------------------------------------------------------
.globl boot_manager
boot_manager:
    push {lr}

    // 1. Initialize the physical hardware
    // SKIP GPIO reconfig — GPU already configured pins for SD boot
    // bl sd_init_part1
    // ldr r0, =msg_sd1
    // bl uart_puts

    bl sd_host_init
    ldr r0, =msg_sd2
    bl uart_puts

    // 2. Negotiate with the SD card microcontroller
    bl sd_card_init
    ldr r0, =msg_sd3
    bl uart_puts

    // 3. Read Sector 0 (The Master Boot Record)
    // [TODO: We need to write the `sd_read_block` function!]
    mov r0, #0              // Target Sector 0
    ldr r1, =sector_buffer  // Ram address to dump the 512 bytes
    bl sd_read_block
    ldr r0, =msg_sd4
    bl uart_puts

    // 4. Check the "First Boot" Flag at byte offset 0x01B8 in the MBR
    ldr r0, =sector_buffer
    ldr r1, =0x01B8
    ldrb r2, [r0, r1]       // Load the single flag byte

    cmp r2, #1              // Is the flag set to 1 (First Boot)?
    beq .do_claim
    
    // Not first boot. Return to Kernel.
    pop {pc}

.do_claim:
    bl claim_free_space
    pop {pc}

// -------------------------------------------------------------
// Stub: Claim Free Space
// -------------------------------------------------------------
.globl claim_free_space
claim_free_space:
    push {lr}
    ldr r0, =msg_claiming
    bl uart_puts
    
    // [TODO: MBR Partition table math and writeback goes here]
    
    pop {pc}

.section ".data"
.align 4
.globl sd_rca
sd_rca: .word 0             // Stores the card's target address

.section ".bss"
.align 4
sector_buffer: .space 512   // 512-byte buffer for reading the MBR

.section ".rodata"
msg_claiming: .asciz "[DBG] First boot detected. Claiming SD card void...\r\n"
msg_sd1: .asciz "[DBG] sd_init_part1 complete\r\n"
msg_sd2: .asciz "[DBG] sd_host_init complete\r\n"
msg_sd3: .asciz "[DBG] sd_card_init complete\r\n"
msg_sd4: .asciz "[DBG] sd_read_block complete\r\n"
