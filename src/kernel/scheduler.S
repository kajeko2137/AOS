.section ".text.scheduler"
.globl context_switch

context_switch:
    // Save current process state
    // We assume that the kernel passes adress of current processes L1 table in r0
    // and the next process L1 table in r1
    
    
