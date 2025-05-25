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

WIN_MARGIN = 5
WIN_MIN_WIDTH = 150
WIN_MIN_HEIGHT = 200
TOOL_ICON_SIZE = 18
TOOL_BTN_SIZE = 24 ; width and height
SEND_BTN_WIDTH = 40
ED_HEIGHT = 22
FONT_WIDTH = 8
FONT_HEIGHT = 16
SCROLL_WIDTH = 16
SCROLL_TOP = WIN_MARGIN + TOOL_BTN_SIZE + WIN_MARGIN
RX_BUF_SIZE = 256
LINE_HEADER_LEN = 11
PORT_STATUS_LEN = 128
ED_SEND_MAX_LEN = 256

KEY_ENTER = 13

IMG_RGB_METADATA_SIZE = 8
ICON_SIZE_BYTES = TOOL_ICON_SIZE * TOOL_ICON_SIZE * 3
ICON_SETUP_OFFSET = IMG_RGB_METADATA_SIZE + ICON_SIZE_BYTES * 60
ICON_CONN_OFFSET = IMG_RGB_METADATA_SIZE + ICON_SIZE_BYTES * 4
ICON_CLEAR_OFFSET = IMG_RGB_METADATA_SIZE + ICON_SIZE_BYTES * 63

BTN_CLOSE = 1
BTN_SETUP = 2
BTN_CONN = 3
BTN_CLEAR = 4
BTN_SEND = 5

BTN_OK = 2
BTN_CANCEL = 3

L_DBG = 0
L_ERR = 1

__DEBUG__ = 1
__DEBUG_LEVEL__ = L_ERR

include '../../proc32.inc'
include '../../macros.inc'
include '../../KOSfuncs.inc'
include '../../dll.inc'
include '../../debug-fdo.inc'
include '../../develop/libraries/box_lib/trunk/box_lib.mac'
include '../../../drivers/serial/common.inc'

include 'settings.inc'
include 'textview.inc'
include 'utils.inc'

