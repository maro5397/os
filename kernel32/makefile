all: virtual-os.bin

virtual-os.bin: virtual-os.asm
	nasm -o virtual-os.bin virtual-os.asm

clean:
	rm -f virtual-os.bin