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

WIN_BORDER_WIDTH = 5
FONT_HEIGHT = 16
CONN_WIN_STACK_SIZE = 1024
BTN_CLOSE = 1
BTN_SETUP = 2
BTN_CONN = 3

__DEBUG__ = 0
__DEBUG_LEVEL__ = 0

include '../../proc32.inc'
include '../../macros.inc'
include '../../KOSfuncs.inc'
include '../../dll.inc'
include '../../debug-fdo.inc'
include '../../develop/libraries/box_lib/trunk/box_lib.mac'
include '../../../drivers/serial/common.inc'
include 'utils.asm'

start:
        mcall   SF_SYS_MISC, SSF_HEAP_INIT
        call    serial_port_init

        stdcall dll.Load, @IMPORT
        or      eax, eax
        jnz     .exit

        mcall   SF_SET_EVENTS_MASK, EVM_MOUSE + EVM_MOUSE_FILTER + EVM_REDRAW + EVM_BUTTON + EVM_KEY

        call    .draw_window

.loop:
        mcall   SF_WAIT_EVENT
        dec     eax
        jz      .win
        dec     eax
        jz      .key
        dec     eax
        jz      .btn
        jmp     .loop
.win:
        call    .draw_window
        jmp     .loop
.key:
        mcall   SF_GET_KEY
        jmp     .loop
.btn:
        mcall   SF_GET_BUTTON
        cmp     ah, BTN_CONN
        jne     @f
        xor     [is_connected], 0xff
        call    .draw_window
        jmp     .loop
    @@:
        cmp     ah, BTN_SETUP
        jne     @f
        call    show_conn_window
        jmp     .loop
    @@:
        cmp     ah, BTN_CLOSE
        jne     .loop
.exit:
        mcall   SF_TERMINATE_PROCESS
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

        mcall   SF_DEFINE_BUTTON, <1, 24>, <5, 24>, BTN_SETUP, [sc.work_light]
        mcall   SF_DEFINE_BUTTON, <30, 24>, <5, 24>, BTN_CONN, [sc.work_light]
        mcall   SF_DEFINE_BUTTON, <59, 24>, <5, 24>, 123, [sc.work_light]

        mcall   SF_PUT_IMAGE_EXT, icons, <20, 20>, <3, 7>, 1, icons.palette, 0

        mov     ebx, icons + 60 ; disconnected icon
        mov     al, [is_connected]
        test    al, al
        jz      @f
        add     ebx, 60 ; connected icon
    @@:
        mcall   SF_PUT_IMAGE_EXT, , <20, 20>, <32, 7>, 1, icons.palette, 0

        ; TODO limit minimum window size

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
        mov     edx, status_msg
        mcall   SF_DRAW_TEXT

.end_redraw:
        mcall   SF_REDRAW, SSF_END_DRAW
        ret

CONN_WIN_WIDTH = 200
CONN_WIN_HEIGHT = 250
show_conn_window:
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
        cmp     ah, BTN_CLOSE
        jne     .loop
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

        edit_boxes_set_sys_color win_conn_edits_start, win_conn_edits_end, sc
        invoke  edit_box_draw, ed_port
        invoke  edit_box_draw, ed_baud

        mcall   SF_REDRAW, SSF_END_DRAW
        ret

align 16
@IMPORT:

library box_lib, 'box_lib.obj'

import  box_lib,\
        edit_box_draw,          'edit_box_draw',\
        edit_box_key,           'edit_box_key',\
        edit_box_mouse,         'edit_box_mouse'

win_conn_edits_start:
ed_port         edit_box 80, CONN_WIN_WIDTH - 80 - 11, 10, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_port_val, mouse_dd, \
                         ed_focus + ed_figure_only
ed_baud         edit_box 80, CONN_WIN_WIDTH - 80 - 11, 42, 0xffffff, 0x6f9480, \
                         0, 0, 0x10000000, 6, ed_baud_val, mouse_dd, \
                         ed_figure_only
win_conn_edits_end:

is_connected    db 0
is_conn_win_opened db 0
app_name        db 'kterm', 0
conn_win_name   db 'Settings', 0
port_label      db 'Port:', 0
baud_label      db 'Baud:', 0
status_msg      db ' ', 0
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
    ; 'icons', 20x60px
    db 0xff, 0xff, 0xf0, 0xfc, 0xff, 0xf0, 0xf8, 0x3f, 0xf0, 0xf8, 0x1f, 0xf0, 0xfe, 0x1f, 0xf0, 0xdf
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
    db 0xf0, 0xff, 0xff, 0xf0
.palette:
    dd 0xffffff
    dd 0x000000

i_end:
ed_port_val     rb 7
ed_baud_val     rb 7
mouse_dd        dd ?
conn_win_pid    dd ?
sc              system_colors
pi              process_information
conn_win_stack  rb CONN_WIN_STACK_SIZE