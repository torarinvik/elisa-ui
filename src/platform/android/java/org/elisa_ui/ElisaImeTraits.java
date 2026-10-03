package org.elisa_ui;

import android.text.InputType;
import android.view.inputmethod.EditorInfo;

// Applies the purpose resolved by Elisa, never application text.
final class ElisaImeTraits {
    static void apply(EditorInfo out, int purpose) {
        out.inputType = inputType(purpose);
        out.imeOptions = imeOptions(purpose);
    }
    static int inputType(int purpose) {
        int type = InputType.TYPE_CLASS_TEXT;
        switch (purpose) {
            case 1: type |= InputType.TYPE_TEXT_VARIATION_PASSWORD | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS; break;
            case 2: type |= InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS; break;
            case 3: type |= InputType.TYPE_TEXT_VARIATION_URI | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS; break;
            case 4: type = InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL | InputType.TYPE_NUMBER_FLAG_SIGNED; break;
            case 5: type |= InputType.TYPE_TEXT_FLAG_AUTO_CORRECT; break;
            case 0: type |= InputType.TYPE_TEXT_FLAG_AUTO_CORRECT; break;
            default: type |= InputType.TYPE_TEXT_VARIATION_PASSWORD | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
        }
        return type;
    }
    static int imeOptions(int purpose) {
        int options = EditorInfo.IME_FLAG_NO_EXTRACT_UI |
            (purpose == 5 ? EditorInfo.IME_ACTION_SEARCH : EditorInfo.IME_ACTION_DONE);
        if (purpose == 1 || purpose < 0 || purpose > 5)
            options |= EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING;
        return options;
    }
}
