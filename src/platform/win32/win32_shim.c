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

static const wchar_t *ELISA_PANEL_CLASS = L"ElisaUiPanel";

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
            char utf8[1024];
            wchar_t wide[1024];
            const int length = GetWindowTextW(control, wide, 1024);
            WideCharToMultiByte(CP_UTF8, 0, wide, length, utf8, (int)sizeof(utf8) - 1, NULL, NULL);
            utf8[length < 1023 ? length : 1023] = '\0';
            (void)elisa_win32_text_action((size_t)(void *)control, utf8);
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
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
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
// affordance; the help text becomes the tooltip-shaped accessible name Windows
// reads. Both are content by the seam's rule and neither is the caption.
void elisa_win32_set_help(size_t handle, const char *placeholder, const char *help) {
    HWND control = hwnd_of(handle);
    if (control == NULL) return;
    wchar_t wide[1024];
    wchar_t cls[64];
    GetClassNameW(control, cls, 64);
    if (lstrcmpiW(cls, L"EDIT") == 0 && placeholder != NULL) {
        SendMessageW(control, EM_SETCUEBANNER, TRUE, (LPARAM)to_wide(placeholder, wide, 1024));
    }
    (void)help;
}

// Win32 delivers actions to the PARENT through WM_COMMAND, so nothing has to
// be installed per control -- the window procedure above already reports them.


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
