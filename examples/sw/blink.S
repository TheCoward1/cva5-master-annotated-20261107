    .section .text
    .globl _start
    .align 2

_start:
    li   t0, 0x60000000      # AXI GPIO base address
    sw   zero, 4(t0)         # GPIO direction: all outputs
    li   t2, 1               # LED pattern 0001

loop:
    sw   t2, 0(t0)           # write GPIO data register
    li   t3, 2000000         # delay counter

delay:
    addi t3, t3, -1
    bnez t3, delay

    slli t2, t2, 1           # 0001 -> 0010 -> 0100 -> 1000
    li   t4, 0x10
    bne  t2, t4, loop

    li   t2, 1
    j    loop