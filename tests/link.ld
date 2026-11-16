ENTRY(_start)

SECTIONS
{
    . = 0x80000000;
    .text : {
        *(.text.start)
        *(.text*)
    }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*) }
    .bss    : { *(.bss*) *(COMMON) }

    . = ALIGN(4);
    _stack_top = 0x80000FF0;
}