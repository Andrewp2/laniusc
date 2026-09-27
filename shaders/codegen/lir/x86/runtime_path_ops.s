# Source for the path_ops_bytes block in runtime_abi.slang. Assemble with
# `as --64`, then `objcopy -O binary -j .text` to regenerate the bytes.
# Calls are local and position-independent; the block is appended at runtime
# offset X86_RUNTIME_PATH_COPY_OFFSET.
.intel_syntax noprefix
path_copy:
    cmp rsi, 4095
    ja .too_long
    test rsi, rsi
    jz .terminate
    test rdi, rdi
    jz .fault
    xor r8d, r8d
.copy:
    mov al, byte ptr [rdi + r8]
    test al, al
    jz .embedded_nul
    mov byte ptr [rdx + r8], al
    inc r8
    cmp r8, rsi
    jb .copy
.terminate:
    mov byte ptr [rdx + rsi], 0
    xor eax, eax
    ret
.too_long:
    mov eax, -36
    ret
.fault:
    mov eax, -14
    ret
.embedded_nul:
    mov eax, -22
    ret

.global path_open_read
path_open_read:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .open_read_done
    mov rdi, rsp
    xor esi, esi
    xor edx, edx
    mov eax, 2
    syscall
.open_read_done:
    add rsp, 4096
    ret

.global path_open_write
path_open_write:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .open_write_done
    mov rdi, rsp
    mov esi, 0x241
    mov edx, 0x1b6
    mov eax, 2
    syscall
.open_write_done:
    add rsp, 4096
    ret

.global path_open_append
path_open_append:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .open_append_done
    mov rdi, rsp
    mov esi, 0x441
    mov edx, 0x1b6
    mov eax, 2
    syscall
.open_append_done:
    add rsp, 4096
    ret

.global path_remove_file
path_remove_file:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .remove_file_done
    mov rdi, rsp
    mov eax, 87
    syscall
.remove_file_done:
    add rsp, 4096
    ret

.global path_create_dir
path_create_dir:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .create_dir_done
    mov rdi, rsp
    mov esi, 0x1ff
    mov eax, 83
    syscall
.create_dir_done:
    add rsp, 4096
    ret

.global path_remove_dir
path_remove_dir:
    sub rsp, 4096
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .remove_dir_done
    mov rdi, rsp
    mov eax, 84
    syscall
.remove_dir_done:
    add rsp, 4096
    ret

.global path_rename
path_rename:
    sub rsp, 8208
    mov qword ptr [rsp + 8192], rdx
    mov qword ptr [rsp + 8200], rcx
    mov rdx, rsp
    call path_copy
    test eax, eax
    js .rename_done
    mov rdi, qword ptr [rsp + 8192]
    mov rsi, qword ptr [rsp + 8200]
    lea rdx, [rsp + 4096]
    call path_copy
    test eax, eax
    js .rename_done
    mov rdi, rsp
    lea rsi, [rsp + 4096]
    mov eax, 82
    syscall
.rename_done:
    add rsp, 8208
    ret
