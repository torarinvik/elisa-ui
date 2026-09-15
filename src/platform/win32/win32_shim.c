// elisa-ui Win32 backend: the widget tree as real Windows controls.
//
// THE LAST COLUMN OF THE SEAM'S MAPPING TABLE. It named HWND, BUTTON, EDIT and
// msctls_progress32 for years with no backend behind them, which made the table
// read as a list of platforms that had native controls when two of them did
// not. GTK closed the Linux half; this closes the Windows one.
//
// HONEST ABOUT ITS EVIDENCE. This is cross-compiled with mingw-w64 and never
// run: there is no Windows machine here and no emulator for one. That is the
// same standard check_uikit.sh already holds the iOS DEVICE build to -- it
// links an image nothing executes, because a successful link is what proves the
// shim and the Elisa exports agree on an ABI. It proves the binding compiles
// against the real headers and resolves against the real import libraries. It
// does not prove a window ever appeared, and the gate says so.
//
// ABSOLUTE PLACEMENT. Win32 is the one toolkit here that wanted nothing
// special for it: every control is a child HWND positioned with MoveWindow in
// its parent's client coordinates, which is exactly the model UiWidgets::layout
// already produces.

#include <windows.h>
#include <commctrl.h>
#include <stdint.h>
#include <string.h>
#include "../common/utf8_utf16.h"

static const wchar_t *ELISA_PANEL_CLASS = L"ElisaUiPanel";
enum { ELISA_WIN32_TEXT_UNITS = 1024, ELISA_WIN32_UTF8_BYTES = 3 * ELISA_WIN32_TEXT_UNITS + 1 };

// Win32 text is UTF-16. The framework carries UTF-8, so it converts here
// rather than anywhere a wide string could leak into the seam -- and uses the
// W entry points throughout, because the A ones would put the user's text
// through whatever code page the machine happens to have.
static wchar_t *to_wide(const char *utf8, wchar_t *buffer, int capacity) {
    if (utf8 == NULL) { buffer[0] = L'\0'; return buffer; }
    int written = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, buffer, capacity);
    if (written <= 0) buffer[0] = L'\0';
    return buffer;
}

static HWND hwnd_of(size_t handle) { return (HWND)(void *)handle; }

static int color_slot_of(HWND control);
static LRESULT color_reply(HDC context, int slot);
static void forget_color_slot(HWND control);
static void forget_help_slot(HWND control);

// Elisa resolves the control back to an index and decides what an action
// means; this window procedure only reports that one happened.
extern int32_t elisa_win32_action(size_t handle, float value, int32_t selected);
extern int32_t elisa_win32_text_action(size_t handle, const char *text);

static LRESULT CALLBACK elisa_window_proc(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_COMMAND) {
        HWND control = (HWND)l;
        const WORD code = HIWORD(w);
        if (control != NULL && (code == BN_CLICKED)) {
            // A check or radio reports its own new state; the seam turns the
            // siblings off, because the group is the list's knowledge.
            const LRESULT checked = SendMessageW(control, BM_GETCHECK, 0, 0);
            (void)elisa_win32_action((size_t)(void *)control, 0.0f, checked == BST_CHECKED ? 1 : 0);
            return 0;
        }
        if (control != NULL && code == EN_CHANGE) {
            // Up to three UTF-8 bytes per UTF-16 code unit (surrogate pairs
            // use four bytes for two units). Terminate at the converter's byte
            // count, never the code-unit count returned by GetWindowTextW.
            char utf8[ELISA_WIN32_UTF8_BYTES];
            wchar_t wide[ELISA_WIN32_TEXT_UNITS];
            const int units = GetWindowTextW(control, wide, ELISA_WIN32_TEXT_UNITS);
            const size_t bytes = elisa_utf16_to_utf8((const uint16_t *)wide,
                units > 0 ? (size_t)units : 0, (uint8_t *)utf8, sizeof(utf8) - 1);
            utf8[bytes] = '\0';
            (void)elisa_win32_text_action((size_t)(void *)control, utf8);
            memset(utf8, 0, sizeof(utf8));
            memset(wide, 0, sizeof(wide));
            return 0;
        }
    }
    if (message == WM_HSCROLL) {
        HWND control = (HWND)l;
        if (control != NULL) {
            const LRESULT position = SendMessageW(control, TBM_GETPOS, 0, 0);
            (void)elisa_win32_action((size_t)(void *)control, (float)position, 0);
            return 0;
        }
    }
    // Windows asks the parent what colour a child should be, once per repaint.
    // A control the framework never coloured is not in the table and falls
    // through to DefWindowProc, which is what keeps it looking like Windows.
    if (message == WM_CTLCOLORSTATIC || message == WM_CTLCOLOREDIT ||
        message == WM_CTLCOLORBTN || message == WM_CTLCOLORLISTBOX) {
        const int slot = color_slot_of((HWND)l);
        if (slot >= 0) return color_reply((HDC)w, slot);
    }
    // Child panels and scroll containers use this same class. Only the
    // top-level window owns the message loop; posting WM_QUIT for a child
    // teardown would terminate a live application while its tree is merely
    // being reconciled.
    if (message == WM_DESTROY) {
        if (GetParent(window) == NULL) PostQuitMessage(0);
        return 0;
    }
    if (message == WM_NCDESTROY) {
        // HWND values are reusable. Forget the entry at the final lifetime
        // boundary so a later control cannot inherit stale colours and the
        // associated GDI brush is released exactly once.
        forget_color_slot(window);
        forget_help_slot(window);
    }
    return DefWindowProcW(window, message, w, l);
}

