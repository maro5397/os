# REIN OS

x86_64 아키텍처를 대상으로, OS의 부팅과 동작 원리를 직접 구현하며 공부하기 위한 토이 OS 프로젝트입니다.
BIOS가 부트로더를 메모리에 올리는 순간부터, 16비트 → 32비트(보호 모드) → 64비트(IA-32e/롱 모드)로 단계적으로 전환하고,
GDT/IDT/페이징을 직접 세팅한 뒤 키보드·타이머·RTC 같은 하드웨어와 통신하는 대화형 셸까지 동작하는 전 과정을 담고 있습니다.

> 학습 목적의 프로젝트이므로, 각 단계가 "왜 필요한지"와 "어떤 하드웨어 자원을 건드리는지"를 코드와 함께 설명하는 데 초점을 두었습니다.

---

## 디렉터리 구조

| 경로 | 역할 |
|------|------|
| [boot-loader/](boot-loader/) | BIOS가 가장 먼저 실행하는 512바이트 부트섹터 (16비트 리얼 모드) |
| [kernel32/](kernel32/) | 보호 모드(32비트) 진입 → 64비트 환경 준비(메모리 검사, 페이지 테이블, CPU 확인) |
| [kernel64/](kernel64/) | IA-32e(64비트) 커널 본체 — GDT/IDT/TSS, 인터럽트, 디바이스 드라이버, 콘솔 셸 |
| [utility/image-maker/](utility/image-maker/) | 세 바이너리를 하나의 부팅 가능한 디스크 이미지로 합치는 도구 |
| [makefile](makefile) | 전체 빌드 오케스트레이션 |
| [run.sh](run.sh) | QEMU 실행 스크립트 |

---

## 빌드 & 실행

### 요구 사항
- `nasm` (어셈블러)
- `gcc` (크로스 컴파일 가능한 x86_64 타깃)
- `qemu-system-x86_64` (에뮬레이터)

### 빌드
```bash
make            # boot-loader + kernel32 + kernel64 빌드 후 disk.img 생성
make clean      # 산출물 제거
```

빌드 흐름:
1. `boot-loader/boot-loader.bin` — 부트섹터(512바이트, 0x55AA 시그니처 포함)
2. `kernel32/kernel32.bin` — 보호 모드 커널
3. `kernel64/kernel64.bin` — 64비트 커널
4. `image-maker`가 위 셋을 순서대로 이어붙여 [disk.img](disk.img) 생성 (1.44MB 플로피 크기로 패딩 → 올바른 CHS 지오메트리 보장)

### 실행
```bash
./run.sh
# 또는
qemu-system-x86_64 -m 64 -fda ./disk.img -rtc base=localtime -M pc -vga std
```
> `-m 64` : 최소 64MB 메모리 필요 (커널이 직접 메모리 크기를 검사함)
> `-fda`  : disk.img를 플로피 디스크 A로 연결 (부트로더가 INT 0x13으로 읽는 대상)

---

## 부팅 과정 (단계별)

OS가 켜지고 셸이 뜨기까지의 전체 흐름입니다. 각 단계는 실제 소스 파일과 연결되어 있습니다.

### 0. BIOS → 부트섹터
- 전원이 켜지면 BIOS가 POST를 끝내고, 디스크 첫 번째 섹터(512바이트)를 물리 주소 `0x7C00`에 적재한 뒤 점프합니다.
- 마지막 2바이트가 `0x55 0xAA`여야 BIOS가 "부팅 가능"으로 인식합니다.

### 1. 부트로더 — 16비트 리얼 모드
[boot-loader/boot-loader.asm](boot-loader/boot-loader.asm)
- `jmp 0x07C0:START` — BIOS 변종(0000:7C00 vs 07C0:0000) 대응을 위한 far jump로 CS:IP를 확정.
- 비디오 메모리(`0xB800`) 세그먼트를 직접 써서 화면을 지우고 부팅 메시지 출력.
- **INT 0x13**(BIOS 디스크 서비스)으로 디스크의 나머지 섹터(커널 이미지)를 `0x10000`부터 읽어들임.
  - CHS(Cylinder-Head-Sector) 주소를 직접 증가시키며 트랙/헤드/섹터를 순회 (플로피: 섹터 1~18, 헤드 0~1).
