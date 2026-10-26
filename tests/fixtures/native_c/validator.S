.text
.globl __lanius_9_9_1
.type __lanius_9_9_1,@function
__lanius_9_9_1:
    test %edi, %edi
#ifdef BAD_BRANCH
    jne __lanius_9_9_2
#else
    jne .Linside
#endif
    xor %eax, %eax
    ret
.Linside:
    mov $1, %eax
    ret
.size __lanius_9_9_1, .-__lanius_9_9_1

.globl __lanius_9_9_2
.type __lanius_9_9_2,@function
__lanius_9_9_2:
    mov $2, %eax
    ret
.size __lanius_9_9_2, .-__lanius_9_9_2

.globl main
.type main,@function
main:
    xor %eax, %eax
    ret
.size main, .-main
.section .note.GNU-stack,"",@progbits
