# Source for linux_syscall6_bytes in runtime_abi.slang. Assemble with
# `as --64`, then `objcopy -O binary -j .text` to regenerate the bytes.
# SysV input: RDI number, RSI pointer to six ascending 64-bit argument words.
# No validation/retry/errno translation. Return the kernel's RAX bit pattern.
# Only valid when the syscall returns on this same continuation and stack.
.intel_syntax noprefix
linux_syscall6:
    mov rax, rdi
    mov r11, rsi
    mov rdi, qword ptr [r11]
    mov rsi, qword ptr [r11 + 8]
    mov rdx, qword ptr [r11 + 16]
    mov r10, qword ptr [r11 + 24]
    mov r8, qword ptr [r11 + 32]
    mov r9, qword ptr [r11 + 40]
    syscall
    ret