- 적재 완료 후 `jmp 0x1000:0x0000` → 32비트 커널 진입점으로 점프.

### 2. 32비트 커널 진입 — 리얼 모드 → 보호 모드
[kernel32/src/entrypoint.s](kernel32/src/entrypoint.s)
- **A20 게이트 활성화**: 1MB 이상 메모리를 접근하기 위해 21번째 주소선을 켬 (BIOS INT 0x15 시도 → 실패 시 시스템 컨트롤 포트 `0x92` 직접 제어).
- `cli`로 인터럽트 차단 후 **임시 GDT 로드**(`lgdt`).
  - GDT에 NULL / 64비트 코드·데이터 / 32비트 코드·데이터 디스크립터 정의.
- `cr0`의 PE 비트를 세팅 → **보호 모드 진입**, `jmp dword 0x18:...`로 32비트 코드 세그먼트로 점프.

### 3. 32비트 C 커널 — 64비트 환경 준비
[kernel32/src/main.c](kernel32/src/main.c)
1. **최소 메모리 검사** (`kIsMemoryEnough`) — 1MB~64MB 영역에 매직값을 써보며 64MB 이상인지 확인.
2. **커널 영역 초기화** (`kInitializeKernel64Area`) — `0x100000`~`0x600000`을 0으로 클리어.
3. **페이지 테이블 생성** ([kernel32/src/page.c](kernel32/src/page.c)) — 64비트 페이징에 필요한 4단계 테이블 구성:
   - PML4(`0x100000`) → PDPT(`0x101000`) → PD(`0x102000`~)
   - 2MB 페이지(`PS` 플래그)로 물리 메모리를 1:1 아이덴티티 매핑.
4. **CPUID로 64비트 지원 확인** ([kernel32/src/mode-switch.asm](kernel32/src/mode-switch.asm) `kReadCPUID`) — CPU 벤더 문자열 출력, `0x80000001`의 EDX 29번 비트로 롱 모드 지원 판별.
5. **64비트 커널 복사** (`kCopyKernel64ImageTo2Mbyte`) — kernel64 이미지를 물리 주소 `0x200000`(2MB)로 이동.
6. **IA-32e 모드 전환** (`kSwitchAndExecute64bitKernel`):
   - `cr4`의 PAE 비트 ON → `cr3`에 PML4 주소 적재 → `IA32_EFER.LME` 비트 ON → `cr0`의 PG 비트 ON.
   - `jmp 0x08:0x200000`으로 64비트 커널로 점프.

### 4. 64비트 커널 — IA-32e 롱 모드
[kernel64/src/entrypoint.s](kernel64/src/entrypoint.s) → [kernel64/src/main.c](kernel64/src/main.c)
1. 세그먼트 레지스터와 스택(`0x6FFF8`) 설정 후 `main()` 호출.
2. **콘솔 초기화** ([console.c](kernel64/src/console.c)) — VGA 텍스트 버퍼 기반 출력/커서 관리.
3. **GDT/TSS 재구성** ([descriptor.c](kernel64/src/descriptor.c)) — 64비트용 정식 GDT(`0x142000`)와 TSS 세그먼트 로드(`kLoadGDTR`, `kLoadTR`).
4. **IDT 초기화** — 인터럽트 디스크립터 테이블 구성 및 로드(`kLoadIDTR`). 예외(0~31)와 하드웨어 인터럽트 핸들러 등록.
5. **RAM 크기 측정** (`kCheckTotalRAMSize`).
6. **키보드 활성화 & 키 입력 큐 초기화** ([keyboard.c](kernel64/src/keyboard.c)).
7. **PIC 초기화 및 인터럽트 허용** ([pic.c](kernel64/src/pic.c)) — IRQ 리매핑 후 `kEnableInterrupt()`(`sti`).
8. **콘솔 셸 시작** (`kStartConsoleShell`) — 사용자 입력 대기 루프 진입.

