BUF_SIZE = 4096

struct  TEXT_VIEW
        left        dd ?
        top         dd ?
        width       dd ?
        height      dd ?

        bg_color    dd ?
        fg_color    dd ?

        buf_data    dd ?
        buf_size    dd ?
        
        total_lines dd ?
        curr_line   dd ?
        max_length  dd ?
ends

proc text_view_init stdcall uses ebx, text_view:dword
        mov     eax, [text_view]
        ret
endp

proc text_view_deinit stdcall, text_view:dword

endp

proc text_view_draw stdcall uses ebx esi, text_view:dword
        mov     esi, [text_view]
        mov     ebx, [esi + TEXT_VIEW.left]
        shl     ebx, 16
        add     ebx, [esi + TEXT_VIEW.width]
        mov     ecx, [esi + TEXT_VIEW.top]
        shl     ecx, 16
        add     ecx, [esi + TEXT_VIEW.height]
        xor     edx, edx
        call    draw_frame
        ret
endp

proc text_view_append_line stdcall, text_view:dword, strp:dword

endp

draw_frame:
; ebx = left << 16 + width
; ecx = top << 16 + height
; edx = color
        push    ebx ecx
        mov     eax, ebx
        shr     eax, 16
        add     ebx, eax
        dec     ebx
        mov     eax, ecx
        shr     eax, 16
        add     ecx, eax
        dec     ecx
        push    ecx
        push    ecx
        mov     eax, ecx
        shr     eax, 16
        mov     cx, ax ; ecx = top << 16 + top
        mcall   SF_DRAW_LINE
        pop     ecx
        mov     eax, ecx
        shl     ecx, 16
        mov     cx, ax ; ecx = height << 16 + height
        mcall   SF_DRAW_LINE
        pop     ecx
        push    ebx
        mov     eax, ebx
        shr     eax, 16
        mov     bx, ax
        mcall   SF_DRAW_LINE
        pop     ebx
        mov     eax, ebx
        shl     ebx, 16
        mov     bx, ax
        mcall   SF_DRAW_LINE
        pop     ecx ebx
        ret
