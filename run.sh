#!/bin/bash
qemu-system-x86_64 -m 64 -fda ./disk.img -rtc base=localtime -M pc