int32_t elisa_win32_init(void) {
    WNDCLASSEXW cls;
    ZeroMemory(&cls, sizeof(cls));
    cls.cbSize = sizeof(cls);
    cls.lpfnWndProc = elisa_window_proc;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.hCursor = LoadCursorW(NULL, IDC_ARROW);
    cls.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    cls.lpszClassName = ELISA_PANEL_CLASS;
    if (RegisterClassExW(&cls) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 0;
    INITCOMMONCONTROLSEX controls;
    controls.dwSize = sizeof(controls);
    controls.dwICC = ICC_BAR_CLASSES | ICC_PROGRESS_CLASS | ICC_STANDARD_CLASSES;
    return InitCommonControlsEx(&controls) ? 1 : 0;
}

size_t elisa_win32_create_window(int32_t resizable) {
    const DWORD style = resizable ? WS_OVERLAPPEDWINDOW : (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU);
    HWND window = CreateWindowExW(0, ELISA_PANEL_CLASS, L"", style,
                                  CW_USEDEFAULT, CW_USEDEFAULT, 640, 480,
                                  NULL, NULL, GetModuleHandleW(NULL), NULL);
    return (size_t)(void *)window;
}

// A child HWND of the same class: Win32's own container, and the one the
// framework's absolute boxes fit without translation.
static HWND child(HWND parent, const wchar_t *cls, DWORD style, DWORD extended) {
    return CreateWindowExW(extended, cls, L"", WS_CHILD | WS_VISIBLE | style,
                           0, 0, 10, 10, parent, NULL, GetModuleHandleW(NULL), NULL);
}

size_t elisa_win32_create_panel(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), ELISA_PANEL_CLASS, 0, 0);
}
size_t elisa_win32_create_scroll(size_t parent, int32_t vertical) {
    return (size_t)(void *)child(hwnd_of(parent), ELISA_PANEL_CLASS,
                                 vertical ? WS_VSCROLL : WS_HSCROLL, 0);
}
size_t elisa_win32_create_label(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), L"STATIC", SS_LEFT | SS_ENDELLIPSIS, 0);
}
size_t elisa_win32_create_button(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), L"BUTTON", BS_PUSHBUTTON, 0);
}
size_t elisa_win32_create_check(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), L"BUTTON", BS_AUTOCHECKBOX, 0);
}
size_t elisa_win32_create_radio(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), L"BUTTON", BS_AUTORADIOBUTTON, 0);
}
size_t elisa_win32_create_entry(size_t parent, int32_t secure) {
    // ES_PASSWORD is the property form here, as on iOS, Android and GTK --
    // AppKit is the one platform that needs a different class for it.
    return (size_t)(void *)child(hwnd_of(parent), L"EDIT",
                                 ES_LEFT | ES_AUTOHSCROLL | (secure ? ES_PASSWORD : 0),
                                 WS_EX_CLIENTEDGE);
}
size_t elisa_win32_create_slider(size_t parent, float low, float high, float value) {
    HWND slider = child(hwnd_of(parent), TRACKBAR_CLASSW, TBS_HORZ | TBS_NOTICKS, 0);
    SendMessageW(slider, TBM_SETRANGE, TRUE, MAKELPARAM((int)low, (int)high));
    SendMessageW(slider, TBM_SETPOS, TRUE, (LPARAM)(int)value);
    return (size_t)(void *)slider;
}
size_t elisa_win32_create_progress(size_t parent) {
    return (size_t)(void *)child(hwnd_of(parent), PROGRESS_CLASSW, 0, 0);
}

