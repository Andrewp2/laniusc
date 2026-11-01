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
# Blocks of 1..1048576 bytes come from power-of-two classes (16 B .. 1 MiB)
# carved from 2 MiB arenas, with one free list per class; freed blocks are
# reused, never unmapped. Larger blocks are one mmap each, freed by munmap and
# resized in place by mremap. Callers pass the allocation's size to dealloc/realloc,
# so no block carries a header. A reused block is zeroed up to its size, so
# every allocation reads as zero, as a fresh mapping does.
#
# The pool state is one MAP_32BIT page: class heads at 0..128 (classes 16 B ..
# 1 MiB), per-class free counters at 1048..1176, the arena cursor at 2048 and
# its end at 2056, and (state page only) shared per-class lists at 3024..3152
# under the lock at 2072. Its address lives in the otherwise unused upper
# half of the argc word at [R15 + 4] (argc readers load 32 bits): 0 = not
# decided yet, 1 = direct mode, else the state page. The first small
# allocation decides, claiming [R15+4] with a 32-bit lock cmpxchg so racing
# threads agree. LANIUS_ALLOC=mmap in the environment, or a failed state
# mapping, selects direct mode: every allocation is its own mmap and every
# free a munmap, exactly as before pooling (trace-based tests rely on it).
#
# Thread-safe without locks on the hot path. All threads share R15 (the C
# entry and crt_entry load the fixed process vector 0x100000000000), so a
# thread is identified by its thread pointer at fs:0 instead. The state page
# also holds the creating ("main") thread's fs:0 at 2064, a table lock at 2072
# and, from 2080, a pointer to a 16 KiB table of (fs:0, pool) for 1024 other
# threads. A thread allocates from and frees into its own pool, with no shared
# writes: a freed block is interchangeable memory of its class, so a foreign
# free simply joins the freeing thread's own list (blocks migrate, memory
# stays bounded). Raw mode (R15 != the fixed vector) is single-threaded and
# never reads fs. A thread beyond the 1024 table slots, or whose pool mapping
# fails, allocates directly by mmap and leaks a freed pooled block rather than
# unmapping an arena sub-range (safe; only >1024-thread programs are affected).
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
    cmp rdi, 1048576
    ja .Lalloc_direct
    mov eax, dword ptr [r15 + 4]
    cmp eax, 1
    je .Lalloc_direct
    jb .Lalloc_init
    # mode >= 2: RAX = state page. Find this thread's pool.
    movabs r11, 0x100000000000
    cmp r15, r11
    jne .Lalloc_pool                 # raw mode: state page is the only pool
    mov r9, qword ptr fs:[0]
    cmp r9, qword ptr [rax + 2064]
    je .Lalloc_pool                  # main thread: state page is its pool
    call .Lresolve_pool              # in RAX = state page; out RAX = pool or 0
    test rax, rax
    jz .Lalloc_direct
.Lalloc_pool:
    # RCX = log2(class) - 1 for classes 16 .. 1048576; RDX = its list head.
    lea rcx, [rdi - 1]
    or rcx, 15
    bsr rcx, rcx
    lea rdx, [rax + rcx*8 - 24]
    mov rsi, qword ptr [rdx]
    test rsi, rsi
    jz .Lalloc_refill
.Lalloc_pop:
    mov r8, qword ptr [rsi]
    mov qword ptr [rdx], r8
    lea rcx, [rdi + 7]
    shr rcx, 3
    mov rdi, rsi
    xor eax, eax
    rep stosq
    mov rax, rsi
    ret
.Lalloc_refill:
    # Local list empty: adopt the class's shared list (blocks other threads
    # trimmed off their lists) before carving new memory. Lock-free peek.
    mov r8d, dword ptr [r15 + 4]
    lea r9, [r8 + rcx*8 + 3000]
    cmp qword ptr [r9], 0
    je .Lalloc_bump
.Lalloc_refill_lock:
    mov r10d, 1
    xchg r10d, dword ptr [r8 + 2072]
    test r10d, r10d
    jz .Lalloc_refill_locked
    pause
    jmp .Lalloc_refill_lock
