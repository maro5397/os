# os
60일 os 개발 프로젝트

# QEMU instruction
```bash
qemu-system-x86_64 -m 64 -fda ./disk.img -rtc base=localtime -M pc -vga std
```

# Extract assembly from C
```bash
gcc -c test.c -o test.o -O2
objdump -d test.o
```
