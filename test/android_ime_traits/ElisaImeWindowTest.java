package org.elisa_ui;

import java.util.Arrays;

public final class ElisaImeWindowTest {
    private static void expect(String text, int anchor, int caret, int before, int after, int... expected) {
        if (!Arrays.equals(ElisaImeWindow.bounds(text, anchor, caret, before, after), expected))
            throw new AssertionError("incorrect surrounding window");
    }
    public static void main(String[] args) {
        expect("AB😀Z", 4, 2, 1, 1, 1, 5, 3, 1);
        expect("AB😀Z", 4, 4, 1, 1, 4, 5, 0, 0);
        expect("AB😀Z", 2, 2, 1, 1, 1, 2, 1, 1);
        expect("AB😀Z", 4, 2, Integer.MAX_VALUE, Integer.MAX_VALUE, 0, 5, 4, 2);
        expect("", 0, 0, 0, 0, 0, 0, 0, 0);
        expect("abc", Integer.MAX_VALUE, -1, 0, 0, 0, 3, 3, 0);
        if (ElisaImeWindow.bounds("abc", 0, 0, -1, 1) != null)
            throw new AssertionError("negative extent accepted");
        System.out.println("android IME windows: all checks passed");
    }
}
