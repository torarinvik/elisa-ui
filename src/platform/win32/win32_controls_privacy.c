#define INITGUID
#define COBJMACROS
#include <windows.h>
#include <commctrl.h>
#include <oleacc.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>
#include "win32_controls_privacy.h"

static const wchar_t *SENSITIVE_PROPERTY = L"ElisaUiSensitive";
static const UINT_PTR PRIVACY_SUBCLASS_ID = 0x454c495341505256u;

static IAccPropServices *begin_services(BOOL *uninitialize) {
    HRESULT apartment = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    *uninitialize = SUCCEEDED(apartment);
    if (FAILED(apartment) && apartment != RPC_E_CHANGED_MODE) return NULL;
    IAccPropServices *services = NULL;
    HRESULT created = CoCreateInstance(&CLSID_AccPropServices, NULL,
        CLSCTX_SERVER, &IID_IAccPropServices, (void **)&services);
    if (FAILED(created)) {
        if (*uninitialize) CoUninitialize();
        *uninitialize = FALSE;
        return NULL;
    }
    return services;
}

static void end_services(IAccPropServices *services, BOOL uninitialize) {
    IAccPropServices_Release(services);
    if (uninitialize) CoUninitialize();
}

static BOOL set_string(IAccPropServices *services, HWND control,
                       MSAAPROPID property, const wchar_t *value) {
    return SUCCEEDED(IAccPropServices_SetHwndPropStr(services, control,
        OBJID_CLIENT, CHILDID_SELF, property, value));
}

static BOOL set_variant(IAccPropServices *services, HWND control,
                        MSAAPROPID property, VARIANT value) {
    return SUCCEEDED(IAccPropServices_SetHwndProp(services, control,
        OBJID_CLIENT, CHILDID_SELF, property, value));
}

static BOOL set_bool(IAccPropServices *services, HWND control,
                     MSAAPROPID property, BOOL value) {
    VARIANT annotated;
    ZeroMemory(&annotated, sizeof(annotated));
    annotated.vt = VT_BOOL;
    annotated.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
    return set_variant(services, control, property, annotated);
}

static BOOL set_number(IAccPropServices *services, HWND control,
                       MSAAPROPID property, double value) {
    VARIANT annotated;
    ZeroMemory(&annotated, sizeof(annotated));
    annotated.vt = VT_R8;
    annotated.dblVal = value;
    return set_variant(services, control, property, annotated);
}

static BOOL clear_props(IAccPropServices *services, HWND control,
                        MSAAPROPID *properties, int count) {
    return SUCCEEDED(IAccPropServices_ClearHwndProps(services, control,
        OBJID_CLIENT, CHILDID_SELF, properties, count));
}

static BOOL edit_class(HWND control) {
    wchar_t name[32];
    GetClassNameW(control, name, 32);
    return lstrcmpiW(name, L"EDIT") == 0;
}

BOOL elisa_win32_privacy_is_sensitive(HWND control) {
    return control != NULL && GetPropW(control, SENSITIVE_PROPERTY) != NULL;
}

static LRESULT CALLBACK privacy_edit_proc(HWND control, UINT message,
    WPARAM w, LPARAM l, UINT_PTR subclass_id, DWORD_PTR reference) {
    (void)reference;
    if (elisa_win32_privacy_is_sensitive(control) &&
        (message == WM_COPY || message == WM_CUT)) return 0;
    if (message == WM_NCDESTROY) {
        RemovePropW(control, SENSITIVE_PROPERTY);
        RemoveWindowSubclass(control, privacy_edit_proc, subclass_id);
    }
    return DefSubclassProc(control, message, w, l);
}

static BOOL apply_sensitive_props(IAccPropServices *services, HWND control) {
    BOOL ok = set_string(services, control, Name_Property_GUID,
                         L"Sensitive content");
    ok = set_string(services, control, LegacyIAccessible_Name_Property_GUID,
                     L"Sensitive content") && ok;
    ok = set_string(services, control, PROPID_ACC_NAME,
                     L"Sensitive content") && ok;
    MSAAPROPID help[] = { HelpText_Property_GUID,
        PROPID_ACC_DESCRIPTION, PROPID_ACC_HELP };
    ok = clear_props(services, control, help, 3) && ok;

    if (edit_class(control)) {
        ok = set_string(services, control, Value_Value_Property_GUID, L"") && ok;
        ok = set_string(services, control,
            LegacyIAccessible_Value_Property_GUID, L"") && ok;
        ok = set_string(services, control, PROPID_ACC_VALUE, L"") && ok;
        ok = set_bool(services, control, IsPassword_Property_GUID, TRUE) && ok;
        ok = set_bool(services, control,
            IsTextPatternAvailable_Property_GUID, FALSE) && ok;
        return ok;
    }

    wchar_t cls[32];
    GetClassNameW(control, cls, 32);
    if (lstrcmpiW(cls, TRACKBAR_CLASSW) == 0 ||
        lstrcmpiW(cls, PROGRESS_CLASSW) == 0) {
        ok = set_number(services, control, RangeValue_Value_Property_GUID, 0) && ok;
        ok = set_number(services, control, RangeValue_Minimum_Property_GUID, 0) && ok;
        ok = set_number(services, control, RangeValue_Maximum_Property_GUID, 0) && ok;
        ok = set_number(services, control, RangeValue_LargeChange_Property_GUID, 0) && ok;
        ok = set_number(services, control, RangeValue_SmallChange_Property_GUID, 0) && ok;
        ok = set_string(services, control,
            LegacyIAccessible_Value_Property_GUID, L"") && ok;
        ok = set_string(services, control, PROPID_ACC_VALUE, L"") && ok;
    } else if (lstrcmpiW(cls, L"BUTTON") == 0) {
        LONG_PTR style = GetWindowLongPtrW(control, GWL_STYLE);
        const LONG_PTR type = style & BS_TYPEMASK;
        if (type == BS_CHECKBOX || type == BS_AUTOCHECKBOX ||
            type == BS_3STATE || type == BS_AUTO3STATE ||
            type == BS_RADIOBUTTON || type == BS_AUTORADIOBUTTON) {
            VARIANT off;
            ZeroMemory(&off, sizeof(off));
            off.vt = VT_I4;
            off.lVal = 0;
            ok = set_variant(services, control,
                Toggle_ToggleState_Property_GUID, off) && ok;
            DWORD state = 0;
            if ((style & WS_TABSTOP) != 0 || GetFocus() == control)
                state |= STATE_SYSTEM_FOCUSABLE;
            if (GetFocus() == control) state |= STATE_SYSTEM_FOCUSED;
            if (!IsWindowEnabled(control)) state |= STATE_SYSTEM_UNAVAILABLE;
            VARIANT legacy;
            ZeroMemory(&legacy, sizeof(legacy));
            legacy.vt = VT_I4;
            legacy.lVal = (LONG)state;
            ok = set_variant(services, control,
                LegacyIAccessible_State_Property_GUID, legacy) && ok;
            ok = set_variant(services, control, PROPID_ACC_STATE, legacy) && ok;
        }
    }
    return ok;
}

