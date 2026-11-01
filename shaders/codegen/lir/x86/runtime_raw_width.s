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
# alloc(size RDI, align RSI), dealloc(ptr RDI, size RSI, align RDX) and
# realloc(ptr RDI, old RSI, new RDX, align RCX): one array, so the three
# entries share local branches. DEALLOC/REALLOC offsets are alloc_dealloc and
# alloc_realloc inside it.
#
# Blocks of 1..32768 bytes come from power-of-two classes (16 B .. 32 KiB)
# carved from 1 MiB arenas, with one free list per class; freed blocks are
# reused, never unmapped. Larger blocks are one mmap each, freed by munmap and
# resized by mremap. Callers pass the allocation's size to dealloc/realloc,
# so no block carries a header. A reused block is zeroed up to its size, so
# every allocation reads as zero, as a fresh mapping does.
#
# The pool state is one MAP_32BIT page: class heads at 0..96, the arena
# cursor at 96 and its end at 104. Its address lives in the otherwise unused
# upper half of the argc word at [R15 + 4] (argc readers load 32 bits):
# 0 = not decided yet, 1 = direct mode, else the state page. The first small
# allocation decides. LANIUS_ALLOC=mmap in the environment, or a failed state
# mapping, selects direct mode: every allocation is its own mmap and every
# free a munmap, exactly as before pooling (trace-based tests rely on it).
# Not thread-safe: Lanius workers are forked processes.
alloc_entry:
    test rdi, rdi
    jz .Lalloc_null
    cmp rsi, 8
    ja .Lalloc_null
    test rsi, rsi
    jz .Lalloc_null
    lea rax, [rsi - 1]
    test rax, rsi
    jnz .Lalloc_null
    cmp rdi, 32768
    ja .Lalloc_direct
    mov eax, dword ptr [r15 + 4]
    cmp eax, 1
    je .Lalloc_direct
    jb .Lalloc_init
.Lalloc_pool:
    # RCX = log2(class) - 1 for classes 16 .. 32768; RDX = its list head.
    lea rcx, [rdi - 1]
    or rcx, 15
    bsr rcx, rcx
    lea rdx, [rax + rcx*8 - 24]
    mov rsi, qword ptr [rdx]
    test rsi, rsi
    jz .Lalloc_bump
    mov r8, qword ptr [rsi]
    mov qword ptr [rdx], r8
    lea rcx, [rdi + 7]
    shr rcx, 3
    mov rdi, rsi
    xor eax, eax
    rep stosq
    mov rax, rsi
    ret
.Lalloc_bump:
    mov edx, 2
    shl edx, cl
    mov rsi, qword ptr [rax + 96]
    lea r8, [rsi + rdx]
    cmp r8, qword ptr [rax + 104]
    ja .Lalloc_arena
    mov qword ptr [rax + 96], r8
    mov rax, rsi
    ret
.Lalloc_arena:
    # A fresh 1 MiB arena; the rest of the old one is abandoned.
    push rax
    push rdx
    mov edi, 1048576
    call .Lalloc_direct
    pop rdx
    pop rcx
    test rax, rax
    jz .Lalloc_arena_done
    lea rsi, [rax + rdx]
    mov qword ptr [rcx + 96], rsi
    lea rsi, [rax + 1048576]
    mov qword ptr [rcx + 104], rsi
.Lalloc_arena_done:
    ret
.Lalloc_init:
    mov r8d, dword ptr [r15]
    lea r8, [r15 + r8*8 + 16]
.Lalloc_env:
    mov r9, qword ptr [r8]
    test r9, r9
    jz .Lalloc_state
    add r8, 8
    lea r10, [rip + .Lalloc_key]
.Lalloc_key_byte:
    mov al, byte ptr [r10]
    cmp al, byte ptr [r9]
    jne .Lalloc_env
    inc r9
    inc r10
    test al, al
    jnz .Lalloc_key_byte
    jmp .Lalloc_mark_direct
.Lalloc_state:
    push rdi
    xor edi, edi
    mov esi, 4096
    mov edx, 3
    mov r10d, 0x62
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    pop rdi
    test rax, rax
    js .Lalloc_mark_direct
    mov dword ptr [r15 + 4], eax
    jmp .Lalloc_pool
.Lalloc_mark_direct:
    mov dword ptr [r15 + 4], 1
    jmp .Lalloc_direct
.Lalloc_null:
    xor eax, eax
    ret
.Lalloc_direct:
    # The historical allocation/deallocation pair, byte for byte: one private
    # anonymous mapping per request, null on failure, then munmap.
    mov rsi, rdi
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    jns .Lalloc_direct_done
    xor eax, eax
.Lalloc_direct_done:
    ret
.Lalloc_munmap:
    mov eax, 11
    syscall
    ret
alloc_dealloc:
    lea rcx, [rsi - 1]
    cmp rcx, 32767
    ja .Lalloc_munmap
    mov eax, dword ptr [r15 + 4]
    cmp eax, 1
    jbe .Lalloc_munmap
    test rdi, rdi
    jz .Lalloc_free_done
    or rcx, 15
    bsr rcx, rcx
    lea rdx, [rax + rcx*8 - 24]
    mov rcx, qword ptr [rdx]
    mov qword ptr [rdi], rcx
    mov qword ptr [rdx], rdi
.Lalloc_free_done:
    ret
alloc_realloc:
    test rdi, rdi
    jz .Lalloc_null
    test rsi, rsi
    jz .Lalloc_null
    test rdx, rdx
    jz .Lalloc_null
    cmp rcx, 8
    ja .Lalloc_null
    test rcx, rcx
    jz .Lalloc_null
    lea rax, [rcx - 1]
    test rax, rcx
    jnz .Lalloc_null
    mov eax, dword ptr [r15 + 4]
    cmp eax, 1
    jbe .Lalloc_remap
    lea rax, [rsi - 1]
    cmp rax, 32767
    jbe .Lalloc_move
    lea rax, [rdx - 1]
    cmp rax, 32767
    ja .Lalloc_remap
.Lalloc_move:
    # A pooled block on either side: allocate, copy the common prefix, free
    # the old block. On failure the old block is untouched and null returns.
    push rdi
    push rsi
    push rdx
    mov rdi, rdx
    mov esi, 8
    call alloc_entry
    pop rdx
    pop rsi
    pop rdi
    test rax, rax
    jz .Lalloc_move_done
    mov rcx, rsi
    cmp rcx, rdx
    cmova rcx, rdx
    push rax
    push rdi
    push rsi
    mov rsi, rdi
    mov rdi, rax
    rep movsb
    pop rsi
    pop rdi
    call alloc_dealloc
    pop rax
.Lalloc_move_done:
    ret
.Lalloc_remap:
    mov r10d, 1
    mov eax, 25
    syscall
    test rax, rax
    jns .Lalloc_remap_done
    xor eax, eax
.Lalloc_remap_done:
    ret
.Lalloc_key:
    .asciz "LANIUS_ALLOC=mmap"
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
    mov r8d, dword ptr [r15]
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
    mov r8d, dword ptr [r15]
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
    mov r8d, dword ptr [r15]
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
