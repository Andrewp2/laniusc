# Source for assert_bytes and trap_bytes in runtime_abi.slang. Assemble with
# `as --64`, then `objcopy -O binary -j .text` to regenerate the bytes. The
# 32 bytes of linux_syscall6_bytes lie between the two arrays.
#
# Each trap writes one line to standard error and ends the process. A guard
# in generated code jumps to trap_bounds or trap_shift on failure. A failed
# division guard loads EDI with 103 (zero divisor) or 104 (the quotient does
# not fit) and jumps to trap_divide. exit_group ends every thread.
.intel_syntax noprefix
# Called with the asserted bool in EDI. A true value returns to the caller
# without changing its state. A false value reports and raises SIGILL.
assert:
    test edi, edi
    jz trap_assert
    ret
    int3
    int3
.skip 32, 0x90
trap_bounds:
    mov edi, 101
    lea rsi, [rip + message_bounds]
    mov edx, offset message_shift - message_bounds
    jmp report
trap_shift:
    mov edi, 102
    lea rsi, [rip + message_shift]
    mov edx, offset message_zero - message_shift
    jmp report
trap_divide:
    lea rsi, [rip + message_zero]
    mov edx, offset message_overflow - message_zero
    cmp edi, 103
    je report
    lea rsi, [rip + message_overflow]
    mov edx, offset message_assert - message_overflow
report:
    mov ebx, edi
    mov eax, 1
    mov edi, 2
    syscall
    mov edi, ebx
    mov eax, 231
    syscall
trap_assert:
    lea rsi, [rip + message_assert]
    mov edx, offset message_end - message_assert
    mov eax, 1
    mov edi, 2
    syscall
    ud2
message_bounds:
    .ascii "lanius: index out of range\n"
message_shift:
    .ascii "lanius: shift amount out of range\n"
message_zero:
    .ascii "lanius: division by zero\n"
message_overflow:
    .ascii "lanius: division overflow\n"
message_assert:
    .ascii "lanius: assertion failed\n"
message_end:
