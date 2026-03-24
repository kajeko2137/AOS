//Arasan eMMC Host Controller Driver

.section ".text"

.equ GPIO_BASE, 0x20200000
.equ GPFSEL4,   (GPIO_BASE + 0x10)  // Controls GPIO 40-49
.equ GPFSEL5,   (GPIO_BASE + 0x14)  // Controls GPIO 50-59
.equ GPPUD,     (GPIO_BASE + 0x94)  // Pull-up/Pull-down Enable
.equ GPPUDCLK1, (GPIO_BASE + 0x9C)  // Pull-up/Pull-down Clock 1 (GPIO 32-53)

// Initialize GPIO pins 48-53 for SD Card access (ALT3)
.globl sd_init_part1
sd_init_part1:
    push {lr}

    // 1. Route GPIO 48 (CLK) and 49 (CMD) to ALT0 (Arasan EMMC)
    ldr r0, =GPFSEL4
    ldr r1, [r0]
    
    // Clear bits 24-29 (3 bits per pin * 2 pins)
    ldr r2, =~(0x3F << 24)      
    and r1, r1, r2
    
    // Set bits 24-29 to 0b100 (ALT0) -> 0b100100 = 0x24
    ldr r2, =(0x24 << 24)       
    orr r1, r1, r2
    str r1, [r0]

    // 2. Route GPIO 50-53 to ALT0 (Arasan EMMC)
    ldr r0, =GPFSEL5
    ldr r1, [r0]
    
    // Clear bits 0-11 (3 bits per pin * 4 pins)
    ldr r2, =~(0xFFF)           
    and r1, r1, r2
    
    // Set bits 0-11 to 0b100 (ALT0) -> 0b100100100100 = 0x924
    ldr r2, =0x924              
    orr r1, r1, r2
    str r1, [r0]

    // 3. Engage internal Pull-Up resistors for GPIO 48-53
    ldr r0, =GPPUD
    mov r1, #2                  // 2 = Enable Pull-Up control
    str r1, [r0]
    
    // Wait 150 cycles for the control signal to set
    mov r0, #150
    bl delay

    // Assert the clock on pins 48-53 to lock in the pull-up state
    // GPIO 48 is bit 16 in GPPUDCLK1 (48 - 32 = 16). 6 pins = 0x3F
    ldr r0, =GPPUDCLK1
    ldr r1, =(0x3F << 16)       
    str r1, [r0]
    
    // Wait 150 cycles for the electrical state to latch
    mov r0, #150
    bl delay

    // Remove the control signal and clock
    mov r1, #0
    ldr r0, =GPPUD
    str r1, [r0]
    ldr r0, =GPPUDCLK1
    str r1, [r0]

    pop {pc}

// Arasan EMMC Peripheral Registers
.equ EMMC_BASE,     0x20300000
.equ EMMC_STATUS,   (EMMC_BASE + 0x24)
.equ EMMC_CONTROL0, (EMMC_BASE + 0x28)
.equ EMMC_CONTROL1, (EMMC_BASE + 0x2C)

// EMMC Register Offsets Extension
.equ EMMC_IRPT_EN,   (EMMC_BASE + 0x34) // Interrupt Status Enable
.equ EMMC_IRPT_MASK, (EMMC_BASE + 0x38) // Interrupt Signal Enable

// EMMC Register Offsets Extension 2
.equ EMMC_CONTROL2,  (EMMC_BASE + 0x3C)
.equ EMMC_SLOTISR_VER, (EMMC_BASE + 0xFC) // Host Controller Version

// Initialize the Arasan Host Controller
// Follows the exact sequence from the working rpi-boot/emmc.c reference.
.globl sd_host_init
sd_host_init:
    push {r4, lr}

    // ============================================================
    // Phase 1: GPU Mailbox — Power-cycle the SD card
    // ============================================================
    ldr r0, =msg_mbox_pwr
    bl uart_puts
    bl mbox_sd_power_cycle
    cmp r0, #0
    bne .mbox_error

    // ============================================================
    // Phase 2: Read controller version (for diagnostics)
    // ============================================================
    ldr r0, =EMMC_SLOTISR_VER
    ldr r1, [r0]
    mov r0, r1
    bl print_hex_error

    // ============================================================
    // Phase 3: Hardware Reset (Full SRST_HC)
    // ============================================================
    ldr r4, =EMMC_CONTROL1
    ldr r1, [r4]
    orr r1, r1, #(1 << 24)         // SRST_HC
    bic r1, r1, #(1 << 2)          // Disable SD clock
    bic r1, r1, #(1 << 0)          // Disable internal clock
    str r1, [r4]

    // Wait for ALL reset bits (24, 25, 26) to self-clear
    ldr r2, =(7 << 24)
