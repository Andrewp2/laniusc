.text

// A C callee defines only the low 32 bits of a record with a 32-bit field.
.globl rec_asm_dirty
.type rec_asm_dirty,@function
rec_asm_dirty:
    movabs $0xdeadbeef0000002a, %rax
    ret
.size rec_asm_dirty, .-rec_asm_dirty

// The whole register of a 64-bit field arrives.
.globl rec_asm_wide_bits
.type rec_asm_wide_bits,@function
rec_asm_wide_bits:
    mov %rsi, %rax
    ret
.size rec_asm_wide_bits, .-rec_asm_wide_bits

.section .note.GNU-stack,"",@progbits