.Lalloc_refill_locked:
    mov rsi, qword ptr [r9]
    mov qword ptr [r9], 0
    mov dword ptr [r8 + 2072], 0
    test rsi, rsi
    jz .Lalloc_bump
    mov qword ptr [rdx], rsi
    jmp .Lalloc_pop
.Lalloc_bump:
    mov edx, 2
    shl edx, cl
    mov rsi, qword ptr [rax + 2048]
    lea r8, [rsi + rdx]
    cmp r8, qword ptr [rax + 2056]
    ja .Lalloc_arena
    mov qword ptr [rax + 2048], r8
    mov rax, rsi
    ret
.Lalloc_arena:
    # A fresh 2 MiB arena; the rest of the old one is abandoned.
    push rax
    push rdx
    mov edi, 2097152
    call .Lalloc_direct
    pop rdx
    pop rcx
    test rax, rax
    jz .Lalloc_arena_done
    lea rsi, [rax + rdx]
    mov qword ptr [rcx + 2048], rsi
    lea rsi, [rax + 2097152]
    mov qword ptr [rcx + 2056], rsi
.Lalloc_arena_done:
    ret
.Lalloc_init:
    mov r8d, dword ptr [r15]
    lea r8, [r15 + r8*8 + 16]
.Lalloc_env:
    mov r9, qword ptr [r8]
    test r9, r9
    jz .Lalloc_makepage
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
.Lalloc_mark_direct:
    mov dword ptr [r15 + 4], 1
    jmp .Lalloc_direct
.Lalloc_makepage:
    push rsi                          # save align and size across the page mmap
    push rdi
    xor edi, edi
    mov esi, 4096
    mov edx, 3
    mov r10d, 0x62
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js .Lalloc_mp_fail
    movabs r11, 0x100000000000
    cmp r15, r11
    jne .Lalloc_claim
    mov r9, qword ptr fs:[0]
    mov qword ptr [rax + 2064], r9     # record the creating thread as main
.Lalloc_claim:
    # Publish the page by claiming [r15+4] (0 -> page); a loser frees its page.
    mov r9, rax
    mov edx, eax
    xor eax, eax
    lock cmpxchg dword ptr [r15 + 4], edx
    jz .Lalloc_won
    mov rdi, r9
    mov esi, 4096
    mov eax, 11
    syscall
    pop rdi
    pop rsi
    jmp alloc_entry
.Lalloc_won:
    pop rdi
    pop rsi
    mov rax, r9
    jmp .Lalloc_pool
.Lalloc_mp_fail:
    pop rdi
    pop rsi
    jmp .Lalloc_mark_direct
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
# Find the calling thread's pool (non-main CRT thread). In RAX = state page.
# Out RAX = pool base, or 0 when no pool could be provided. Preserves RDI/RSI.
.Lresolve_pool:
    push rbx
    mov rbx, rax
    mov r9, qword ptr fs:[0]
    mov r10, qword ptr [rbx + 2080]
    test r10, r10
    jz .Lres_slow
    mov rax, r9
    shr rax, 4
    and eax, 1023
    shl rax, 4
    lea r11, [r10 + rax]
    lea rdx, [r10 + 16384]
    mov ecx, 1024
.Lres_probe:
    mov r8, qword ptr [r11]
    cmp r8, r9
    je .Lres_hit
    test r8, r8
    jz .Lres_slow
    add r11, 16
    cmp r11, rdx
    jb .Lres_pn
    mov r11, r10
.Lres_pn:
    dec ecx
    jnz .Lres_probe
.Lres_none:
    xor eax, eax
    pop rbx
    ret
.Lres_hit:
    mov rax, qword ptr [r11 + 8]
    pop rbx
    ret
.Lres_slow:
    push rdi
    push rsi
.Lres_lock:
    mov eax, 1
    xchg eax, dword ptr [rbx + 2072]
    test eax, eax
    jz .Lres_locked
    pause
    jmp .Lres_lock
.Lres_locked:
    mov r10, qword ptr [rbx + 2080]
    test r10, r10
    jnz .Lres_have
    xor edi, edi
    mov esi, 16384
    mov edx, 3
    mov r10d, 0x62
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js .Lres_unlock_none
    mov qword ptr [rbx + 2080], rax
    mov r10, rax