1:  ldr r1, [r4]
    tst r1, r2
    bne 1b

    // ============================================================
    // Phase 4: Check for an inserted card (STATUS bit 16)
    // If the controller doesn't see a card, abort immediately.
    // ============================================================
    ldr r0, =EMMC_STATUS
    // Wait up to ~500ms for card detect
    ldr r3, =500000
2:  ldr r1, [r0]
    tst r1, #(1 << 16)             // Card Inserted?
    bne .card_found
    subs r3, r3, #1
    bne 2b

    // Card not detected — print STATUS and halt
    ldr r0, =msg_no_card
    bl uart_puts
    ldr r0, =EMMC_STATUS
    ldr r0, [r0]
    bl print_hex_error
    b .host_init_fail

.card_found:
    ldr r0, =msg_card_ok
    bl uart_puts

    // ============================================================
    // Phase 5: Post-reset configuration
    // ============================================================

    // 5a: Turn on SD Bus Power (CONTROL0)
    ldr r0, =EMMC_CONTROL0
    ldr r1, [r0]
    orr r1, r1, #(0x0F << 8)
    str r1, [r0]
    ldr r0, =50000
    bl delay

    // 5b: Clear CONTROL2
    ldr r0, =EMMC_CONTROL2
    mov r1, #0
    str r1, [r0]

    // 5c: Get EMMC base clock from GPU
    ldr r0, =msg_mbox_clk
    bl uart_puts
    bl mbox_get_emmc_clock
    cmp r0, #0
    beq .mbox_error

    ldr r1, =emmc_base_clock
    str r0, [r1]
    bl print_hex_error

    // 5d: Clock setup (read-modify-write)
    ldr r1, [r4]
    orr r1, r1, #(1 << 0)          // Enable internal clock
    orr r1, r1, #(7 << 16)         // Data timeout
    ldr r2, =~(0xFFE0)
    and r1, r1, r2
    ldr r2, =(0xFF << 8)
    orr r1, r1, r2
    str r1, [r4]

    // 5e: Wait for internal clock to stabilize
    ldr r3, =0x1000000
3:  ldr r1, [r4]
    tst r1, #(1 << 1)
    bne .clk_stable
    subs r3, r3, #1
    bne 3b

    ldr r0, =msg_clk_fail
    bl uart_puts
    b .host_init_fail

.clk_stable:
    // 5f: Enable SD clock
    ldr r0, =50000
    bl delay
    ldr r1, [r4]
    orr r1, r1, #(1 << 2)
    str r1, [r4]
    ldr r0, =50000
    bl delay

    // ============================================================
    // Phase 8: Configure Interrupts (AFTER clock)
    // BCM2835 register semantics (OPPOSITE to SDHCI naming!):
    //   0x34 (IRPT_EN)   = Status Enable: which bits appear in INTERRUPT reg
    //   0x38 (IRPT_MASK) = Signal Enable: which bits generate ARM IRQs
    // We want: all status visible (for polling), no ARM IRQs.
    // ============================================================
    ldr r0, =EMMC_IRPT_EN
    ldr r1, =0xFFFFFEFF             // Enable all status bits except Card Interrupt
    str r1, [r0]

    ldr r0, =EMMC_INTERRUPT
    ldr r1, =0xFFFFFFFF
    str r1, [r0]

    ldr r0, =EMMC_IRPT_MASK
    mov r1, #0                      // Don't generate ARM IRQs (we poll)
    str r1, [r0]

    ldr r0, =50000
    bl delay

    // Debug: dump final CONTROL0 and CONTROL1 values
    ldr r0, =EMMC_CONTROL0
    ldr r0, [r0]
    bl print_hex_error
    ldr r0, =EMMC_CONTROL1
    ldr r0, [r0]
    bl print_hex_error

    pop {r4, pc}

.host_init_fail:
1:  wfe
    b 1b

.mbox_error:
    ldr r0, =msg_mbox_err
    bl uart_puts
1:  wfe
    b 1b

// EMMC Register Offsets
.equ EMMC_BASE,      0x20300000
.equ EMMC_CMDTM,     (EMMC_BASE + 0x0C) // Command and Transfer Mode
.equ EMMC_ARG1,      (EMMC_BASE + 0x08) // Argument (WAS 0x14 - HUGE BUG)
.equ EMMC_STATUS,    (EMMC_BASE + 0x24) // Present State
.equ EMMC_INTERRUPT, (EMMC_BASE + 0x30) // Interrupt Status

// Send a command to the SD Card
// r0 = Command configuration for CMDTM
// r1 = 32-bit Argument for ARG1
// Returns: r0 = 0 on success, -1 on error
.globl sd_send_command
sd_send_command:
    push {lr}

    push {r0-r3}
    ldr r0, =msg_send_start
    bl uart_puts
    pop {r0-r3}

    // 1. Ensure the Command Line is Idle
    ldr r2, =EMMC_STATUS
