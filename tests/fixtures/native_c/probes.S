.text

/* Read rsp before a compiler-generated C prologue can change its residue. */
.macro ALIGN_PROBE name
.globl \name
.type \name,@function
\name:
    mov %rsp, %rax
    and $15, %eax
    ret
.size \name, .-\name
.endm

ALIGN_PROBE probe_align0
ALIGN_PROBE probe_align7
ALIGN_PROBE probe_align8
ALIGN_PROBE probe_align9

.globl probe_clobber
.type probe_clobber,@function
probe_clobber:
    /* Use every callee-saved register, then restore the required ABI state. */
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    movabs $0xdeadbeef13572468, %rbx
    mov %rbx, %rbp
    mov %rbx, %r12
    mov %rbx, %r13
    mov %rbx, %r14
    mov %rbx, %r15
    mov %rbx, %rdi
    mov %rbx, %rsi
    mov %rbx, %rdx
    mov %rbx, %rcx
    mov %rbx, %r8
    mov %rbx, %r9
    mov %rbx, %r10
    mov %rbx, %r11
    pcmpeqd %xmm0, %xmm0
    pcmpeqd %xmm1, %xmm1
    pcmpeqd %xmm2, %xmm2
    pcmpeqd %xmm3, %xmm3
    pcmpeqd %xmm4, %xmm4
    pcmpeqd %xmm5, %xmm5
    pcmpeqd %xmm6, %xmm6
    pcmpeqd %xmm7, %xmm7
    pcmpeqd %xmm8, %xmm8
    pcmpeqd %xmm9, %xmm9
    pcmpeqd %xmm10, %xmm10
    pcmpeqd %xmm11, %xmm11
    pcmpeqd %xmm12, %xmm12
    pcmpeqd %xmm13, %xmm13
    pcmpeqd %xmm14, %xmm14
    pcmpeqd %xmm15, %xmm15
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    movabs $0x9876543210abcdef, %rax
    ret
.size probe_clobber, .-probe_clobber

.section .note.GNU-stack,"",@progbits
