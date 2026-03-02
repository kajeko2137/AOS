// process1.S — Simple test process
// Tests memory allocation via SWI #2, writing, lazy allocation, and SWI #3.

.section ".text.process1"

.globl process1_entry
process1_entry:
    // 0. Test lazy allocation
    // Writing to 0x20000000 (512MB) will trigger data abort
    // Wait, let's pick somewhere in the middle of heap space
    ldr r0, =0x10000000     // 256MB mark
    ldr r1, =0xCAFEBABE
    str r1, [r0]            // This will trigger Data Abort!

    // If we get here, lazy allocation worked!
    ldr r2, [r0]            // Read it back
    cmp r1, r2
    bne .alloc_failed

    // 1. Request a new page
    mov r7, #2
    swi #0
    
    // r0 should now contain the address of the newly allocated page
    mov r4, r0              // Store the allocated page address in r4
    cmp r4, #0
    beq .alloc_failed
    
    // 2. Test writing to it
    ldr r1, =0xDEADBEEF
    str r1, [r4]            // Write to the new page

.alloc_failed:
    // 3. Count to 10
    mov r0, #0
    mov r1, #10

.loop:
    add r0, r0, #1
    cmp r0, r1
    blt .loop

    // 4. Free the allocated page (if any)
    cmp r4, #0
    beq .skip_free
    mov r0, r4              // Load the allocated page address back into r0
    mov r7, #3              // sys_free_page
    swi #0

.skip_free:
    // 5. Done - call sys_exit
    mov r0, #0
    mov r7, #1
    swi #0