// ---- COLOUR IS THE PARENT'S ANSWER ---------------------------------------
//
// WIN32 HAS NO SetControlColor, and the conclusion drawn from that here was
// that colouring a control meant drawing it -- which is the one thing a native
// backend exists not to do. That conflated two different mechanisms. Owner-draw
// does mean drawing the control yourself. WM_CTLCOLOR* does not: Windows asks
// the parent for a text colour, a background colour and a brush, and then
// Windows draws the control. It is the platform's own colour affordance, the
// exact counterpart of GTK's CSS, and it was available the whole time.
//
// So the parent answers, from a table this file keeps, and the framework's
// colours arrive without a single pixel being drawn here.
//
// WHAT IT DOES NOT REACH: a themed BS_PUSHBUTTON. Visual styles draw push
// buttons through the theme and never send WM_CTLCOLORBTN, so a push button
// keeps the system's colours. Reaching it needs BS_OWNERDRAW, and that is the
// line -- the caption colour of one control is not worth this backend taking
// over the drawing of it. Labels, edits, check boxes, radios, panels and the
// window all take the colours they are given.
//
// ALPHA IS A MESSAGE, NOT A CHANNEL. GDI controls have no alpha; zero means
// "leave it to Windows", as everywhere else in this seam, and any other value
// means the colour is used opaque.

#define ELISA_WIN32_MAX_COLORED 128

static struct {
    HWND control;
    COLORREF ink;
    COLORREF fill;
    HBRUSH brush;
    int has_ink;
    int has_fill;
} colored[ELISA_WIN32_MAX_COLORED];
static int colored_count;

// A tooltip is the Win32-native help affordance for a child control. Keep its
// text in an Elisa-owned bounded table: TOOLINFO stores the pointer rather than
// copying the string, and the UTF-8 staging buffer in `set_help` is gone as soon
// as that call returns.
#define ELISA_WIN32_MAX_HELP 128
#define ELISA_WIN32_HELP_UNITS 1024
static struct {
    HWND control;
    wchar_t text[ELISA_WIN32_HELP_UNITS];
} help_entries[ELISA_WIN32_MAX_HELP];
static int help_count;
static HWND help_tooltip;

static int help_slot_of(HWND control) {
    for (int slot = 0; slot < help_count; slot++) {
        if (help_entries[slot].control == control) return slot;
    }
    return -1;
}

static HWND ensure_help_tooltip(void) {
    if (help_tooltip != NULL && IsWindow(help_tooltip)) return help_tooltip;
    help_tooltip = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, NULL,
                                   WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX,
                                   CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                                   CW_USEDEFAULT, NULL, NULL, GetModuleHandleW(NULL), NULL);
    return help_tooltip;
}

static TOOLINFOW help_tool(HWND control, wchar_t *text) {
    TOOLINFOW info;
    ZeroMemory(&info, sizeof(info));
    info.cbSize = sizeof(info);
    info.uFlags = TTF_IDISHWND;
    info.hwnd = GetParent(control);
    info.uId = (UINT_PTR)control;
    info.lpszText = text;
    return info;
}

static void forget_help_slot(HWND control) {
    const int slot = help_slot_of(control);
    if (slot < 0) return;
    if (help_tooltip != NULL && IsWindow(help_tooltip)) {
        TOOLINFOW info = help_tool(control, help_entries[slot].text);
        SendMessageW(help_tooltip, TTM_DELTOOLW, 0, (LPARAM)&info);
    }
    ZeroMemory(&help_entries[slot], sizeof(help_entries[slot]));
    help_entries[slot] = help_entries[help_count - 1];
    ZeroMemory(&help_entries[help_count - 1], sizeof(help_entries[0]));
    help_count -= 1;
}

