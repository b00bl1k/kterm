; Copyright (C) KolibriOS team 2025. All rights reserved.
; Distributed under terms of the GNU General Public License
;
; GNU GENERAL PUBLIC LICENSE
; Version 2, June 1991

use32
        org    0x0

        db     'MENUET01'
        dd     0x01             ; header version
        dd     start            ; start of code
        dd     i_end            ; size of image
        dd     (i_end + 0x1000) ; memory for app
        dd     (i_end + 0x1000) ; esp
        dd     0, 0             ; I_Param, I_Path

WIN_MIN_WIDTH = 150
WIN_MIN_HEIGHT = 200
WIN_BORDER_WIDTH = 5
FONT_WIDTH = 8
FONT_HEIGHT = 16
SCROLL_WIDTH = 16
SCROLL_TOP = 34
RX_BUF_SIZE = 256
LINE_HEADER_LEN = 11
PORT_STATUS_LEN = 128
ED_SEND_MAX_LEN = 256

KEY_ENTER = 13

CONN_WIN_STACK_SIZE = 1024

BTN_CLOSE = 1
BTN_SETUP = 2
BTN_CONN = 3
BTN_CLEAR = 4
BTN_SEND = 5

BTN_OK = 2
BTN_CANCEL = 3

__DEBUG__ = 0
__DEBUG_LEVEL__ = 0

include '../../proc32.inc'
include '../../macros.inc'
include '../../KOSfuncs.inc'
include '../../dll.inc'
include '../../debug-fdo.inc'
include '../../develop/libraries/box_lib/trunk/box_lib.mac'
include '../../../drivers/serial/common.inc'
include 'textview.inc'
include 'utils.inc'