1:  ldr r3, [r2]
    tst r3, #1                  // Bit 0 is Command Inhibit (CMD)
    bne 1b                      // Spin-wait until the line is free

    push {r0-r3}
    ldr r0, =msg_send_idle
    bl uart_puts
    pop {r0-r3}

    // 2. Clear the Interrupt Register
    // The BCM2835 clears interrupt flags when you write '1' to them.
    // Writing 0xFFFFFFFF clears all pending status flags.
    ldr r2, =EMMC_INTERRUPT
    ldr r3, =0xFFFFFFFF
    str r3, [r2]

    // 3. Load the Argument
    ldr r2, =EMMC_ARG1
    str r1, [r2]

    // 4. Pull the Trigger
    // Writing to CMDTM physically initiates the serial transmission.
    ldr r2, =EMMC_CMDTM
    str r0, [r2]

    push {r0-r3}
    ldr r0, =msg_send_trigger
    bl uart_puts
    pop {r0-r3}

    // -------------------------------------------------------------
    // 5. Spin-wait for the Hardware to Finish
    // -------------------------------------------------------------
    ldr r2, =EMMC_INTERRUPT
    ldr r1, =0x8001             // (1 << 15) | 1 (Bit 15 is ERR_INTR, Bit 0 is CMD_DONE)
2:  ldr r3, [r2]
    // We are looking for Bit 0 (Command Done) or Bit 15 (General Error)
    tst r3, r1      
    beq 2b                      // Keep waiting if neither bit is set

    // -------------------------------------------------------------
    // 6. Error Checking & Cleanup
    // -------------------------------------------------------------
    tst r3, #(1 << 15)          // Did the Error bit trip?
    bne .cmd_error

    // Success: Clear the CMD_DONE bit by writing 1 to it
    mov r3, #1
    str r3, [r2]
    mov r0, #0                  // Return 0
    pop {pc}

.cmd_error:
    push {r0-r3}
    ldr r0, =msg_cmd_err
    bl uart_puts

    // Read and print the exact EMMC_INTERRUPT error bits
    ldr r2, =EMMC_INTERRUPT
    ldr r0, [r2]
    bl print_hex_error

    // Clear command line and data line state machines (SRST_CMD & SRST_DAT)
    ldr r0, =EMMC_CONTROL1
    ldr r1, [r0]
    orr r1, r1, #(3 << 25)      // Bit 25 is CMD_RESET, Bit 26 is DAT_RESET
    str r1, [r0]
1:  ldr r1, [r0]
    tst r1, #(3 << 25)
    bne 1b

    pop {r0-r3}

    // Hardware failure (e.g., CRC error, timeout)
    ldr r3, =0xFFFF0000         // Clear all error bits in the upper half-word
    str r3, [r2]
    mov r0, #-1                 // Return -1
    pop {pc}



    // SD Command Indices and CMDTM Configuration
// CMDTM Format for BCM2835: (Command Index << 24) | Response Type
.equ CMD0_CMDTM,     0x00000000 // GO_IDLE_STATE (No response)
.equ CMD8_CMDTM,     0x08020000 // SEND_IF_COND (48-bit response)
.equ CMD55_CMDTM,    0x37020000 // APP_CMD (48-bit response)
.equ ACMD41_CMDTM,   0x29020000 // SD_SEND_OP_COND (48-bit response)
.equ CMD2_CMDTM,     0x02090000 // ALL_SEND_CID (136-bit response)
.equ CMD3_CMDTM,     0x03020000 // SEND_RELATIVE_ADDR (48-bit response)

// -------------------------------------------------------------
// Initialize the SD Card Microcontroller
// -------------------------------------------------------------
.globl sd_card_init
sd_card_init:
    push {lr}

    // Force 74+ clocks by sending a dummy CMD0 and waiting.
    // The Arasan controller might not physically toggle the CLK pin until 
    // an actual transmission is requested.
    ldr r0, =CMD0_CMDTM
    mov r1, #0
    bl sd_send_command
    
    // Give the card time to process the physical hardware reset
    ldr r0, =1000000 
    bl delay

    ldr r0, =msg_cmd0
    bl uart_puts
    // 1. Send the real CMD0: Reset the card
    ldr r0, =CMD0_CMDTM
    mov r1, #0
    bl sd_send_command
    cmp r0, #0
    bne .fatal_sd_error

    // Give it slightly more time before probing voltage
    ldr r0, =10000
    bl delay

    ldr r0, =msg_cmd8
    bl uart_puts
    // 2. Send CMD8: Check voltage (Arg: 0x1AA for 3.3V)
    ldr r0, =CMD8_CMDTM
    ldr r1, =0x000001AA
    bl sd_send_command
    cmp r0, #0
    bne .fatal_sd_error

    ldr r0, =msg_acmd41
    bl uart_puts
    // 3. Power-Up Loop (CMD55 + ACMD41)