static COLORREF colorref_of(uint32_t argb) {
    return RGB((argb >> 16) & 0xFFu, (argb >> 8) & 0xFFu, argb & 0xFFu);
}

static int color_slot_of(HWND control) {
    for (int slot = 0; slot < colored_count; slot++) {
        if (colored[slot].control == control) return slot;
    }
    return -1;
}

static void forget_color_slot(HWND control) {
    const int slot = color_slot_of(control);
    if (slot < 0) return;
    if (colored[slot].brush != NULL) DeleteObject(colored[slot].brush);
    colored[slot] = colored[colored_count - 1];
    ZeroMemory(&colored[colored_count - 1], sizeof(colored[0]));
    colored_count -= 1;
}

// The answer to one WM_CTLCOLOR*. Returning the brush is not optional: letting
// DefWindowProc answer would put the system's colours back into the DC and
// undo the SetTextColor above it.
static LRESULT color_reply(HDC context, int slot) {
    if (colored[slot].has_ink) SetTextColor(context, colored[slot].ink);
    if (colored[slot].has_fill) {
        SetBkColor(context, colored[slot].fill);
        return (LRESULT)colored[slot].brush;
    }
    SetBkColor(context, GetSysColor(COLOR_WINDOW));
    return (LRESULT)GetSysColorBrush(COLOR_WINDOW);
}

void elisa_win32_set_colors(size_t handle, uint32_t ink, uint32_t fill) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return;
    const int has_ink = ((ink >> 24) & 0xFFu) != 0;
    const int has_fill = ((fill >> 24) & 0xFFu) != 0;
    if (!has_ink && !has_fill) {
        // A transparent pair means "return to the system colours". Do not
        // leave an old brush/record behind: reconciliation can reuse this
        // HWND for another widget, and the GDI object would leak until then.
        forget_color_slot(control);
        InvalidateRect(control, NULL, TRUE);
        return;
    }
    int slot = color_slot_of(control);
    if (slot < 0) {
        if (colored_count == ELISA_WIN32_MAX_COLORED) return;
        slot = colored_count++;
        colored[slot].control = control;
    }
    colored[slot].has_ink = has_ink;
    colored[slot].has_fill = has_fill;
    colored[slot].ink = colorref_of(ink);
    if (has_fill) {
        const COLORREF wanted = colorref_of(fill);
        // One brush per control, replaced only when the colour actually
        // changes -- a GDI object leaked per repaint is the classic way to
        // exhaust a desktop heap.
        if (colored[slot].brush == NULL || colored[slot].fill != wanted) {
            if (colored[slot].brush != NULL) DeleteObject(colored[slot].brush);
            colored[slot].brush = CreateSolidBrush(wanted);
        }
        colored[slot].fill = wanted;
    } else if (colored[slot].brush != NULL) {
        // A later ink-only update must release the fill brush that is no
        // longer reachable from color_reply.
        DeleteObject(colored[slot].brush);
        colored[slot].brush = NULL;
        colored[slot].fill = 0;
    }
    // The colour is only read when Windows next asks for it, so the control
    // has to be told there is something to ask about.
    InvalidateRect(control, NULL, TRUE);
}

// Facts a fixture on a Windows machine can check without a screenshot: the
// table took the colour, and the window procedure answers for that control.
uint32_t elisa_win32_color_reply(size_t handle, int32_t want_ink) {
    const int slot = color_slot_of(hwnd_of(handle));
    if (slot < 0) return 0;
    if (want_ink && !colored[slot].has_ink) return 0;
    if (!want_ink && !colored[slot].has_fill) return 0;
    // A COLORREF is 0x00BBGGRR and the framework speaks ARGB, so this reports
    // the colour the way the caller named it rather than the way GDI stores it.
    const COLORREF value = want_ink ? colored[slot].ink : colored[slot].fill;
    return 0xFF000000u | ((uint32_t)GetRValue(value) << 16) |
           ((uint32_t)GetGValue(value) << 8) | (uint32_t)GetBValue(value);
}

