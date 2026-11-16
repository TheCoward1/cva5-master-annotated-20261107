    .section .text
    .globl _start
    .align 2
_start:
    li   x6, 0x12345678
    li   x7, 0x0000000F
    and  x5, x6, x7
    li   x8, 0x00000008
    bne  x5, x8, fail
    .word 0x00A00013
fail:
    .word 0x00F00013