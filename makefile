.PHONY: boot-loader kernel32

all: boot-loader kernel32 disk.img

boot-loader:
	@echo
	@echo ============== Build Boot Loader ==============
	@echo

	make -C boot-loader

	@echo
	@echo ============== Build Complete ==============
	@echo

kernel32:
	@echo
	@echo ============== Build 32bit Kernel ==============
	@echo

	make -C kernel32

	@echo
	@echo ============== Build Complete ==============
	@echo

disk.img: boot-loader kernel32
	@echo
	@echo ============== Disk Image Build Start ==============
	@echo

	cat boot-loader/boot-loader.bin kernel32/virtual-os.bin > disk.img

	@echo
	@echo ============== All Build Complete ==============
	@echo

clean:
	make -C boot-loader clean
	make -C kernel32 clean
	rm -f disk.img
