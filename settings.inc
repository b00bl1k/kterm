; Copyright (C) KolibriOS team 2025. All rights reserved.
; Distributed under terms of the GNU General Public License
;
; GNU GENERAL PUBLIC LICENSE
; Version 2, June 1991

SETTINGS_WIN_STACK_SIZE = 1024
SETTINGS_WIN_WIDTH = 350
SETTINGS_WIN_HEIGHT = 250

SETTINGS_BTN_WIDTH = 60
SETTINGS_BTN_HEIGHT = 24

OPT_HEIGHT = 10
COL2 = 190

SETTINGS_APPEND_NONE = 0
SETTINGS_APPEND_LF = 1
SETTINGS_APPEND_CRLF = 2

proc show_settings_win
        cmp     [settings_is_win_opened], 1
        jne     @f
        mcall   SF_SYSTEM, SSF_GET_THREAD_SLOT, [settings_win_pid]
        xchg    eax, ecx
        mcall   SF_SYSTEM, SSF_FOCUS_WINDOW
        ret
    @@:
        mcall   SF_CREATE_THREAD, 1, .thread, settings_win_stack + SETTINGS_WIN_STACK_SIZE
        cmp     eax, -1
        je      @f
        mov     [settings_win_pid], eax
        mov     [settings_is_win_opened], 1
    @@:
        ret
    .thread:
        mcall   SF_SET_EVENTS_MASK, EVM_MOUSE + EVM_MOUSE_FILTER + EVM_REDRAW + EVM_BUTTON + EVM_KEY
        call    settings_load
        call    .draw_window
    .loop:
        mcall   SF_WAIT_EVENT
        dec     eax
        jz      .win
        dec     eax
        jz      .key
        dec     eax
        jz      .btn
    .mouse:
        invoke  edit_box_mouse, ed_port
        invoke  edit_box_mouse, ed_baud
        invoke  edit_box_mouse, ed_bits
        invoke  option_box_mouse, op_append
        jmp     .loop
    .win:
        call    .draw_window
        jmp     .loop
    .key:
        mcall   SF_GET_KEY
        invoke  edit_box_key, ed_port
        invoke  edit_box_key, ed_baud
        invoke  edit_box_key, ed_bits
        jmp     .loop
    .btn:
        mcall   SF_GET_BUTTON
        cmp     ah, BTN_OK
        jne     @f
        call    settings_save
    @@:
        and     [settings_is_win_opened], 0
        mcall   SF_TERMINATE_PROCESS

    .draw_window:
        mcall   SF_REDRAW, SSF_BEGIN_DRAW

        mov     edx, [sc.work]
        or      edx, 0x34000000
        mov     esi, [sc.work]
        mov     edi, settings_win_name

        mov     ebx, [pi.box.width]
        shr     ebx, 1
        add     ebx, [pi.box.left]
        sub     ebx, SETTINGS_WIN_WIDTH / 2
        shl     ebx, 16
        add     ebx, SETTINGS_WIN_WIDTH

        mov     ecx, [pi.box.height]
        shr     ecx, 1
        add     ecx, [pi.box.top]
        sub     ecx, SETTINGS_WIN_HEIGHT / 2
        shl     ecx, 16
        add     ecx, SETTINGS_WIN_HEIGHT

        mcall   SF_CREATE_WINDOW
        mcall   SF_THREAD_INFO, s_pi, -1

        ; prevent drawing if the window is collapsed
        test    [s_pi.wnd_state], 0x04
        jnz     .end_redraw

        mov     ecx, 0x90000000
        or      ecx, [sc.work_text]
        mcall   SF_DRAW_TEXT, <WIN_MARGIN, WIN_MARGIN + 2>, , port_conf_lbl

        add     ebx, WIN_MARGIN * 2 + FONT_HEIGHT
        mcall   SF_DRAW_TEXT, , , port_lbl
        mov     word [ed_port.top], bx

        add     ebx, WIN_MARGIN + ED_HEIGHT
        mcall   SF_DRAW_TEXT, , , baud_lbl
        mov     word [ed_baud.top], bx

        add     ebx, WIN_MARGIN + ED_HEIGHT
        mcall   SF_DRAW_TEXT, , , bits_lbl
        mov     word [ed_bits.top], bx

        mcall   SF_DRAW_TEXT, <COL2, WIN_MARGIN + 2>, , tx_text_lbl


        edit_boxes_set_sys_color settings_win_edits_start, settings_win_edits_end, sc
        invoke  edit_box_draw, ed_port
        invoke  edit_box_draw, ed_baud
        invoke  edit_box_draw, ed_bits
        option_boxes_set_sys_color sc, op_append
        invoke  option_box_draw, op_append

        mov     ebx, WIN_MARGIN shl 16
        add	    ebx, [s_pi.client_box.width]
        sub     ebx, WIN_MARGIN + 1
        mov     edx, [s_pi.client_box.height]
        sub     edx, SETTINGS_BTN_HEIGHT + WIN_MARGIN * 2
        mov     ecx, edx
        shl     ecx, 16
        mov     cx, dx
        mov     edx, [sc.work_graph]
        mcall   SF_DRAW_LINE

        mov     ebx, [s_pi.client_box.width]
        sub     ebx, (SETTINGS_BTN_WIDTH + WIN_MARGIN) * 2
        shl     ebx, 16
        add     ebx, SETTINGS_BTN_WIDTH
        mov     ecx, [s_pi.client_box.height]
        sub     ecx, SETTINGS_BTN_HEIGHT + WIN_MARGIN
        shl     ecx, 16
        add     ecx, SETTINGS_BTN_HEIGHT
        mcall   SF_DEFINE_BUTTON, , , BTN_OK, [sc.work_button]

        push    ebx ecx
        add     ebx, 24 shl 16
        mov     bx, word [s_pi.client_box.height]
        sub     bx, SETTINGS_BTN_HEIGHT + WIN_MARGIN - 5
        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, , , ok_lbl
        pop     ecx ebx

        add     ebx, (SETTINGS_BTN_WIDTH + WIN_MARGIN) shl 16
        mcall   SF_DEFINE_BUTTON, , , BTN_CANCEL, [sc.work_button]

        add     ebx, 8 shl 16
        mov     bx, word [s_pi.client_box.height]
        sub     bx, SETTINGS_BTN_HEIGHT + WIN_MARGIN - 5
        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, , , cancel_lbl

    .end_redraw:
        mcall   SF_REDRAW, SSF_END_DRAW
        ret
