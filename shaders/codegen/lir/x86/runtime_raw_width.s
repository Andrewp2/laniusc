# Readable source for the width-sensitive arrays in runtime_abi.slang.
# Assemble with as --64; extract each .text.<array-name> section independently.
# Runtime names/indices/results remain unchanged. All returning paths preserve
# callee-saved registers, notably the original process stack in R15.
.intel_syntax noprefix
.section .text.stdout_bytes,"ax"
    mov rdx, rsi
    push rdi
    pop rsi
    mov edi, 1
    mov eax, 1
    syscall
    ret
.section .text.stderr_bytes,"ax"
    mov rdx, rsi
    push rdi
    pop rsi
    mov edi, 2
    mov eax, 1
    syscall
    ret
.section .text.stdin_bytes,"ax"
    mov rdx, rsi
    push rdi
    pop rsi
    xor edi, edi
    xor eax, eax
    syscall
    ret
.section .text.arg_read_bytes,"ax"
    test edi, edi
    js .Larg_bad
    cmp edi, dword ptr [r15]
    jae .Larg_bad
    mov r8, rsi
    mov r9, rdx
    mov eax, edi
    inc eax
    mov rsi, qword ptr [r15 + rax*8]
    xor eax, eax
.Larg_copy:
    cmp rax, r9
    jae .Larg_done
    cmp byte ptr [rsi + rax], 0
    je .Larg_done
    mov cl, byte ptr [rsi + rax]
    mov byte ptr [r8 + rax], cl
    inc eax
    jmp .Larg_copy
.Larg_done:
    ret
.Larg_bad:
    mov eax, -1
    ret
.section .text.alloc_bytes,"ax"
    test rdi, rdi
    jz .Lalloc_bad
    cmp rsi, 8
    ja .Lalloc_bad
    test rsi, rsi
    jz .Lalloc_bad
    lea rax, [rsi - 1]
    test rax, rsi
    jnz .Lalloc_bad
    mov rsi, rdi
    xor edi, edi
    mov edx, 3
    mov r10d, 0x62
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    jns .Lalloc_done
.Lalloc_bad:
    xor eax, eax
.Lalloc_done:
    ret
.section .text.realloc_bytes,"ax"
    test rdi, rdi
    jz .Lrealloc_bad
    test rsi, rsi
    jz .Lrealloc_bad
    test rdx, rdx
    jz .Lrealloc_bad
    cmp rcx, 8
    ja .Lrealloc_bad
    test rcx, rcx
    jz .Lrealloc_bad
    lea rax, [rcx - 1]
    test rax, rcx
    jnz .Lrealloc_bad
    mov r10d, 1
    mov eax, 25
    syscall
    test rax, rax
    jns .Lrealloc_done
.Lrealloc_bad:
    xor eax, eax
.Lrealloc_done:
    ret
.section .text.monotonic_read_bytes,"ax"
    cmp rsi, 16
    jb .Lmonotonic_bad
    push rdi
    pop rsi
    mov edi, 1
    mov eax, 228
    syscall
    ret
.Lmonotonic_bad:
    mov eax, -1
    ret
.section .text.system_read_bytes,"ax"
    cmp rsi, 16
    jb .Lsystem_bad
    push rdi
    pop rsi
    mov edi, 0
    mov eax, 228
    syscall
    ret
.Lsystem_bad:
    mov eax, -1
    ret
.section .text.var_key_read_bytes,"ax"
    mov r8, qword ptr [r15]
    lea r8, [r15 + r8*8 + 16]
    mov r9d, edi
    test r9d, r9d
    js .Lkey_bad
    mov r10, r8
.Lkey_entry:
    mov r11, qword ptr [r10]
    test r11, r11
    jz .Lkey_bad
    test r9d, r9d
    jz .Lkey_found
    add r10, 8
    dec r9d
    jmp .Lkey_entry
.Lkey_found:
    mov r10, rsi
    mov r9, rdx
    xor eax, eax
.Lkey_copy:
    test r9, r9
    jz .Lkey_done
    mov r8b, byte ptr [r11 + rax]
    test r8b, r8b
    jz .Lkey_done
    cmp r8b, '='
    je .Lkey_done
    mov byte ptr [r10 + rax], r8b
    inc eax
    dec r9
    jmp .Lkey_copy
.Lkey_done:
    ret
.Lkey_bad:
    mov eax, -1
    ret
.section .text.var_len_bytes,"ax"
    mov r10, rdi
    mov r9, rsi
    mov r8, qword ptr [r15]
    lea r8, [r15 + r8*8 + 16]
.Llen_entry:
    mov r11, qword ptr [r8]
    test r11, r11
    jz .Llen_bad
    xor eax, eax
.Llen_compare:
    cmp rax, r9
    jae .Llen_delimiter
    mov dl, byte ptr [r11 + rax]
    test dl, dl
    jz .Llen_next
    cmp dl, '='
    je .Llen_next
    cmp dl, byte ptr [r10 + rax]
    jne .Llen_next
    inc eax
    jmp .Llen_compare
.Llen_delimiter:
    cmp byte ptr [r11 + rax], '='
    jne .Llen_next
    lea r11, [r11 + rax + 1]
    xor eax, eax
.Llen_value:
    cmp byte ptr [r11 + rax], 0
    je .Llen_done
    inc eax
    jmp .Llen_value
.Llen_next:
    add r8, 8
    jmp .Llen_entry
.Llen_done:
    ret
.Llen_bad:
    mov eax, -1
    ret
.section .text.var_read_bytes,"ax"
    mov r10, rdi
    mov rdi, rdx
    mov r9, rsi
    mov r8, qword ptr [r15]
    lea r8, [r15 + r8*8 + 16]
.Lread_entry:
    mov r11, qword ptr [r8]
    test r11, r11
    jz .Lread_bad
    xor eax, eax
.Lread_compare:
    cmp rax, r9
    jae .Lread_delimiter
    mov dl, byte ptr [r11 + rax]
    test dl, dl
    jz .Lread_next
    cmp dl, '='
    je .Lread_next
    cmp dl, byte ptr [r10 + rax]
    jne .Lread_next
    inc eax
    jmp .Lread_compare
.Lread_delimiter:
    cmp byte ptr [r11 + rax], '='
    jne .Lread_next
    lea r11, [r11 + rax + 1]
    mov r10, rdi
    mov r9, rcx
    xor eax, eax
.Lread_copy:
    test r9, r9
    je .Lread_done
    mov dl, byte ptr [r11 + rax]
    test dl, dl
    je .Lread_done
    mov byte ptr [r10 + rax], dl
    inc eax
    dec r9
    jmp .Lread_copy
.Lread_next:
    add r8, 8
    jmp .Lread_entry
.Lread_done:
    ret
.Lread_bad:
    mov eax, -1
    ret
.section .text.current_dir_read_bytes,"ax"
    test rsi, rsi
    jz .Lcwd_bad
    mov eax, 79
    syscall
    test rax, rax
    js .Lcwd_bad
    dec eax
.Lcwd_done:
    ret
.Lcwd_bad:
    mov eax, -1
    ret
.section .note.GNU-stack,"",@progbits