start:
        mcall   SF_SYS_MISC, SSF_HEAP_INIT

        call    serial_port_init
        test    eax, eax
        jnz     @f
        mov     eax, err_driver
        mov     [status_msg], eax
    @@:

        stdcall dll.Load, @IMPORT
        or      eax, eax
        jnz     .exit

        mcall   SF_SET_EVENTS_MASK, EVM_MOUSE + EVM_REDRAW + EVM_BUTTON + EVM_KEY

        mov     byte [ed_send_val], 0
        stdcall text_view_init, text_view
        call    .draw_window

    .loop:
        mov     eax, SF_WAIT_EVENT
        cmp     [is_connected], 0
        jz      @f
        mov     eax, SF_WAIT_EVENT_TIMEOUT
        mov     ebx, 100
    @@:
        mcall
        cmp     eax, EV_REDRAW
        jz      .win
        cmp     eax, EV_KEY
        jz      .key
        cmp     eax, EV_BUTTON
        jz      .btn
        cmp     eax, EV_MOUSE
        jz      .mouse
    .timer:
        call    check_port
        jmp     .loop
    .win:
        call    .draw_window
        jmp     .loop
    .key:
        mcall   SF_GET_KEY
        invoke  edit_box_key, ed_send
        cmp     ah, KEY_ENTER
        jne     @f
        call    send_text
    @@:
        jmp     .loop
    .btn:
        mcall   SF_GET_BUTTON
        cmp     ah, BTN_CONN
        jne     @f
        call    btn_conn_click
        call    .draw_window
        jmp     .loop
    @@:
        cmp     ah, BTN_SETUP
        jne     @f
        call    show_conn_window
        jmp     .loop
    @@:
        cmp     ah, BTN_CLEAR
        jne     @f
        stdcall text_view_clear, text_view
        stdcall text_view_draw, text_view
        call    update_vscroll
        invoke  scrollbar_draw, vscroll
        jmp     .loop
    @@:
        cmp     ah, BTN_SEND
        jne     @f
        call    send_text
        jmp     .loop
    @@:
        cmp     ah, BTN_CLOSE
        jne     .loop
    .exit:
        mcall   SF_TERMINATE_PROCESS
    .mouse:
        invoke  edit_box_mouse, ed_send
        push    [vscroll.position]
        invoke  scrollbar_mouse, vscroll
        pop     eax
        cmp     eax, [vscroll.position]
        je      .loop
        mov     eax, [vscroll.position]
        cmp     eax, [text_view.total_lines]
        jae     .loop
        mov     [text_view.curr_line], eax
        stdcall text_view_draw, text_view
        jmp     .loop
    .draw_window:
        mcall   SF_STYLE_SETTINGS, SSF_GET_COLORS, sc, sizeof.system_colors
        mcall   SF_REDRAW, SSF_BEGIN_DRAW

        ; fill palette for icons
        mov     eax, [sc.work_text]
        mov     [icons.palette], eax
        mov     eax, [sc.work_light]
        mov     [icons.palette + 4], eax

        mov     edx, [sc.work]
        or      edx, 0x33000000
        xor     esi, esi
        mov     edi, app_name
        mcall   SF_CREATE_WINDOW, <80, 400>, <100, 250>

        mcall   SF_THREAD_INFO, pi, -1

        ; prevent drawing if the window is collapsed
        test    [pi.wnd_state], 0x04
        jnz     .end_redraw

        ; prevent resize if smaller
        xor     eax, eax
        mov     ebx, [pi.box.width]
        mov     ecx, [pi.box.height]
        mov     edx, [pi.client_box.width]
        mov     esi, [pi.client_box.height]
        sub     ebx, edx
        sub     ecx, esi

        cmp     edx, WIN_MIN_WIDTH
        jae     .width_ok
        inc     eax
        mov     edx, WIN_MIN_WIDTH
    .width_ok:
        add     edx, ebx

        cmp     esi, WIN_MIN_HEIGHT
        jae     .height_ok
        inc     eax
        mov     esi, WIN_MIN_HEIGHT
    .height_ok:
        add     esi, ecx
        test    eax, eax
        jz      @f
        mcall   SF_CHANGE_WINDOW, -1, -1
        jmp     .end_redraw
    @@:

        mcall   SF_DEFINE_BUTTON, <1, 24>, <5, 24>, BTN_SETUP, [sc.work_light]
        mcall   SF_DEFINE_BUTTON, <30, 24>, <5, 24>, BTN_CONN, [sc.work_light]
        mcall   SF_DEFINE_BUTTON, <59, 24>, <5, 24>, BTN_CLEAR, [sc.work_light]

        mcall   SF_PUT_IMAGE_EXT, icons, <20, 20>, <3, 7>, 1, icons.palette, 0
        mcall   SF_PUT_IMAGE_EXT, icons + 180, <20, 20>, <61, 7>, 1, icons.palette, 0

        mov     ebx, icons + 60 ; disconnected icon
        mov     al, [is_connected]
        test    al, al
        jz      @f
        add     ebx, 60 ; connected icon
    @@:
        mcall   SF_PUT_IMAGE_EXT, , <20, 20>, <32, 7>, 1, icons.palette, 0

        ; text view
        mov     eax, [sc.work_light]
        mov     [text_view.bg_color], eax
        mov     eax, [sc.work_text]
        mov     [text_view.fg_color], eax

        xor     eax, eax
        mov     [text_view.left], eax
        add     eax, SCROLL_TOP
        mov     [text_view.top], eax
        mov     eax, [pi.client_box.width]
        sub     eax, SCROLL_WIDTH + 4
        mov     [text_view.width], eax
        mov     eax, [pi.client_box.height]
        sub     eax, 2 * FONT_HEIGHT + WIN_BORDER_WIDTH + 14 + SCROLL_TOP
        mov     [text_view.height], eax
        stdcall text_view_draw, text_view

        ; scrollbar

        mov     [vscroll.all_redraw], 1

        mov     eax, [sc.work]
        mov     [vscroll.bg_color], eax
        mov     eax, [sc.work_button]
        mov     [vscroll.front_color], eax
        mov     eax, [sc.work_text]
        mov     [vscroll.line_color], eax
        mov     [vscroll.type], 0

        mov     eax, [pi.client_box.width]
        sub     eax, SCROLL_WIDTH + 2
        mov     [vscroll.x_pos], ax
        mov     eax, [pi.client_box.height]
        sub     eax, 2 * FONT_HEIGHT + WIN_BORDER_WIDTH + 14 + SCROLL_TOP
        mov     [vscroll.y_size], ax

        call    update_vscroll
        invoke  scrollbar_draw, vscroll

        ; editbox and send button

        edit_boxes_set_sys_color main_win_edits_start, main_win_edits_end, sc
        mov     eax, [pi.client_box.width]
        sub     eax, 46
        mov     [ed_send.width], eax
        mov     eax, [pi.client_box.height]
        sub     eax, 2 * FONT_HEIGHT + WIN_BORDER_WIDTH + 10
        mov     [ed_send.top], eax
        invoke  edit_box_draw, ed_send

        mov     ebx, [pi.client_box.width]
        sub     ebx, 42
        shl     ebx, 16
        add     ebx, 40
        mov     ecx, [pi.client_box.height]
        sub     ecx, 2 * FONT_HEIGHT + WIN_BORDER_WIDTH + 10
        shl     ecx, 16
        add     ecx, FONT_HEIGHT + 4
        mcall   SF_DEFINE_BUTTON, , , BTN_SEND, [sc.work_button]

        add     ebx, 4 shl 16
        mov     bx, word [pi.client_box.height]
        sub     bx, 2 * FONT_HEIGHT + WIN_BORDER_WIDTH + 7
        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, , , send_label

        ; status bar

        mov	    ebx, [pi.client_box.width]
        mov     edx, [pi.client_box.height]
        sub     edx, FONT_HEIGHT + WIN_BORDER_WIDTH
        mov     ecx, edx
        shl     ecx, 16
        mov     cx, dx
        mov     edx, [sc.work_graph]
        mcall   SF_DRAW_LINE

        mov     ebx, [pi.client_box.height]
        sub     ebx, FONT_HEIGHT
        mov     ecx, 0x90000000
        or      ecx, [sc.work_text]
        mov     edx, [status_msg]
        mcall   SF_DRAW_TEXT

    .end_redraw:
        mcall   SF_REDRAW, SSF_END_DRAW
        ret

