package org.elisa_ui;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;

public final class ElisaImeTraitsTest {
    private static void check(String name, boolean ok) {
        if (!ok) throw new AssertionError(name);
    }
    public static void main(String[] args) {
        check("email", (ElisaImeTraits.inputType(2) & InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        check("URL", (ElisaImeTraits.inputType(3) & InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_URI);
        check("decimal number", (ElisaImeTraits.inputType(4) & InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_NUMBER && (ElisaImeTraits.inputType(4) & InputType.TYPE_NUMBER_FLAG_DECIMAL) != 0);
        check("search action", (ElisaImeTraits.imeOptions(5) & EditorInfo.IME_MASK_ACTION) == EditorInfo.IME_ACTION_SEARCH);
        for (int purpose : new int[]{1, -1, 99}) {
            int type = ElisaImeTraits.inputType(purpose);
            check("password variation", (type & InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_PASSWORD);
            check("no suggestions", (type & InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) != 0);
            check("no correction", (type & InputType.TYPE_TEXT_FLAG_AUTO_CORRECT) == 0);
            check("no learning", (ElisaImeTraits.imeOptions(purpose) & EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) != 0);
        }
        for (int purpose = 0; purpose <= 5; ++purpose)
            check("no extract copy", (ElisaImeTraits.imeOptions(purpose) & EditorInfo.IME_FLAG_NO_EXTRACT_UI) != 0);
        System.out.println("android IME traits: all checks passed");
    }
}