start:
        mcall   SF_SYS_MISC, SSF_HEAP_INIT

        call    serial_port_init
        test    eax, eax
        jnz     @f
        DEBUGF  L_ERR, "kterm: %s\n", err_driver
        mov     eax, err_driver
        mov     [status_msg], eax
    @@:
        push    0
        stdcall serial_port_get_version, esp
        pop     eax
        DEBUGF  L_DBG, "kterm: serial driver version 0x%x\n", eax
        shr     eax, 16
        cmp     ax, SERIAL_COMPATIBLE_API_VER
        jle     @f
        mov     eax, err_driver_ver
        mov     [status_msg], eax
    @@:
        stdcall dll.Load, @IMPORT
        or      eax, eax
        jnz     .exit

        invoke  img.from_file, icons_file
        test    eax, eax
        jz      @f
        mov     esi, eax
        invoke  img.to_rgb, esi
        mov     [icons_rgb], eax
        invoke  img.destroy, esi
    @@:

        mcall   SF_SET_EVENTS_MASK, EVM_MOUSE + EVM_REDRAW + EVM_BUTTON + EVM_KEY

        mov     byte [ed_send_val], 0
        stdcall text_view_init, text_view
        call    .draw_window

    .loop:
        mov     eax, SF_WAIT_EVENT
        cmp     [is_connected], 0
        jz      @f
        mov     eax, SF_WAIT_EVENT_TIMEOUT
        mov     ebx, 10
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
        call    show_settings_win
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

        mcall   SF_DEFINE_BUTTON, <WIN_MARGIN, TOOL_BTN_SIZE>, \
                                  <WIN_MARGIN, TOOL_BTN_SIZE>, \
                                  BTN_SETUP, 0xffffff
        mcall   SF_DEFINE_BUTTON, <WIN_MARGIN * 2 + TOOL_BTN_SIZE, TOOL_BTN_SIZE>, \
                                  <WIN_MARGIN, TOOL_BTN_SIZE>, \
                                  BTN_CONN, 0xffffff
        mcall   SF_DEFINE_BUTTON, <WIN_MARGIN * 3 + TOOL_BTN_SIZE * 2, TOOL_BTN_SIZE>, \
                                  <WIN_MARGIN, TOOL_BTN_SIZE>, \
                                  BTN_CLEAR, 0xffffff

        mov     ebx, [icons_rgb]
        test    ebx, ebx
        jz      .no_icons

        add     ebx, ICON_SETUP_OFFSET
        mcall   SF_PUT_IMAGE, , <TOOL_ICON_SIZE, TOOL_ICON_SIZE>, \
                                <WIN_MARGIN + 3, WIN_MARGIN + 3>
        mov     ebx, [icons_rgb]
        add     ebx, ICON_CONN_OFFSET
        mcall   SF_PUT_IMAGE, , <TOOL_ICON_SIZE, TOOL_ICON_SIZE>, \
                                <WIN_MARGIN * 2 + TOOL_BTN_SIZE + 3, WIN_MARGIN + 3>
        mov     ebx, [icons_rgb]
        add     ebx, ICON_CLEAR_OFFSET
        mcall   SF_PUT_IMAGE, , <TOOL_ICON_SIZE, TOOL_ICON_SIZE>, \
                                <WIN_MARGIN * 3 + TOOL_BTN_SIZE * 2 + 3, WIN_MARGIN + 3>
    .no_icons:

        ; text view
        mov     eax, 0xffffff
        mov     [text_view.bg_color], eax
        mov     eax, [sc.work_graph]
        mov     [text_view.fg_color], eax
        mov     eax, [sc.work_text]
        mov     [text_view.text_color], eax

        mov     eax, WIN_MARGIN
        mov     [text_view.left], eax
        mov     eax, SCROLL_TOP
        mov     [text_view.top], eax
        mov     eax, [pi.client_box.width]
        sub     eax, SCROLL_WIDTH + WIN_MARGIN * 2 - 1
        mov     [text_view.width], eax
        mov     eax, [pi.client_box.height]
        sub     eax, FONT_HEIGHT + ED_HEIGHT + WIN_MARGIN * 4 + SCROLL_TOP
        mov     [text_view.height], eax
        stdcall text_view_draw, text_view

        ; scrollbar

        mov     [vscroll.all_redraw], 1

        mov     eax, [sc.work_light]
        mov     [vscroll.bg_color], eax
        mov     eax, [sc.work_light]
        mov     [vscroll.front_color], eax
        mov     eax, [sc.work_graph]
        mov     [vscroll.line_color], eax
        mov     [vscroll.type], 0

        mov     eax, [pi.client_box.width]
        sub     eax, SCROLL_WIDTH + WIN_MARGIN
        mov     [vscroll.x_pos], ax
        mov     eax, [pi.client_box.height]
        sub     eax, FONT_HEIGHT + ED_HEIGHT + WIN_MARGIN * 4 + SCROLL_TOP
        mov     [vscroll.y_size], ax

        call    update_vscroll
        invoke  scrollbar_draw, vscroll

        ; editbox and send button

        edit_boxes_set_sys_color main_win_edits_start, main_win_edits_end, sc
        mov     eax, [pi.client_box.width]
        sub     eax, SEND_BTN_WIDTH + WIN_MARGIN * 3
        mov     [ed_send.width], eax
        mov     eax, [pi.client_box.height]
        sub     eax, FONT_HEIGHT + ED_HEIGHT + WIN_MARGIN * 3
        mov     [ed_send.top], eax
        invoke  edit_box_draw, ed_send

        mov     ebx, [pi.client_box.width]
        sub     ebx, SEND_BTN_WIDTH + WIN_MARGIN
        shl     ebx, 16
        add     ebx, SEND_BTN_WIDTH
        mov     ecx, [pi.client_box.height]
        sub     ecx, FONT_HEIGHT + ED_HEIGHT + WIN_MARGIN * 3
        shl     ecx, 16
        add     ecx, FONT_HEIGHT + 5
        mcall   SF_DEFINE_BUTTON, , , BTN_SEND, [sc.work_button]

        add     ebx, 4 shl 16
        mov     bx, word [pi.client_box.height]
        sub     bx, FONT_HEIGHT + ED_HEIGHT + WIN_MARGIN * 3 - 4
        mov     ecx, 0x90000000
        or      ecx, [sc.work_button_text]
        mcall   SF_DRAW_TEXT, , , send_label

        ; status bar

        mov     ebx, WIN_MARGIN shl 16
        add	    ebx, [pi.client_box.width]
        sub     ebx, WIN_MARGIN + 1
        mov     edx, [pi.client_box.height]
        sub     edx, FONT_HEIGHT + WIN_MARGIN * 2
        mov     ecx, edx
        shl     ecx, 16
        mov     cx, dx
        mov     edx, [sc.work_graph]
        mcall   SF_DRAW_LINE

        mov     ebx, WIN_MARGIN shl 16
        add     ebx, [pi.client_box.height]
        sub     ebx, FONT_HEIGHT + WIN_MARGIN
        mov     ecx, 0x90000000
        or      ecx, [sc.work_text]
        mov     edx, [status_msg]
        mcall   SF_DRAW_TEXT

    .end_redraw:
        mcall   SF_REDRAW, SSF_END_DRAW
        ret

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
        call    .append_ending
        mov     [tx_buf_cnt], eax
        stdcall serial_port_write, [port_handle], ed_send_val, tx_buf_cnt
        ; TODO check for errors and actual size of written data
        mov     esi, ed_send_val
        call    escape_chars
        mov     byte [esi], 0
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

    .append_ending:
        cmp     [text_append], SETTINGS_APPEND_NONE
        je      .nothing
        cmp     [text_append], SETTINGS_APPEND_LF
        je      .append_lf
        mov     byte [esi], 0x0d
        inc     esi
        inc     eax
    .append_lf:
        mov     byte [esi], 0x0a
        inc     esi
        inc     eax
    .nothing:
        mov     byte [esi], 0
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
        mov     [status_msg], noconn_msg
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
        ; make string for status
        mov     esi, port_lbl
        mov     edi, port_status
        mov     ecx, 4
        cld
        rep     movsb
        mov     eax, [port_num]
        mov     ecx, 10
        call    int_to_str
        mov     al, ' '
        stosb
        mov     eax, [port_conf + SP_CONF.baudrate]
        mov     ecx, 10
        call    int_to_str
        mov     al, ' '
        stosb
        mov     al, [port_conf + SP_CONF.word_size]
        add     al, '0'
        stosb
        mov     eax, 'n1'
        stosd
        mov     [status_msg], port_status
        jmp     .exit
    .close:
        stdcall serial_port_close, [port_handle]
        and     [is_connected], 0
        mov     [status_msg], noconn_msg
    .exit:
        ret
