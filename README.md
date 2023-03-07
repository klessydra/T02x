<img src="/pics/Klessydra_Logo.png" width="400">

# KLESSYDRA-T02 INTRELEAVED MULTITHREADED PROCESSOR

Intro: The Klessydra processing core family is a set of processors featuring full compliance with RISC-V, and pin-to-pin compatible with the PULPino Riscy cores. Klessydra-T02 is a bare-metal 32-bit processor supporting the RV32I from the RISC-V ISA, and one instruction from the Atomic "A" extension.

Architecture: T02 is an interleaved multithreaded processor (Aka, barrel processor). It interleaves two hardware threads (harts). Each hart has it's own registerfile, CSR-unit, and program counter, and they communicate with each other via software interrupts.

Fencing role of the harts: The harts in our IMT archtiecture play an essential fencing role to avoid pipeline stalls. One role is to fence between registerfile RD & WR accesses, thus never having data-dependency pipeline stalls. The other is to fence between the execution and fetch stage, but since this core interleaves only two harts, we get 1 cycle penalty during a pipeline flush. A configuration like the T03 interleaves three harts and has zero pipeline flushing penalties.

PROCEDURE:

To use Klessydra-M, please download [PULPino-Klessydra](https://github.com/klessydra/pulpino-klessydra) , and follow the guide over there. 

- For more details about the Klessydra processing cores, please refer to the technincal manual in Docs
- For more details about the Klessydra runtime libraries, please refer to the software runtime manual in Docs

Hope you like it :D