```
BIOS → [0x7C00] 부트섹터(16bit)
            │  INT 0x13으로 커널 적재
            ▼
       [0x10000] kernel32 (16bit→32bit 보호 모드)
            │  A20, GDT, 페이징, CPUID, IA-32e 전환
            ▼
       [0x200000] kernel64 (64bit 롱 모드)
            │  GDT/IDT/TSS, PIC, 디바이스 드라이버
            ▼
        REIN64> _   (콘솔 셸)
```

---

## 메모리 맵 (물리 주소)

| 주소 | 용도 |
|------|------|
| `0x7C00` | BIOS가 부트섹터를 적재하는 위치 |
| `0xB8000` | VGA 텍스트 모드 비디오 메모리 (80×25, 문자+속성) |
| `0x10000` | 부트로더가 커널 이미지를 적재하는 위치 (kernel32 진입점) |
| `0x100000` (1MB) | PML4 페이지 테이블 |
| `0x101000` | PDPT |
| `0x102000` ~ | PD (2MB 페이지 매핑) |
| `0x142000` | 64비트 GDTR / GDT / TSS / IDTR / IDT |
| `0x200000` (2MB) | IA-32e 64비트 커널 본체 |
| `0x6FFF8` | 64비트 커널 초기 스택 |
| `0x700000` | IST (Interrupt Stack Table) 영역 |

---

## 다른 디바이스와 통신하는 방법

이 OS가 하드웨어와 대화하는 모든 통로는 결국 **포트 I/O** (`in`/`out` 명령)와 **인터럽트** 두 가지로 귀결됩니다.
어셈블리 래퍼는 [assembly-utility.h](kernel64/src/assembly-utility.h) / [assembly-utility.asm](kernel64/src/assembly-utility.asm)에 있습니다.

```c
BYTE kInPortByte(WORD wPort);            // 포트에서 1바이트 읽기 (in)
void kOutPortByte(WORD wPort, BYTE bData); // 포트로 1바이트 쓰기 (out)
```

### 1. 인터럽트 처리 흐름
하드웨어가 신호를 보내면 다음 경로로 처리됩니다:

```
디바이스 → PIC(8259) → CPU → IDT의 해당 벡터 → ISR 스텁(어셈블리) → C 핸들러 → EOI 전송
```

- **PIC (8259 인터럽트 컨트롤러)** [pic.c](kernel64/src/pic.c) / [pic.h](kernel64/src/pic.h)
  - 마스터 포트 `0x20/0x21`, 슬레이브 포트 `0xA0/0xA1`.
  - 기본 IRQ 0~15가 CPU 예외(0~31)와 겹치므로 시작 벡터를 `0x20`으로 **리매핑**.
  - `kMaskPICInterrupt`로 특정 IRQ만 허용, 처리 후 `kSendEOIToPIC`로 EOI(End Of Interrupt) 전송.
- **ISR 스텁** [isr.asm](kernel64/src/isr.asm) — 레지스터 컨텍스트 저장/복원(`KSAVECONTEXT`/`KLOADCONTEXT`) 후 C 핸들러 호출.
- **C 핸들러** [interrupt-handler.c](kernel64/src/interrupt-handler.c)
  - `kCommonExceptionHandler` — CPU 예외 발생 시 벡터 번호를 화면에 찍고 정지.
  - `kCommonInterruptHandler` — 등록되지 않은 하드웨어 인터럽트 공통 처리.
  - `kKeyboardHandler` — 키보드 IRQ 전용 처리.