CONN_WIN_WIDTH = 200
CONN_WIN_HEIGHT = 250
proc show_conn_window
        cmp     [is_conn_win_opened], 1
        jne     @f
        mcall   SF_SYSTEM, SSF_GET_THREAD_SLOT, [conn_win_pid]
        xchg    eax, ecx
        mcall   SF_SYSTEM, SSF_FOCUS_WINDOW
        ret
    @@:
        mcall   SF_CREATE_THREAD, 1, .thread, conn_win_stack + CONN_WIN_STACK_SIZE
        cmp     eax, -1
        je      @f
        mov     [conn_win_pid], eax
        mov     [is_conn_win_opened], 1
    @@:
        ret
    .thread:
        mcall   SF_SET_EVENTS_MASK, EVM_MOUSE + EVM_MOUSE_FILTER + EVM_REDRAW + EVM_BUTTON + EVM_KEY

        mov     eax, [port_num]
        mov     ecx, 10
        mov     edi, ed_port_val
        call    int_to_str
        and     byte [edi], 0
        mov     esi, ed_port_val
        call    strlen
        mov     [ed_port.size], eax
        mov     [ed_port.pos], eax

        mov     eax, [port_conf + 4]
        mov     ecx, 10
        mov     edi, ed_baud_val
        call    int_to_str
        and     byte [edi], 0
        mov     esi, ed_baud_val
        call    strlen
        mov     [ed_baud.size], eax

        call    .draw_window
    .loop:
        mcall   SF_WAIT_EVENT
        dec     eax
        jz      .win
        dec     eax
        jz      .key
        dec     eax
        jz      .btn
        invoke  edit_box_mouse, ed_port
        invoke  edit_box_mouse, ed_baud
        jmp     .loop
    .win:
        call    .draw_window
        jmp     .loop
    .key:
        mcall   SF_GET_KEY
        invoke  edit_box_key, ed_port
        invoke  edit_box_key, ed_baud
        jmp     .loop
    .btn:
        mcall   SF_GET_BUTTON
        cmp     ah, BTN_OK
        jne     @f
        mov     esi, ed_port_val
        call    str_to_uint
        mov     [port_num], ebx
        mov     esi, ed_baud_val
        call    str_to_uint
        mov     [port_conf + 4], ebx
    @@:
        and     [is_conn_win_opened], 0
        mcall   SF_TERMINATE_PROCESS

    .draw_window:
        mcall   SF_REDRAW, SSF_BEGIN_DRAW

        mov     edx, [sc.work]
        or      edx, 0x34000000
        mov     esi, [sc.work]
        mov     edi, conn_win_name

        mov     ebx, [pi.box.width]
        shr     ebx, 1
        add     ebx, [pi.box.left]
        sub     ebx, CONN_WIN_WIDTH / 2
        shl     ebx, 16
        add     ebx, CONN_WIN_WIDTH

        mov     ecx, [pi.box.height]
        shr     ecx, 1
        add     ecx, [pi.box.top]
        sub     ecx, CONN_WIN_HEIGHT / 2
        shl     ecx, 16
        add     ecx, CONN_WIN_HEIGHT

        mcall   SF_CREATE_WINDOW

        mov     ecx, 0x90000000
        or      ecx, [sc.work_text]
        mov     edx, port_label
        mcall   SF_DRAW_TEXT, <0, 13>
        mov     edx, baud_label
        mcall   SF_DRAW_TEXT, <0, 45>

        edit_boxes_set_sys_color conn_win_edits_start, conn_win_edits_end, sc
        invoke  edit_box_draw, ed_port
        invoke  edit_box_draw, ed_baud

        mcall   SF_DEFINE_BUTTON, <CONN_WIN_WIDTH - 137, 60>, \
                                  <CONN_WIN_HEIGHT - 55, 24>, BTN_OK, \
                                  [sc.work_button]

        mcall   SF_DEFINE_BUTTON, <CONN_WIN_WIDTH - 71, 60>, \
                                  <CONN_WIN_HEIGHT - 55, 24>, BTN_CANCEL, \
                                  [sc.work_button]

        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, <CONN_WIN_WIDTH - 114, CONN_WIN_HEIGHT - 50>, , ok_label

        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, <CONN_WIN_WIDTH - 65, CONN_WIN_HEIGHT - 50>, , cancel_label

        mcall   SF_REDRAW, SSF_END_DRAW
        ret
