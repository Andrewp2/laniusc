"""CPU-only oracle for GPU CRT bridge bytes and the SysV process boundary."""

import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[3]
module = root / "shaders/codegen/lir/x86/crt_entry.slang"
source = module.read_text()
constants = {
    key: int(value)
    for key, value in re.findall(r"static const uint (\w+) = (\d+)u;", source)
}
record = re.search(r"crt_entry_bytes\[(\d+)\] = \{(.*?)\};", source, re.S)
assert record is not None
literal = bytes(int(value, 0) for value in re.findall(r"(0x[0-9a-f]+|\d+)u", record[2]))
assert len(literal) == int(record[1]) == constants["X86_CRT_ENTRY_BYTES"]
call_offset = constants["X86_CRT_ENTRY_CALL_OFFSET"]
assert literal[call_offset:call_offset + 5] == b"\xe8\0\0\0\0"

with tempfile.TemporaryDirectory(prefix="laniusc_crt_entry_") as directory:
    directory = pathlib.Path(directory)
    obj = directory / "bridge.o"
    binary = directory / "bridge.bin"
    subprocess.run(["as", "--64", "-o", obj, module.with_suffix(".s")], check=True, timeout=10)
    subprocess.run(["objcopy", "-O", "binary", "-j", ".text.crt_entry_bytes", obj, binary], check=True, timeout=10)
    assert binary.read_bytes() == literal, "CRT table differs from reviewed assembly"
    symbols = subprocess.run(["nm", "-n", obj], check=True, capture_output=True, text=True, timeout=10).stdout
    addresses = {name: int(address, 16) for address, _, name in (line.split() for line in symbols.splitlines())}
    assert addresses["crt_entry_call"] == call_offset
    assert addresses["crt_entry_end"] == len(literal)

    # Language main follows the literal bridge in this host fixture. The GPU
    # computes the same relative displacement from its checked artifact layout.
    patched = bytearray(literal)
    patched[call_offset + 1:call_offset + 5] = (len(literal) - call_offset - 5).to_bytes(4, "little", signed=True)
    binary.write_bytes(patched)
    assembly = directory / "probe.s"
    assembly.write_text(r'''
.intel_syntax noprefix
.text
.globl crt_bridge
crt_bridge:
.incbin "bridge.bin"
language_main:
    mov rdi, r15
    mov rsi, rsp
    sub rsp, 8
    call validate_context
    add rsp, 8
    ret
.globl probe_bridge
probe_bridge:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov ebp, 0x11223344
    mov ebx, 0x22334455
    mov r12d, 0x33445566
    mov r13d, 0x44556677
    mov r14d, 0x55667788
    mov r15d, 0x66778899
    call crt_bridge
    mov dword ptr [rsp], eax
    cmp rbp, 0x11223344
    jne .Lprobe_bad
    cmp rbx, 0x22334455
    jne .Lprobe_bad
    cmp r12, 0x33445566
    jne .Lprobe_bad
    cmp r13, 0x44556677
    jne .Lprobe_bad
    cmp r14, 0x55667788
    jne .Lprobe_bad
    cmp r15, 0x66778899
    jne .Lprobe_bad
    mov eax, dword ptr [rsp]
    jmp .Lprobe_restore
.Lprobe_bad:
    mov eax, 1000
.Lprobe_restore:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.section .note.GNU-stack,"",@progbits
''')
    harness = directory / "probe.c"
    harness.write_text(r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>

extern int probe_bridge(int argc, char **argv, char **envp);
static int expected_argc, expected_status, calls;
static size_t expected_envc;
static char **expected_argv, **expected_envp;
static uintptr_t *context;

int validate_context(uintptr_t *words, uintptr_t entry_rsp) {
    assert((entry_rsp & 15) == 8);
    assert(words[0] == (uintptr_t)expected_argc);
    for (int i = 0; i < expected_argc; i++)
        assert(words[i + 1] == (uintptr_t)expected_argv[i]);
    assert(words[expected_argc + 1] == 0);
    for (size_t i = 0; i < expected_envc; i++)
        assert(words[expected_argc + 2 + i] == (uintptr_t)expected_envp[i]);
    assert(words[expected_argc + expected_envc + 2] == 0);
    context = words;
    calls++;
    return expected_status;
}

static void success(int argc, char **argv, char **envp, size_t envc, int status) {
    expected_argc = argc;
    expected_argv = argv;
    expected_envp = envp;
    expected_envc = envc;
    expected_status = status;
    int before = calls;
    assert(probe_bridge(argc, argv, envp) == status);
    assert(calls == before + 1);
    unsigned char residency;
    errno = 0;
    assert(mincore(context, 4096, &residency) == -1 && errno == ENOMEM);
}

static void failure(int argc, char **argv, char **envp) {
    int before = calls;
    assert(probe_bridge(argc, argv, envp) == 127);
    assert(calls == before);
}

int main(void) {
    // The poisoned word before argv prevents dependence on argv[-1] for argc.
    char *argv_storage[] = {(char *)(uintptr_t)0xdeadbeef, "program", "one", "", NULL};
    char *envp[] = {"A=one", "B=two", NULL};
    success(3, argv_storage + 1, envp, 2, 187);
    success(3, argv_storage + 1, NULL, 0, -23);
    success(0, NULL, NULL, 0, 0);
    failure(-1, NULL, NULL);
    failure(1048574, NULL, NULL);
    failure(1, NULL, NULL);
    // Exercise the shared argc+env limit exactly, and one entry beyond it.
    const size_t maximum_envc = 1048573;
    char **large_env = calloc(maximum_envc + 2, sizeof(char *));
    assert(large_env);
    for (size_t i = 0; i < maximum_envc; i++) large_env[i] = "X=Y";
    success(0, NULL, large_env, maximum_envc, 9);
    large_env[maximum_envc] = "X=Y";
    failure(0, NULL, large_env);
    free(large_env);
    return 0;
}
''')
    executable = directory / "probe"
    subprocess.run(["cc", "-no-pie", "-O2", "-Wall", "-Wextra", "-Werror", harness, assembly, "-o", executable], cwd=directory, check=True, timeout=20)
    subprocess.run([executable], check=True, timeout=10)

print("CRT bridge: assembly bytes, process vectors, stack alignment, register preservation, return status, cleanup and bounds passed")