endp

proc check_port
        mov     [rx_buf_cnt], RX_BUF_SIZE - 1
        stdcall serial_port_read, [port_handle], rx_buf, rx_buf_cnt
        test    eax, eax
        jnz     .error
        mov     ecx, [rx_buf_cnt]
        test    ecx, ecx
        jz      .exit
        mov     esi, rx_buf
        call    escape_chars
        mov     byte [esi], 0
        xor     eax, eax
        mov     edi, rx_header
        call    make_line_header
        stdcall text_view_append_line, text_view, rx_header, TV_FLAG_AUTOSCROLL
        stdcall text_view_draw, text_view
        call    update_vscroll
        invoke  scrollbar_draw, vscroll
        jmp     .exit
    .error:
        ; the port was closed
        mov     eax, noconn_msg
        mov     [status_msg], eax
        mov     [is_connected], 0
        call    start.draw_window ; TODO redraw status only
    .exit:
        ret
endp

align 16
@IMPORT:

library box_lib, 'box_lib.obj',\
        libimg,  'libimg.obj'

import  box_lib,\
        edit_box_draw,          'edit_box_draw',\
        edit_box_key,           'edit_box_key',\
        edit_box_mouse,         'edit_box_mouse',\
        edit_box_set_text,      'edit_box_set_text',\
        scrollbar_draw,         'scrollbar_v_draw',\
        scrollbar_mouse,        'scrollbar_v_mouse',\
        option_box_draw,        'option_box_draw',\
        option_box_mouse,       'option_box_mouse'

import  libimg,\
        libimg.init,            'lib_init',\
        img.from_file,          'img_from_file',\
        img.to_rgb,             'img_to_rgb',\
        img.destroy,            'img_destroy'


main_win_edits_start:
ed_send         edit_box 0, WIN_MARGIN, 0, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, ED_SEND_MAX_LEN - 3, ed_send_val, mouse_dd, \
                         ed_focus + ed_always_focus, 0, 0
main_win_edits_end:

vscroll         scrollbar SCROLL_WIDTH, 0, 0, SCROLL_TOP, SCROLL_WIDTH, 0, 0, 0, 0, 0, 0, 1
text_view       TEXT_VIEW

is_connected    db 0
app_name        db 'kterm v0.2.0', 0
send_label      db 'Send', 0
noconn_msg      db 'Not connected', 0
icons_file      db '/sys/icons16.png', 0
err_port        db 'Invalid serial port', 0
err_busy        db 'The port is already in use', 0
err_conf        db 'Invalid port configuration', 0
err_unknown     db 'An unknown error occured', 0
err_driver      db 'Error loading driver serial.sys', 0
err_driver_ver  db 'Error serial driver version', 0

align 4
status_msg      dd noconn_msg
port_num        dd 0
icons_rgb       dd 0
port_conf:
        dd      port_conf_end - port_conf
        dd      9600
        db      8, SERIAL_CONF_STOP_BITS_1, SERIAL_CONF_PARITY_NONE, SERIAL_CONF_FLOW_CTRL_NONE
port_conf_end:
text_append     db SETTINGS_APPEND_LF

IncludeIGlobals

include_debug_strings

align 4
i_end:
IncludeUGlobals
mouse_dd        dd ?
port_handle     dd ?
rx_buf_cnt      dd ?
tx_buf_cnt      dd ?
ed_send_header  rb LINE_HEADER_LEN
ed_send_val     rb ED_SEND_MAX_LEN
port_status     rb PORT_STATUS_LEN
rx_header       rb LINE_HEADER_LEN
rx_buf          rb RX_BUF_SIZE
sc              system_colors
pi              process_information
