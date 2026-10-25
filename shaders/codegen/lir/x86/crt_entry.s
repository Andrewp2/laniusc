# Readable source for crt_entry.slang. Assemble with as --64 and extract
# .text.crt_entry_bytes. The GPU replaces only the four-byte call displacement.
#
# Linux x86_64/glibc calls this bridge as main(int argc, char **argv, char **envp).
# The private native runtime retains its initial-stack ABI in R15. Build that
# exact vector in bounded mmap storage, independently of libc's pointer layout.
# The mapping lives until language main returns. Failure returns status 127.
.intel_syntax noprefix
.section .text.crt_entry_bytes,"ax"
.globl crt_entry_start
crt_entry_start:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    # At most 1,048,576 native pointer words (8 MiB), including both sentinels
    # and the argc word. Check before pointer indexing or size multiplication.
    test edi, edi
    js .Lcrt_bad
    cmp edi, 1048573
    ja .Lcrt_bad
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    xor ebp, ebp
    test r12, r12
    jnz .Lcrt_env
    test ebx, ebx
    jnz .Lcrt_bad
.Lcrt_env:
    test r13, r13
    jz .Lcrt_counted
.Lcrt_count:
    lea eax, [rbx + rbp + 3]
    cmp eax, 1048576
    ja .Lcrt_bad
    cmp qword ptr [r13 + rbp*8], 0
    je .Lcrt_counted
    inc ebp
    jmp .Lcrt_count
.Lcrt_counted:
    lea r14, [rbx + rbp + 3]
    shl r14, 3
    xor edi, edi
    mov rsi, r14
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js .Lcrt_bad
    mov r15, rax
    mov qword ptr [r15], rbx
    lea rdi, [r15 + 8]
    mov rsi, r12
    mov ecx, ebx
    cld
    rep movsq
    mov qword ptr [rdi], 0
    add rdi, 8
    mov rsi, r13
    mov ecx, ebp
    rep movsq
    mov qword ptr [rdi], 0
.globl crt_entry_call
crt_entry_call:
    .byte 0xe8
    .long 0
    mov ebx, eax
    mov rdi, r15
    mov rsi, r14
    mov eax, 11
    syscall
    mov eax, ebx
    jmp .Lcrt_restore
.Lcrt_bad:
    mov eax, 127
.Lcrt_restore:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.globl crt_entry_end
crt_entry_end:
.section .note.GNU-stack,"",@progbits
