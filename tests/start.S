    .section .text.start
    .globl _start
_start:
    la   sp, _stack_top
    call main

fail:
    .word 0x00F00013
1:
    j 1b