endp

proc settings_load
        mov     eax, [port_num]
        mov     ecx, 10
        mov     edi, ed_port_val
        call    int_to_str
        and     byte [edi], 0
        mov     esi, ed_port_val
        call    strlen
        mov     [ed_port.size], eax
        mov     [ed_port.pos], eax

        mov     eax, [port_conf + SP_CONF.baudrate]
        mov     ecx, 10
        mov     edi, ed_baud_val
        call    int_to_str
        and     byte [edi], 0
        mov     esi, ed_baud_val
        call    strlen
        mov     [ed_baud.size], eax

        mov     al, [port_conf + SP_CONF.word_size]
        add     al, '0'
        mov     [ed_bits_val], al
        mov     [ed_bits_val + 1], 0
        mov     [ed_bits.size], 1

        mov     al, [text_append]
        mov     ebx, opt_append_none
        cmp     al, SETTINGS_APPEND_NONE
        je      .opt_append_ok
        mov     ebx, opt_append_lf
        cmp     al, SETTINGS_APPEND_LF
        je      .opt_append_ok
        mov     ebx, opt_append_crlf
    .opt_append_ok:
        mov     [op_append_val], ebx
        ret
endp

proc settings_save
        mov     esi, ed_port_val
        call    str_to_uint
        mov     [port_num], ebx

        mov     esi, ed_baud_val
        call    str_to_uint
        mov     [port_conf + SP_CONF.baudrate], ebx

        mov     al, [ed_bits_val]
        sub     al, '0'
        mov     [port_conf + SP_CONF.word_size], al

        mov     eax, [op_append_val]
        mov     bl, SETTINGS_APPEND_NONE
        cmp     eax, opt_append_none
        je      .opt_append_ok
        mov     bl, SETTINGS_APPEND_LF
        cmp     eax, opt_append_lf
        je      .opt_append_ok
        mov     bl, SETTINGS_APPEND_CRLF
    .opt_append_ok:
        mov     [text_append], bl
        ret
endp

iglobal
settings_is_win_opened db 0
settings_win_edits_start:
ed_port         edit_box 70, 100, WIN_MARGIN, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_port_val, mouse_dd, \
                         ed_focus + ed_figure_only
ed_baud         edit_box 70, 100, WIN_MARGIN * 2 + ED_HEIGHT, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_baud_val, mouse_dd, \
                         ed_figure_only
ed_bits         edit_box 40, 100, WIN_MARGIN * 3 + ED_HEIGHT * 2, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 1, ed_bits_val, mouse_dd, \
                         ed_figure_only
settings_win_edits_end:
opt_append_none     option_box op_append_val, COL2, WIN_MARGIN * 2 + FONT_HEIGHT, 6, 12, 0, 0, 0, opt_lbl_nothing, 14
opt_append_lf       option_box op_append_val, COL2, WIN_MARGIN * 3 + OPT_HEIGHT+ FONT_HEIGHT, 6, 12, 0, 0, 0, opt_lbl_lf, 9
opt_append_crlf     option_box op_append_val, COL2, WIN_MARGIN * 4 + OPT_HEIGHT * 2+ FONT_HEIGHT, 6, 12, 0, 0, 0, opt_lbl_crlf, 11
op_append           dd opt_append_none, opt_append_lf, opt_append_crlf, 0

settings_win_name   db 'kterm - settings', 0
port_conf_lbl       db 'Port settings', 0
tx_text_lbl         db 'Transmitted text', 0
port_lbl            db 'Port:', 0
baud_lbl            db 'Baudrate:', 0
bits_lbl            db 'Data bits:', 0
ok_lbl              db 'Ok', 0
cancel_lbl          db 'Cancel', 0
opt_lbl_nothing     db 'Append nothing', 0
opt_lbl_lf          db 'Append LF', 0
opt_lbl_crlf        db 'Append CRLF', 0
endg

uglobal
align 4
settings_win_pid    dd ?
op_append_val       dd ?
s_pi                process_information
ed_port_val         rb 7
ed_baud_val         rb 7
ed_bits_val         rb 2
settings_win_stack  rb SETTINGS_WIN_STACK_SIZE
endg
