BUF_SIZE = 4096
FRM_WIDTH = 1
MARGIN = 1

struct  TEXT_VIEW
        left        dd ?
        top         dd ?
        width       dd ?
        height      dd ?

        bg_color    dd ?
        fg_color    dd ?

        buf_data    dd ?
        buf_size    dd ?
        data_size   dd ?

        total_lines dd ?
        curr_line   dd ?
        max_length  dd ? ; length of the longest string

        rows        dd ?
        cols        dd ?
ends

proc text_view_init stdcall, text_view:dword
        mov     ecx, [text_view]
        xor     eax, eax
        mov     [ecx + TEXT_VIEW.buf_data], eax
        mov     [ecx + TEXT_VIEW.buf_size], eax
        mov     [ecx + TEXT_VIEW.data_size], eax
        mov     [ecx + TEXT_VIEW.total_lines], eax
        mov     [ecx + TEXT_VIEW.curr_line], eax
        mov     [ecx + TEXT_VIEW.max_length], eax
        ret
endp

proc text_view_deinit stdcall uses ebx, text_view:dword
        mov     ebx, [text_view]
        mov     ecx, [ebx + TEXT_VIEW.buf_data]
        test    ecx, ecx
        jz      .exit
        mcall   SF_SYS_MISC, SSF_MEM_FREE
    .exit
        ret
endp

proc text_view_draw stdcall uses ebx esi edi, text_view:dword
        mov     esi, [text_view]
        call    tv.draw_frame_and_bg
        call    tv.calc_rows_and_cols
        DEBUGF  0, "text_view rows=%d cols=%d\n", [esi + TEXT_VIEW.rows], [esi + TEXT_VIEW.cols]

        mov     eax, [esi + TEXT_VIEW.curr_line]
        mov     ebx, [esi + TEXT_VIEW.total_lines]
        DEBUGF  0, "text_view curr_line=%d total_lines=%d\n", eax, ebx
        sub     ebx, eax
        cmp     ebx, [esi + TEXT_VIEW.rows]
        jbe     @f
        mov     ebx, [esi + TEXT_VIEW.rows]
    @@:
        mov     edi, [esi + TEXT_VIEW.buf_data]
        call    goto_curr_line
        mov     ecx, ebx ; ecx = count lines
        xor     eax, eax ; eax = index from 0

        mov     ebx, [esi + TEXT_VIEW.left]
        add     ebx, MARGIN + FRM_WIDTH
        shl     ebx, 16
        add     ebx, [esi + TEXT_VIEW.top]
        add     ebx, MARGIN + FRM_WIDTH

    .draw_lines:
        cmp     eax, ecx
        jae     .draw_lines_end
        push    eax ecx
        call    tv.draw_single_line
        ; move edi pointer to the next string
        add     edi, eax
        inc     edi
        pop     ecx eax
        inc     eax ; next line num
        add     ebx, FONT_HEIGHT + MARGIN
        jmp     .draw_lines
    .draw_lines_end:
        ret
endp

proc text_view_append_line stdcall uses ebx esi edi, text_view:dword, string:dword
        mov     esi, [string]
        call    strlen
        inc     eax ; include \0
        mov     esi, [text_view]
        mov     edi, eax
        add     eax, [esi + TEXT_VIEW.data_size]
        cmp     eax, [esi + TEXT_VIEW.buf_size]
        jbe     .noalloc

        and     eax, not (BUF_SIZE - 1)
        add     eax, BUF_SIZE
        mov     ecx, eax
        mov     edx, [esi + TEXT_VIEW.buf_data]
        mcall   SF_SYS_MISC, SSF_MEM_REALLOC
        test    eax, eax
        jz      .exit

        mov     [esi + TEXT_VIEW.buf_data], eax
        mov     [esi + TEXT_VIEW.buf_size], ecx
    .noalloc:
        inc     [esi + TEXT_VIEW.total_lines]
        mov     eax, edi
        cmp     eax, [esi + TEXT_VIEW.max_length]
        jbe     .short

        mov     [esi + TEXT_VIEW.max_length], eax
    .short:
        mov     ecx, edi
        mov     edi, [esi + TEXT_VIEW.buf_data]
        add     edi, [esi + TEXT_VIEW.data_size]
        add     [esi + TEXT_VIEW.data_size], ecx
        mov     esi, [string]
        cld
        rep     movsb
    .exit:
        ret