endp

proc send_text
        ; check for empty string
        cmp     byte [ed_send_val], 0
        jz      .exit
        cmp     [is_connected], 0
        jz      .exit
        or      eax, 1
        mov     edi, ed_send_header
        call    make_line_header
        mov     esi, ed_send_val
        call    strlen
        mov     [tx_buf_cnt], eax
        stdcall serial_port_write, [port_handle], ed_send_val, tx_buf_cnt
        ; TODO check for errors and actual size of written data
        stdcall text_view_append_line, text_view, ed_send_header, TV_FLAG_AUTOSCROLL
        xor     eax, eax
        push    eax
        invoke  edit_box_set_text, ed_send, esp
        pop     eax
        stdcall text_view_draw, text_view
        invoke  edit_box_draw, ed_send
        call    update_vscroll
        invoke  scrollbar_draw, vscroll
    .exit:
        ret
endp

proc update_vscroll
        mov     eax, [text_view.total_lines]
        mov     [vscroll.max_area], eax
        mov     eax, [text_view.rows]
        mov     [vscroll.cur_area], eax
        mov     eax, [text_view.curr_line]
        mov     [vscroll.position], eax
        ret
endp

proc btn_conn_click
        cmp     [is_connected], 0
        jnz     .close
        lea     eax, [port_conf]
        lea     ebx, [port_handle]
        stdcall serial_port_open, [port_num], eax, ebx
        mov     [status_msg], status_ver
        test    eax, eax
        jz      .opened
        mov     [status_msg], err_port
        cmp     eax, SERIAL_API_ERR_PORT_INVALID
        jz      .exit
        mov     [status_msg], err_busy
        cmp     eax, SERIAL_API_ERR_PORT_BUSY
        jz      .exit
        mov     [status_msg], err_conf
        cmp     eax, SERIAL_API_ERR_CONF
        jz      .exit
        mov     [status_msg], err_unknown
        jmp     .exit
    .opened:
        mov     [is_connected], 1
        mov     esi, port_label
        mov     edi, port_status
        mov     ecx, 4
        cld
        rep     movsb
        mov     eax, [port_num]
        mov     ecx, 10
        call    int_to_str
        mov     al, ' '
        stosb
        mov     eax, [port_conf + 4]
        mov     ecx, 10
        call    int_to_str
        mov     eax, ' 8n1'
        stosd
        xor     al, al
        stosb
        mov     [status_msg], port_status
        jmp     .exit
    .close:
        stdcall serial_port_close, [port_handle]
        and     [is_connected], 0
        mov     [status_msg], status_ver
    .exit:
        ret
