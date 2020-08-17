<img src="/pics/Klessydra_Logo.png" width="400">

# KLESSYDRA-T03 INTRELEAVED MULTITHREADED PROCESSOR

Intro: The Klessydra processing core family is a set of processors featuring full compliance with RISC-V, and pin-to-pin compatible with the PULPino Riscy cores. Klessydra-T02 is a bare-metal 32-bit processor supporting the RV32I from the RISC-V ISA, and one instruction from the Atomic "A" extension.

Architecture: T02 is an interleaved multithreaded processor (Aka, barrel processor). It interleaves two hardware threads (harts). Each hart has it's own registerfile, CSR-unit, and program counter, and they communicate with each other via software interrupts.

Fencing role of the harts: The harts in our IMT archtiecture play an essential fencing role to avoid pipeline stalls. One role is to fence between registerfile RD & WR accesses, thus never having data-dependency pipeline stalls. The other is to fence between the execution and fetch stage, but since this core interleaves only two harts, we get 1 cycle penalty during a pipeline flush. A configuration like the T03 interleaves three harts and has zero pipeline flushing penalties.

<p align="center">
<img src="/pics/Klessydra-T02x.png" width="600">
</p>

A more advanced, and highly parametrizable version of the T02 is the T13 available at:

https://github.com/klessydra/T13x

# Merging T02x User Guide

This guide explains how one can download and install Pulpino, and it's 
modified version of the riscv-gnu toolchain. It also demonstrates
how to patch the offcial riscv-toolchain in order to add the klessydra 
extensions. And then it shows how you can easily merge the Klessydra-Core 
in the Pulpino project.

###########################################################################################
- Prerequisites as indicated by the pulpino group
	- ModelSim in reasonably recent version (we tested it with versions 10.2c)
	- CMake >= 2.8.0, versions greater than 3.1.0 recommended due to support for ninja
	- riscv-toolchain, there are two choices for getting the toolchain: 

  		1) RECOMENDED OPTION: Use the custom version of the RISC-V toolchain from ETH. 
  		The ETH versions supports all the ISA extensions that were incorporated 
	  	into the RI5CY core as well as the reduced base instruction set for zero-riscy.
	        " https://github.com/pulp-platform/ri5cy_gnu_toolchain.git "

		2) Or download the official RISC-V toolchain supported by Berkeley.
 	       	" https://github.com/riscv/riscv-gnu-toolchain "


	  	Please make sure you are using the newlib version of the toolchain.
	- python2 >= 2.6
	
###########################################################################################

- IF you already have pulpino and their own version of the riscv-toolchain, then skip ahead to step.4


PROCEDURE:
1.	Install the following packeges:
		
		sudo apt-get install git cmake python-yaml tcsh autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev

2.	Download and build the "ri5cy_gnu_toolchain"

		a) git clone https://github.com/pulp-platform/ri5cy_gnu_toolchain.git
		
		b) cd ri5cy_gnu_toolchain
		
		c) make ZERORISCY=1
		
	When the build is done, add the path **_<path_to_toolchain>/ri5cy_gnu_toolchain/install/bin_** to the environmental variables

3.	Download the PULPino suite:

		a) git clone https://github.com/pulp-platform/pulpino.git
		
		b) cd pulpino
		
		c) ./update-ips.py	


4.	If you want to run the klessydra specific tests, you have to download and patch the official riscv-toolchain, and then build it. Instructions for doing so are included in the README.md file
	inside the folder called toolchain_files.

5.	To merge the Klessydra core, and tests:

		a) git clone https://github.com/klessydra/T02x.git
		
		b) cd T02x
		
		c) ./runMErge.sh <pulpino_path>

6.	OPTIONAL: After merging is done, this is how you will be able to test Klessydra-t0-2th.
		-Open a terminal and navigate to "sw" folder inside pulpino and execute the following commands

		a) e.g. mkdir build
		
		b) cp cmake_configure.klessydra-t0-2th.gcc.sh build/
		
		c) cd build
		
		d) ./cmake_configure.klessydra-t0-2th.gcc.sh
		
		e) make vcompile

		For running Klessydra tests; the variable "USE_KLESSYDRA_TEST" in the shell file is set to '1' by default. You only need to build and run your test
		f) (e.g. make barrier_test.vsimc)
		
		For running a PULPino test, set the variable "USE_KLESSYDRA_TEST" inside the shell file to 0, and re-execute the shell file again, and then run
		g) (e.g. make testALU.vsimc)
			
	IT"S DONE!!!!!!

EXTRA:

7.	In order to run tests in Modelsim, go to the build folder and do the following:
		make nameofthetest.vsim (or .vsimc to run a test without modelsim GUI)