### 2. 키보드 (IRQ 1) [keyboard.c](kernel64/src/keyboard.c)
- 키를 누르면 키보드 컨트롤러(8042)가 IRQ 1을 발생 → `kKeyboardHandler` 실행.
- 핸들러는 출력 버퍼에서 **스캔 코드**를 읽어(`kGetKeyboardScanCode`) ASCII로 변환 후 **키 큐**에 적재.
- 셸은 `kGetCh()`로 큐에서 키를 꺼내 사용 → 인터럽트(생산자)와 셸 루프(소비자)를 큐로 분리.
- Shift/Caps/Num/Scroll Lock 상태 추적 및 LED 제어(`kChangeKeyboardLED`), A20 게이트·리부트도 키보드 컨트롤러를 통해 수행.

### 3. PIT — 프로그래머블 인터벌 타이머 (IRQ 0) [pit.c](kernel64/src/pit.c) / [pit.h](kernel64/src/pit.h)
- 제어 포트 `0x43`, 카운터0 포트 `0x40`. 기준 주파수 `1193182 Hz`.
- `kInitializePIT`로 주기/단발 모드 설정. `MSTOCOUNT(ms)` 매크로로 밀리초 → 카운터값 변환.
- `kWaitUsingDirectPIT` — 카운터를 폴링하며 정밀한 시간 지연 구현 (`sleep`, `cpuspeed` 명령에서 사용).

### 4. RTC — 실시간 클록 / CMOS [rtc.c](kernel64/src/rtc.c)
- CMOS 주소 포트로 레지스터 번호를 쓰고(`out`), 데이터 포트로 값을 읽음(`in`).
- 시/분/초, 연/월/일/요일을 **BCD → 바이너리**로 변환하여 반환 (`date` 명령).

### 5. VGA 텍스트 출력 [console.c](kernel64/src/console.c)
- `0xB8000` 메모리에 `[문자, 속성]` 2바이트 쌍을 직접 써서 80×25 화면에 출력 (메모리 맵드 I/O).

---

## 콘솔 셸 명령어

부팅이 끝나면 `REIN64>` 프롬프트가 뜨고, 아래 명령을 입력할 수 있습니다.
명령 테이블은 [console-shell.c](kernel64/src/console-shell.c)의 `gs_vstCommandTable`에 정의되어 있습니다.

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `help` | 사용 가능한 명령어 목록 출력 | `help` |
| `clear` | 화면 지우기 | `clear` |
| `free` | 전체 RAM 크기 출력 | `free` |
| `printf` | 문자열 → 10진수/16진수 변환 테스트 | `printf 0x1234 1024` |
| `reboot` | 시스템 종료 후 재부팅 | `reboot` |
| `settimer` | PIT 인터벌 타이머 설정 (ms, 주기 여부) | `settimer 10 1` |
| `sleep` | 지정 시간(ms) 동안 대기 (PIT 사용) | `sleep 100` |
| `lscpu` | Time Stamp Counter(TSC) 값 출력 | `lscpu` |
| `cpuspeed` | TSC + PIT로 현재 CPU 클록 측정 | `cpuspeed` |
| `date` | RTC에서 현재 날짜/시간 읽어 출력 | `date` |

### 새 명령어 추가하는 법
1. [console-shell.c](kernel64/src/console-shell.c)에 `void kMyCommand(const char* pcParameterBuffer)` 형태의 함수 작성.
2. `gs_vstCommandTable` 배열에 `{"명령어", "설명", kMyCommand}` 항목 추가.
3. [console-shell.h](kernel64/src/console-shell.h)에 함수 프로토타입 선언.
4. 파라미터가 필요하면 `kInitializeParameter` / `kGetNextParameter`로 토큰 단위 파싱.

---

## 참고: C 코드에서 생성된 어셈블리 확인
구현 의도와 실제 기계어를 비교하며 공부할 때 유용합니다.
```bash
gcc -c test.c -o test.o -O2
objdump -d test.o
```

## 라이선스
[LICENSE](LICENSE) 참고.
