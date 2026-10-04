#ifndef ELISA_WIN32_CONTROLS_PRIVACY_H
#define ELISA_WIN32_CONTROLS_PRIVACY_H

#include <windows.h>

BOOL elisa_win32_privacy_apply(HWND control, BOOL sensitive);
BOOL elisa_win32_privacy_is_sensitive(HWND control);
BOOL elisa_win32_privacy_set_help(HWND control, const wchar_t *help);

#endif
