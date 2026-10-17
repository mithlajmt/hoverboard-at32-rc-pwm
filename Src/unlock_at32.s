/*
 * AT32F413 Hardware Flash Access Protection (FAP Level 1) Unlock Stub
 * Author: Mithlaj MT (@mithlajmt)
 * Runs directly in SRAM at 0x20000000 to clear RDPRT & mass erase flash
 */

.syntax unified
.thumb
.text
.global _start
_start:
    /* Unlock Flash Controller */
    ldr r0, =0x40022004
    ldr r1, =0x45670123
    str r1, [r0]
    ldr r1, =0xCDEF89AB
    str r1, [r0]

    /* Unlock Option Bytes */
    ldr r0, =0x40022008
    ldr r1, =0x45670123
    str r1, [r0]
    ldr r1, =0xCDEF89AB
    str r1, [r0]

    /* Erase Option Bytes: CTRL |= UOBWE (0x200) | UOBERS (0x20) | STRT (0x40) = 0x260 */
    ldr r2, =0x40022010
    ldr r3, =0x4002200C
    ldr r1, =0x260
    str r1, [r2]

wait_erase:
    ldr r1, [r3]
    tst r1, #1
    bne wait_erase

    /* Clear UOBERS, set UOBPRGM (0x10) | UOBWE (0x200) = 0x210 */
    ldr r1, =0x210
    str r1, [r2]

    /* Write RDPRT = 0x00A5 (Disables Readout Protection / FAP) */
    ldr r0, =0x1FFFF800
    movs r1, #0xA5
    strh r1, [r0]

wait_prgm:
    ldr r1, [r3]
    tst r1, #1
    bne wait_prgm

    /* Clear UOBPRGM */
    movs r1, #0
    str r1, [r2]

    /* Success indicator: set r0 = 0x12345678 */
    ldr r0, =0x12345678
    bkpt #0
loop:
    b loop

    .align 4
    .word 0x40022004
    .word 0x45670123
    .word 0xCDEF89AB
    .word 0x40022008
    .word 0x40022010
    .word 0x4002200C
    .word 0x1FFFF800
    .word 0x12345678
