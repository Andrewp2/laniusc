.text

.globl fp_asm_from32
.type fp_asm_from32,@function
fp_asm_from32:
    movd %edi, %xmm0
    ret
.size fp_asm_from32, .-fp_asm_from32

.globl fp_asm_from64
.type fp_asm_from64,@function
fp_asm_from64:
    movq %rdi, %xmm0
    ret
.size fp_asm_from64, .-fp_asm_from64

.globl fp_asm_bits32
.type fp_asm_bits32,@function
fp_asm_bits32:
    movd %xmm0, %eax
    ret
.size fp_asm_bits32, .-fp_asm_bits32

.globl fp_asm_bits64
.type fp_asm_bits64,@function
fp_asm_bits64:
    movq %xmm0, %rax
    ret
.size fp_asm_bits64, .-fp_asm_bits64

.macro ALIGN_PROBE name
.globl \name
.type \name,@function
\name:
    mov %rsp, %rax
    and $15, %eax
    ret
.size \name, .-\name
.endm

ALIGN_PROBE fp_asm_align31
ALIGN_PROBE fp_asm_align32

.macro CLOBBER_XMM
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
.endm

.globl fp_asm_clobber
.type fp_asm_clobber,@function
fp_asm_clobber:
    CLOBBER_XMM
    movabs $0x1234567887654321, %rax
    ret
.size fp_asm_clobber, .-fp_asm_clobber

.globl fp_asm_clobber32
.type fp_asm_clobber32,@function
fp_asm_clobber32:
    CLOBBER_XMM
    mov $0x40400000, %eax
    movd %eax, %xmm0
    ret
.size fp_asm_clobber32, .-fp_asm_clobber32

.globl fp_asm_clobber64
.type fp_asm_clobber64,@function
fp_asm_clobber64:
    CLOBBER_XMM
    movabs $0x4002000000000000, %rax
    movq %rax, %xmm0
    ret
.size fp_asm_clobber64, .-fp_asm_clobber64

.section .note.GNU-stack,"",@progbits