.Lres_have:
    mov r9, qword ptr fs:[0]
    mov rax, r9
    shr rax, 4
    and eax, 1023
    shl rax, 4
    lea r11, [r10 + rax]
    lea rdx, [r10 + 16384]
    mov ecx, 1024
.Lres_sprobe:
    mov r8, qword ptr [r11]
    cmp r8, r9
    je .Lres_sfound
    test r8, r8
    jz .Lres_sinsert
    add r11, 16
    cmp r11, rdx
    jb .Lres_spn
    mov r11, r10
.Lres_spn:
    dec ecx
    jnz .Lres_sprobe
    jmp .Lres_unlock_none
.Lres_sfound:
    mov rax, qword ptr [r11 + 8]
    jmp .Lres_unlock_ok
.Lres_sinsert:
    push r11
    xor edi, edi
    mov esi, 4096
    mov edx, 3
    mov r10d, 0x62
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    pop r11
    test rax, rax
    js .Lres_unlock_none
    mov qword ptr [r11 + 8], rax      # store pool before tp (x86 TSO release)
    mov r9, qword ptr fs:[0]
    mov qword ptr [r11], r9
.Lres_unlock_ok:
    mov dword ptr [rbx + 2072], 0
    pop rsi
    pop rdi
    pop rbx
    ret
.Lres_unlock_none:
    mov dword ptr [rbx + 2072], 0
    xor eax, eax
    pop rsi
    pop rdi
    pop rbx
    ret
alloc_dealloc:
    lea rax, [rsi - 1]
    cmp rax, 1048575
    ja .Lalloc_munmap
    mov eax, dword ptr [r15 + 4]
    cmp eax, 1
    jbe .Lalloc_munmap
    test rdi, rdi
    jz .Lalloc_free_done
    movabs r11, 0x100000000000
    cmp r15, r11
    jne .Lalloc_free_pool
    mov r9, qword ptr fs:[0]
    cmp r9, qword ptr [rax + 2064]
    je .Lalloc_free_pool
    call .Lresolve_pool
    test rax, rax
    jz .Lalloc_free_done              # no pool: leak the block (never unmap an arena)
.Lalloc_free_pool:
    lea rcx, [rsi - 1]
    or rcx, 15
    bsr rcx, rcx
    lea rdx, [rax + rcx*8 - 24]
    mov r8, qword ptr [rdx]
    mov qword ptr [rdi], r8
    mov qword ptr [rdx], rdi
    # Every 256 frees into a class, keep 63 blocks and move the rest to the
    # class's shared list, so blocks freed by a consumer thread flow back to
    # the producer instead of piling up (memory stays bounded by live data).
    mov r8, qword ptr [rdx + 1048]
    inc r8
    mov qword ptr [rdx + 1048], r8
    cmp r8, 256
    jae .Lalloc_trim
.Lalloc_free_done:
    ret
.Lalloc_trim:
    mov qword ptr [rdx + 1048], 0
    mov r8, qword ptr [rdx]
    mov r9d, 63
.Lalloc_trim_keep:
    mov r10, qword ptr [r8]
    test r10, r10
    jz .Lalloc_free_done
    dec r9d
    jz .Lalloc_trim_cut
    mov r8, r10
    jmp .Lalloc_trim_keep
.Lalloc_trim_cut:
    mov qword ptr [r8], 0
    mov r11, r10
.Lalloc_trim_tail:
    mov r9, qword ptr [r11]
    test r9, r9
    jz .Lalloc_trim_splice
    mov r11, r9
    jmp .Lalloc_trim_tail
.Lalloc_trim_splice:
    mov eax, dword ptr [r15 + 4]
    lea r9, [rax + rcx*8 + 3000]
.Lalloc_trim_lock:
    mov r8d, 1
    xchg r8d, dword ptr [rax + 2072]
    test r8d, r8d
    jz .Lalloc_trim_locked
    pause
    jmp .Lalloc_trim_lock
.Lalloc_trim_locked:
    mov r8, qword ptr [r9]
    mov qword ptr [r11], r8
    mov qword ptr [r9], r10
    mov dword ptr [rax + 2072], 0
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
    cmp rax, 1048575
    jbe .Lalloc_move
    lea rax, [rdx - 1]
    cmp rax, 1048575
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