endp

proc check_port
        mov     [rx_buf_cnt], RX_BUF_SIZE - 1
        stdcall serial_port_read, [port_handle], rx_buf, rx_buf_cnt
        ; TODO check eax for errors
        mov     eax, [rx_buf_cnt]
        test    eax, eax
        jz      .exit
        ; TODO escape non-print chars
        lea     esi, [rx_buf + eax]
        mov     byte [esi], 0
        xor     eax, eax
        mov     edi, rx_header
        call    make_line_header
        stdcall text_view_append_line, text_view, rx_header, TV_FLAG_AUTOSCROLL
        stdcall text_view_draw, text_view
        call    update_vscroll
        invoke  scrollbar_draw, vscroll
    .exit:
        ret
endp

proc make_line_header
; eax = 0 - rx, 1 - tx
; edi = dest buf
        push    eax
        mcall   SF_GET_SYS_TIME
        mov     ebx, eax
        mov     ecx, 3
        ; BCD timestamp to string
    .loop:
        mov     al, bl
        shr     al, 4
        add     al, '0'
        stosb
        mov     al, bl
        and     al, 0x0f
        add     al, '0'
        stosb
        dec     ecx
        jz      .done
        mov     al, ':'
        stosb
        shr     ebx, 8
        jmp     .loop
    .done:
        mov     al, ' '
        stosb
        mov     al, '<'
        pop     ebx
        test    ebx, ebx
        jz      @f
        mov     al, '>'
    @@:
        stosb
        mov     al, ' '
        stosb
        ret
endp

align 16
@IMPORT:

library box_lib, 'box_lib.obj'

import  box_lib,\
        edit_box_draw,          'edit_box_draw',\
        edit_box_key,           'edit_box_key',\
        edit_box_mouse,         'edit_box_mouse',\
        edit_box_set_text,      'edit_box_set_text',\
        scrollbar_draw,         'scrollbar_v_draw',\
        scrollbar_mouse,        'scrollbar_v_mouse'

conn_win_edits_start:
ed_port         edit_box 80, CONN_WIN_WIDTH - 80 - 11, 10, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_port_val, mouse_dd, \
                         ed_focus + ed_figure_only
ed_baud         edit_box 80, CONN_WIN_WIDTH - 80 - 11, 42, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_baud_val, mouse_dd, \
                         ed_figure_only
conn_win_edits_end:
main_win_edits_start:
ed_send         edit_box 0, 0, 0, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, ED_SEND_MAX_LEN - 1, ed_send_val, mouse_dd, \
                         ed_focus + ed_always_focus, 0, 0
main_win_edits_end:

vscroll         scrollbar SCROLL_WIDTH, 0, 0, SCROLL_TOP, SCROLL_WIDTH, 0, 0, 0, 0, 0, 0, 1
text_view       TEXT_VIEW

