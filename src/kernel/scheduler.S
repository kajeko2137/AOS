.section ".rodata"
msg_reschedule: .asciz "[DBG] Reschedule called, halting.\r\n"

.section ".text.scheduler"
.globl reschedule

reschedule:
    ldr r0, =msg_reschedule
    bl uart_puts
    b halt

