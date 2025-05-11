; Copyright (C) KolibriOS team 2025. All rights reserved.
; Distributed under terms of the GNU General Public License
;
; GNU GENERAL PUBLIC LICENSE
; Version 2, June 1991

align 4
proc str_to_uint
; esi = source string
; eax = 0 if success
; ebx = number
        xor     eax, eax
        xor     ebx, ebx
.loop:
        lodsb
        test    al, al
        jz      .exit
        sub     al, '0'
        jb      .exit
        cmp     al, 9
        ja      .exit
        lea     ebx, [ebx + 4 * ebx]
        shl     ebx, 1
        add     ebx, eax
        jmp     .loop
.exit:
        ret
endp

align 4
proc int_to_str
; eax = number to convert
; ecx = base
; edi = string buffer address
        push    ecx edx
        or      eax, eax
        jns     @f
        mov     byte [edi], '-'
        inc     edi
    @@:
        call    .recurse
        pop     edx ecx
        ret
.recurse:
        cmp     eax, ecx
        jb      @f
        xor     edx, edx
        div     ecx
        push    edx
        call    .recurse
        pop     eax
    @@:
        cmp     al, 10
        sbb     al, 0x69
        das
        stosb
        retn
endp

align 4
proc strlen
; esi = string
; eax = length
        push    ebx
        mov     ebx, esi
        cld
    @@:
        lodsb
        test    al, al
        jnz     @b
        mov     eax, esi
        sub     eax, ebx
        dec     eax
        pop     ebx
        ret
endp

proc strcpy
; esi = source
; edi = destination
        cld
    @@:
        lodsb
        stosb
        test    al, al
        jnz     @b
        ret
endp
