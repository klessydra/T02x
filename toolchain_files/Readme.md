Intro: 
Attached are the files used to build the riscv toolchain with the klessydra instruction extensions

1) Download the official riscv toolchain from: 

	git clone https://github.com/riscv/riscv-gnu-toolchain
   
2) Switch to the commit which has the compatible version with our patched files

	- cd riscv-gnu-toolchain
	- git checkout v20180629	

3) Update the submodules inside the riscv-gnu-toolchain

	 git submodule update --init --recursive

4) - replace the patched file riscv-binutils/riscv-opc.c in <path_to_toolchain>/riscv-gdb/opcode/
   - replace the patched file riscv-binutils/riscv-opc.h in <path_to_toolchain>/riscv-gdb/include/opcode/
   - replace the patched file riscv-gdb/riscv-opc.c in <path_to_toolchain>/riscv-binutils/opcode/
   - replace the patched file riscv-gdb/riscv-opc.h in <path_to_toolchain>/riscv-binutils/include/opcode/

5) Build the toolchain using the following commands
    
  - ./configure --prefix=/opt/riscv/ --with-arch=rv32ia --with-abi=ilp32
  -  make

6) After the build, in order to use both pulpino ri5cy toolchain and klessydra toolchain simultaneusly, execute the "make_links.sh" which creates symbolic links of the official pointers.
   -	copy the "make_links.sh" into <path_to_klessydra_toolchain>/bin 
   -	chmod +x make_links.sh
   -	./make_links.sh

7) Add the path of <klessydra_toolchain>/bin to environmental variables.

Now if you want to test the toolchain, execute the commands as such in a terminal: klessydra-unknown-elf-... (e.g. klessydra-unknown-elf-gcc -c file.c -o file.o)