is_connected    db 0
is_conn_win_opened db 0
app_name        db 'kterm', 0
conn_win_name   db 'Settings', 0
port_label      db 'Port:', 0
baud_label      db 'Baud:', 0
ok_label        db 'Ok', 0
cancel_label    db 'Cancel', 0
send_label      db 'Send', 0
status_msg      dd status_ver
status_ver      db 'v0.1.1', 0
err_port        db 'Invalid serial port.', 0
err_busy        db 'The port is already in use.', 0
err_conf        db 'Invalid port configuration.', 0
err_unknown     db 'An unknown error occured.', 0
err_driver      db 'Error loading driver serial.sys.', 0
port_num        dd 0
port_conf:
        dd      port_conf_end - port_conf
        dd      9600
        db      8, 1, SERIAL_CONF_PARITY_NONE, SERIAL_CONF_FLOW_CTRL_NONE
port_conf_end:

if __DEBUG__ eq 1
    include_debug_strings
end if

; https://javl.github.io/image2cpp/
icons:
    ; 'icons', 20x80px
    db 0xff, 0xff, 0xf0, 0xfc, 0x7f, 0xf0, 0xf8, 0x3f, 0xf0, 0xf8, 0x1f, 0xf0, 0xfe, 0x1f, 0xf0, 0xdf
    db 0x1f, 0xf0, 0x8e, 0x1f, 0xf0, 0xa4, 0x3f, 0xf0, 0x90, 0x1f, 0xf0, 0xc8, 0x0f, 0xf0, 0xe0, 0x07
    db 0xf0, 0xfe, 0x43, 0xf0, 0xff, 0x21, 0xf0, 0xff, 0x90, 0xf0, 0xff, 0xc8, 0x70, 0xff, 0xe4, 0x30
    db 0xff, 0xf0, 0x70, 0xff, 0xf8, 0xf0, 0xff, 0xfd, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff
    db 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xfe, 0xf7, 0xf0, 0xfc, 0xf3, 0xf0, 0xf8, 0xf1
    db 0xf0, 0xf8, 0xf1, 0xf0, 0xf0, 0x78, 0xf0, 0x80, 0x78, 0x10, 0x80, 0x78, 0x10, 0xf0, 0x78, 0xf0
    db 0xf8, 0xf1, 0xf0, 0xf8, 0xf1, 0xf0, 0xfc, 0xf3, 0xf0, 0xfe, 0xf7, 0xf0, 0xff, 0xff, 0xf0, 0xff
    db 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff
    db 0xf0, 0xff, 0xff, 0xf0, 0xff, 0x9f, 0xf0, 0xff, 0x0f, 0xf0, 0xfe, 0x07, 0xf0, 0xfe, 0x07, 0xf0
    db 0xfc, 0x03, 0xf0, 0x80, 0x00, 0x10, 0x80, 0x00, 0x10, 0xfc, 0x03, 0xf0, 0xfe, 0x07, 0xf0, 0xfe
    db 0x07, 0xf0, 0xff, 0x0f, 0xf0, 0xff, 0x9f, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff
    db 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xe3, 0xf0
    db 0xff, 0xc9, 0xf0, 0xff, 0x9c, 0xf0, 0xff, 0x3e, 0x70, 0xfe, 0x7f, 0x70, 0xfc, 0x7f, 0x70, 0xf9
    db 0x3e, 0x70, 0xf3, 0x9c, 0xf0, 0xe7, 0xc9, 0xf0, 0xef, 0xe3, 0xf0, 0xe7, 0xe7, 0xf0, 0xf3, 0xcf
    db 0xf0, 0xf9, 0x9f, 0xf0, 0xfc, 0x00, 0x70, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0, 0xff, 0xff, 0xf0
.palette:
    dd 0xffffff
    dd 0x000000

i_end:
ed_port_val     rb 7
ed_baud_val     rb 7
ed_send_header  rb LINE_HEADER_LEN
ed_send_val     rb ED_SEND_MAX_LEN
mouse_dd        dd ?
conn_win_pid    dd ?
port_handle     dd ?
port_status     rb PORT_STATUS_LEN
rx_header       rb LINE_HEADER_LEN
rx_buf          rb RX_BUF_SIZE
rx_buf_cnt      dd ?
tx_buf_cnt      dd ?
sc              system_colors
pi              process_information
conn_win_stack  rb CONN_WIN_STACK_SIZE