.power_loop:
    ldr r0, =CMD55_CMDTM
    mov r1, #0              // RCA is 0 during init
    bl sd_send_command
    cmp r0, #0
    bne .fatal_sd_error     // Break the infinite loop!

    ldr r0, =ACMD41_CMDTM
    ldr r1, =0x40FF0000     // Arg: Host supports High Capacity (SDHC/SDXC)
    bl sd_send_command
    cmp r0, #0
    bne .fatal_sd_error     // Break the infinite loop!

    // Read EMMC_RESP0 to check if the power-up is complete
    ldr r2, =0x20300010     // EMMC_RESP0 register
    ldr r3, [r2]
    tst r3, #(1 << 31)      // Bit 31 is the "Power Up Status" bit
    beq .power_loop         // If 0, card is still busy. Keep looping.

    ldr r0, =msg_cmd2
    bl uart_puts
    // 4. Send CMD2: Request Card ID (CID)
    ldr r0, =CMD2_CMDTM
    mov r1, #0
    bl sd_send_command

    ldr r0, =msg_cmd3
    bl uart_puts
    // 5. Send CMD3: Request Relative Card Address (RCA)
    ldr r0, =CMD3_CMDTM
    mov r1, #0
    bl sd_send_command

    // The RCA is stored in the upper 16 bits of RESP0.
    // We must save this RCA to a global variable to use in all future read/write commands!
    ldr r2, =0x20300010
    ldr r3, [r2]
    ldr r2, =sd_rca
    str r3, [r2]

    pop {pc}

.fatal_sd_error:
    ldr r0, =msg_fatal_err
    bl uart_puts
1:  wfe                     // Put the ARM core to sleep to save power
    b 1b

.section ".rodata"
msg_cmd0:   .asciz "[DBG] - Sending CMD0 (Reset)\r\n"
msg_cmd8:   .asciz "[DBG] - Sending CMD8 (Voltage)\r\n"
msg_acmd41: .asciz "[DBG] - Sending ACMD41 loop (Power-up)\r\n"
msg_cmd2:   .asciz "[DBG] - Sending CMD2 (CID)\r\n"
msg_cmd3:   .asciz "[DBG] - Sending CMD3 (RCA)\r\n"
msg_cmd_err:.asciz "[DBG] - COMMAND RETURNED AN ERROR (Bit 15 set)\r\n"
msg_send_start:   .asciz "      -> [sd_send] Started\r\n"
msg_send_idle:    .asciz "      -> [sd_send] CMD Line is Idle\r\n"
msg_send_trigger: .asciz "      -> [sd_send] Trigger Pulled. Spinning...\r\n"
msg_fatal_err:    .asciz "\r\n[FATAL] SD Card Hardware Failure. Halting OS.\r\n"
msg_mbox_pwr:     .asciz "[DBG] Mailbox: Power-cycling SD card...\r\n"
msg_mbox_clk:     .asciz "[DBG] Mailbox: Querying EMMC base clock...\r\n"
msg_mbox_err:     .asciz "\r\n[FATAL] GPU Mailbox communication failed. Halting.\r\n"
msg_no_card:      .asciz "\r\n[FATAL] No SD card detected by controller! STATUS:\r\n"
msg_card_ok:      .asciz "[DBG] Card detected in slot.\r\n"
msg_clk_fail:     .asciz "\r\n[FATAL] Internal clock failed to stabilize.\r\n"

.section ".data"
hex_str: .asciz " [HEX: 0x00000000]\r\n"
emmc_base_clock: .word 0

.section ".text"
.globl print_hex_error
print_hex_error:
    push {r0-r6, lr}
    mov r4, r0              // r4 contains the value
    ldr r5, =hex_str
    add r5, r5, #9          // point r5 to the first '0' after 0x

    mov r6, #8              // 8 digits to print
.hex_loop:
    mov r0, r4, lsr #28     // get highest 4 bits
    and r0, r0, #0xF        
    cmp r0, #9
    addls r0, r0, #'0'      // '0'-'9' (ls means lower or same as 9)
    addhi r0, r0, #55       // 'A'-'F' (hi means strictly greater than 9, 55 = 'A'-10 = 65-10 = 55)
    strb r0, [r5], #1       // store char and increment pointer
    mov r4, r4, lsl #4      // shift next digit up
    subs r6, r6, #1
    bne .hex_loop

    ldr r0, =hex_str
    bl uart_puts

    pop {r0-r6, pc}

