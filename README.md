# A6OS

A bare-metal operating system for the **Raspberry Pi 1 Model B**, written entirely in ARM assembly[cite: 11]. The project features physical page allocation, advanced ARMv6 Extended Page Table MMU initialization, process isolation across User/Supervisor modes, a functional software interrupt (SWI) system call dispatcher, and an O(1) Tiered Lottery Scheduler[cite: 11].

## Hardware Target

| Detail | Value |
|---|---|
| **Board** | Raspberry Pi 1 Model B[cite: 11] |
| **SoC** | Broadcom BCM2835[cite: 11] |
| **CPU** | ARM1176JZF-S (ARMv6)[cite: 11] |
| **RAM** | 512 MB[cite: 11] |
| **Kernel load address** | `0x8000`[cite: 11] |

## Core Features

- **Tiered Lottery Scheduler (TLS):** A custom O(1) scheduler driven by a 10ms system timer interrupt[cite: 11]. Manages processes across 4 priority tiers using a zero-copy pointer-swapping mechanism for downgrades (100ms) and array flattening for starvation prevention resets (1000ms)[cite: 11].
- **Physical Page Allocator:** Tracks exactly 131,072 4KB pages across 512MB of RAM using a byte array tracking map[cite: 11].
- **MMU & Virtual Memory:** Creates L1 coarse tables and initializes ARMv6 Extended Page Table format (SCTLR.XP enabled), mapping the kernel identity region and 512MB RAM physical translation through a higher-half offset (0x80000000+)[cite: 11].
- **Process Memory Isolation:** Maps separate 4KB virtual pages per process into L2 coarse tables, restricting User mode constraints[cite: 11]. The code is mapped at `0x00100000`, the heap at `0x00101000`, and the stack is dynamically allocated downwards from `0x00200000`[cite: 11].
- **System Calls (SWI Dispatcher):** A system call handler tracking software interrupt triggers[cite: 11]. Handlers preserve exception execution states and process registers, seamlessly returning control to user execution[cite: 11].
- **Lazy Memory Mapping & Allocation:** Seamlessly intercepts physical access to unused virtual heap boundaries via the kernel's Data Abort Exception handler, instantly provisioning requested memory pages invisibly to the application[cite: 11]. Processes can also ask for pages dynamically via system calls, using O(1) bump-allocation[cite: 11].
- **Hardware True RNG:** Initializes and reads the silicon BCM2835 True Random Number Generator once during boot to securely seed the software deterministic Xorshift PRNG used by the Lottery Scheduler[cite: 11].

## Boot Sequence

`ROM (SoC) → bootcode.bin → start.elf → kernel.img (A6OS)`[cite: 11]

On startup, the kernel maps CPU execution contexts, zeroes the `.bss` section, and initializes UART0 for basic serial output[cite: 11]. It then initializes the MMU, the TLS memory structures, and the True RNG seed[cite: 11]. Finally, it maps `process1` directly into the Tier 0 Scheduler ring buffer, enables the 10ms hardware timer interrupt, and enters the `system_idle` loop to bootstrap user execution[cite: 11].