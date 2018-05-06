# T02x

Intro: This guide explains how one can download and install Pulpino, and 
it's modified version of the riscv-gnu toolchain. And then it shows how 
you can easily merge the Klessydra-Core in the Pulpino project.

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

- IF you already have pulpino and their toolchain, than skip ahead to step.4


PROCEDURE:
1.	Install the following packeges:
		sudo apt-get install git cmake tcsh python-yaml tcsh autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev

2.	Download the toolchain, execute the following commands in the folder where you want to download the pulpino version of the riscv-gnu toolchain

		a) git clone https://github.com/pulp-platform/ri5cy-gnu-toolchain.git
		
		b) cd ri5cy-gnu-toolchain
		
		c) make ZERORISCY=1
		
	at the end of compilation, add the path <path_to_toolchain>/ri5cy_gnu_toolchain/install/bin to the environmental variables

3.	Download PULPino suite:

		a) git clone https://github.com/pulp-platform/pulpino.git
		
		b) cd pulpino
		
		c) ./update-ips.py	
	
4.	To merge the Klessydra core:

		a) git clone https://github.com/klessydra/T02x.git
		
		b) cd T02x
		
		c) ./runMErge.sh <pulpino_path>

5.	OPTIONAL: After merging is done, this is how you will be able to test Klessydra-t0-2th.
		-Open the terminal and navigate to "sw" folder inside pulpino and execute the following commands

		a) e.g. mkdir build
		
		b) cp cmake_configure.klessydra-t0-2th.gcc.sh build/
		
		c) cd build
		
		d) ./cmake_configure.klessydra-t0-2th.gcc.sh
		
		e) make vcompile
		
		EXAMPLE TEST:
		f) make testALU.vsimc
			
	IT"S DONE!!!!!!

	Extra options: You can modify the cmake-configure file:
	for example, if you want to run zero-riscy without multiplication extensions change the variable "ZERO_RV32M" from '1' to '0' inside cmake_configure.zeroriscy.gcc.sh .
	save file and run

6.	In order to run tests in Modelsim, go to the build folder and do the following:
		make nameofthetest.vsim (or .vsimc to run a test without modelsim GUI)

7.	The list of the tests that passed on Klessydra are available in the file SIMUL_TEST_REULTS.pdf