endp

proc text_view_clear stdcall uses ebx, text_view:dword
        mov     edx, [text_view]
        mov     ecx, [edx + TEXT_VIEW.buf_data]
        test    ecx, ecx
        jz      @f
        mcall   SF_SYS_MISC, SSF_MEM_FREE
    @@:
        xor     eax, eax
        mov     [edx + TEXT_VIEW.buf_data], eax
        mov     [edx + TEXT_VIEW.buf_size], eax
        mov     [edx + TEXT_VIEW.data_size], eax
        mov     [edx + TEXT_VIEW.total_lines], eax
        mov     [edx + TEXT_VIEW.curr_line], eax
        mov     [edx + TEXT_VIEW.max_length], eax
        ret
endp

proc text_view_deinit stdcall uses ebx, text_view:dword
        mov     edx, [text_view]
        mov     ecx, [edx + TEXT_VIEW.buf_data]
        test    ecx, ecx
        jz      @f
        mcall   SF_SYS_MISC, SSF_MEM_FREE
    @@:
        ret
endp

proc tv.draw_frame_and_bg
; esi = text_view
        mov     ebx, [esi + TEXT_VIEW.left]
        shl     ebx, 16
        add     ebx, [esi + TEXT_VIEW.width]
        mov     ecx, [esi + TEXT_VIEW.top]
        shl     ecx, 16
        add     ecx, [esi + TEXT_VIEW.height]
        mov     edx, [esi + TEXT_VIEW.fg_color]
        call    draw_frame
        add     ebx, 1 shl 16
        sub     ebx, 2
        add     ecx, 1 shl 16
        sub     ecx, 2
        mov     edx, [esi + TEXT_VIEW.bg_color]
        mcall   SF_DRAW_RECT
        ret
endp

proc tv.calc_rows_and_cols
; esi = text_view
        mov     eax, [esi + TEXT_VIEW.width]
        sub     eax, (FRM_WIDTH + MARGIN) * 2
        shr     eax, 3 ; assume that font width is 8 px
        mov     [esi + TEXT_VIEW.cols], eax
        xor     edx, edx
        mov     eax, [esi + TEXT_VIEW.height]
        sub     eax, MARGIN * 2
        mov     ebx, FONT_HEIGHT + MARGIN
        div     ebx
        mov     [esi + TEXT_VIEW.rows], eax
        ret
endp

proc tv.draw_single_line uses esi
; esi = text_view
; ebx = coordinates: left << 16 + top
; edi = pointer to the first byte of string in [text_view.buf_data]
; return: eax = length of the string
        mov     ecx, 0x10000000 ; fixed-length string
        or      ecx, [esi + TEXT_VIEW.fg_color]
        push    esi
        mov     esi, edi
        call    strlen
        pop     esi
        push    eax
        cmp     eax, [esi + TEXT_VIEW.cols]
        jbe     .len_ok
        mov     eax, [esi + TEXT_VIEW.cols]
    .len_ok:
        mov     esi, eax
        mov     edx, edi
        mcall   SF_DRAW_TEXT
        pop     eax
        ret
endp

proc goto_curr_line uses ebx esi
; eax = curr line index
; edi = buf
        mov     ebx, eax
        xor     ecx, ecx
        mov     esi, edi
        cld
    .scan:
        cmp     ecx, ebx
        je      .exit
        lodsb
        test    al, al
        jnz     .scan
        inc     ecx
        jmp     .scan
    .exit:
        mov     eax, ebx
        mov     edi, esi
        ret
endp

proc draw_frame
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
        mov     cx, ax
        mcall   SF_DRAW_LINE
        pop     ecx
        mov     eax, ecx
        shl     ecx, 16
        mov     cx, ax
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
endp