void elisa_win32_set_frame(size_t handle, float x, float y, float width, float height) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return;
    MoveWindow(control, (int)x, (int)y, (int)width, (int)height, TRUE);
}

void elisa_win32_set_text(size_t handle, const char *text) {
    wchar_t wide[1024];
    if (hwnd_of(handle) != NULL) SetWindowTextW(hwnd_of(handle), to_wide(text, wide, 1024));
}

void elisa_win32_set_state(size_t handle, float value, int32_t selected,
                           int32_t enabled, int32_t secure) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return;
    EnableWindow(control, enabled != 0);
    wchar_t cls[64];
    GetClassNameW(control, cls, 64);
    if (lstrcmpiW(cls, L"BUTTON") == 0) {
        SendMessageW(control, BM_SETCHECK, selected ? BST_CHECKED : BST_UNCHECKED, 0);
    } else if (lstrcmpiW(cls, TRACKBAR_CLASSW) == 0) {
        SendMessageW(control, TBM_SETPOS, TRUE, (LPARAM)(int)value);
    } else if (lstrcmpiW(cls, PROGRESS_CLASSW) == 0) {
        SendMessageW(control, PBM_SETPOS, (WPARAM)(int)(value * 100.0f), 0);
    } else if (lstrcmpiW(cls, L"EDIT") == 0) {
        SendMessageW(control, EM_SETPASSWORDCHAR, secure ? (WPARAM)L'*' : 0, 0);
    }
}

// A placeholder is EM_SETCUEBANNER on an EDIT, which is the platform's own
// affordance; help is a real Win32 tooltip. Both are content by the seam's rule
// and neither is the caption. Empty values clear their previous native state.
void elisa_win32_set_help(size_t handle, const char *placeholder, const char *help) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return;
    wchar_t wide[1024];
    wchar_t cls[64];
    GetClassNameW(control, cls, 64);
    if (lstrcmpiW(cls, L"EDIT") == 0) {
        SendMessageW(control, EM_SETCUEBANNER, TRUE, (LPARAM)to_wide(placeholder, wide, 1024));
    }
    if (help == NULL || help[0] == '\0') {
        forget_help_slot(control);
        return;
    }
    int slot = help_slot_of(control);
    if (slot < 0) {
        if (help_count == ELISA_WIN32_MAX_HELP) return;
        slot = help_count++;
        help_entries[slot].control = control;
    } else if (help_tooltip != NULL && IsWindow(help_tooltip)) {
        TOOLINFOW old = help_tool(control, help_entries[slot].text);
        SendMessageW(help_tooltip, TTM_DELTOOLW, 0, (LPARAM)&old);
    }
    to_wide(help, help_entries[slot].text, ELISA_WIN32_HELP_UNITS);
    HWND tooltip = ensure_help_tooltip();
    if (tooltip == NULL) {
        forget_help_slot(control);
        return;
    }
    TOOLINFOW info = help_tool(control, help_entries[slot].text);
    if (!SendMessageW(tooltip, TTM_ADDTOOLW, 0, (LPARAM)&info)) forget_help_slot(control);
}

// Win32 delivers actions to the PARENT through WM_COMMAND, so nothing has to
// be installed per control -- the window procedure above already reports them.
void elisa_win32_set_action(size_t handle) { (void)handle; }

// Facts only a live HWND has, for a fixture on a machine that has one.
int32_t elisa_win32_is_class(size_t handle, const char *name) {
    HWND control = hwnd_of(handle);
    if (control == NULL || name == NULL) return 0;
    wchar_t wanted[64];
    wchar_t actual[64];
    GetClassNameW(control, actual, 64);
    return lstrcmpiW(actual, to_wide(name, wanted, 64)) == 0 ? 1 : 0;
}
int32_t elisa_win32_is_enabled(size_t handle) {
    return hwnd_of(handle) == NULL ? -1 : (IsWindowEnabled(hwnd_of(handle)) ? 1 : 0);
}
int32_t elisa_win32_is_checked(size_t handle) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return -1;
    return SendMessageW(control, BM_GETCHECK, 0, 0) == BST_CHECKED ? 1 : 0;
}
void elisa_win32_destroy_window(size_t handle) {
    if (hwnd_of(handle) != NULL) DestroyWindow(hwnd_of(handle));
}
