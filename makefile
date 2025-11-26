all: boot-loader disk.img

boot-loader:
	@echo
	@echo ============== Build Boot Loader ==============
	@echo

	make -C boot-loader

	@echo
	@echo ============== Build Complete ==============
	@echo

disk.img: boot-loader/boot-loader.bin
	@echo
	@echo ============== Disk Image Build Start ==============
	@echo

	cp boot-loader/boot-loader.bin disk.img

	@echo
	@echo ============== All Build Complete ==============
	@echo

clean:
	make -C boot-loader clean
	rm -f disk.img