static BOOL clear_sensitive_props(IAccPropServices *services, HWND control) {
    MSAAPROPID base[] = { Name_Property_GUID,
        LegacyIAccessible_Name_Property_GUID, PROPID_ACC_NAME,
        HelpText_Property_GUID, PROPID_ACC_DESCRIPTION, PROPID_ACC_HELP };
    BOOL ok = clear_props(services, control, base,
                          (int)(sizeof(base) / sizeof(base[0])));
    if (edit_class(control)) {
        MSAAPROPID edit[] = { Value_Value_Property_GUID,
            LegacyIAccessible_Value_Property_GUID, PROPID_ACC_VALUE,
            IsPassword_Property_GUID, IsTextPatternAvailable_Property_GUID };
        ok = clear_props(services, control, edit,
                         (int)(sizeof(edit) / sizeof(edit[0]))) && ok;
    } else {
        wchar_t cls[32];
        GetClassNameW(control, cls, 32);
        if (lstrcmpiW(cls, TRACKBAR_CLASSW) == 0 ||
            lstrcmpiW(cls, PROGRESS_CLASSW) == 0) {
            MSAAPROPID range[] = { RangeValue_Value_Property_GUID,
                RangeValue_Minimum_Property_GUID, RangeValue_Maximum_Property_GUID,
                RangeValue_LargeChange_Property_GUID,
                RangeValue_SmallChange_Property_GUID,
                LegacyIAccessible_Value_Property_GUID, PROPID_ACC_VALUE };
            ok = clear_props(services, control, range,
                             (int)(sizeof(range) / sizeof(range[0]))) && ok;
        } else if (lstrcmpiW(cls, L"BUTTON") == 0) {
            MSAAPROPID toggle[] = { Toggle_ToggleState_Property_GUID,
                LegacyIAccessible_State_Property_GUID, PROPID_ACC_STATE };
            ok = clear_props(services, control, toggle,
                             (int)(sizeof(toggle) / sizeof(toggle[0]))) && ok;
        }
    }
    return ok;
}

BOOL elisa_win32_privacy_apply(HWND control, BOOL sensitive) {
    if (control == NULL) return FALSE;
    BOOL was_sensitive = elisa_win32_privacy_is_sensitive(control);
    if (sensitive != was_sensitive && sensitive) {
        if (!SetPropW(control, SENSITIVE_PROPERTY, (HANDLE)(ULONG_PTR)1))
            return FALSE;
        if (edit_class(control) && !SetWindowSubclass(control, privacy_edit_proc,
                PRIVACY_SUBCLASS_ID, 0)) {
            RemovePropW(control, SENSITIVE_PROPERTY);
            return FALSE;
        }
    } else if (!sensitive && was_sensitive) {
        RemovePropW(control, SENSITIVE_PROPERTY);
    } else if (!sensitive) {
        return TRUE;
    }

    BOOL uninitialize = FALSE;
    IAccPropServices *services = begin_services(&uninitialize);
    if (services == NULL) return FALSE;
    BOOL ok = sensitive ? apply_sensitive_props(services, control)
                        : clear_sensitive_props(services, control);
    end_services(services, uninitialize);
    return ok;
}

BOOL elisa_win32_privacy_set_help(HWND control, const wchar_t *help) {
    BOOL uninitialize = FALSE;
    IAccPropServices *services = begin_services(&uninitialize);
    if (services == NULL) return FALSE;
    BOOL ok;
    if (elisa_win32_privacy_is_sensitive(control) || help == NULL || help[0] == 0) {
        MSAAPROPID properties[] = { HelpText_Property_GUID,
            PROPID_ACC_DESCRIPTION, PROPID_ACC_HELP };
        ok = clear_props(services, control, properties, 3);
    } else {
        ok = set_string(services, control, HelpText_Property_GUID, help);
    }
    end_services(services, uninitialize);
    return ok;
}
