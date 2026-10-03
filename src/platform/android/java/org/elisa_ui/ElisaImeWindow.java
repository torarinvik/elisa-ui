package org.elisa_ui;

// Pure UTF-16 window arithmetic shared by the real query and host tests.
final class ElisaImeWindow {
    static int[] bounds(CharSequence text, int anchor, int caret, int before, int after) {
        if (text == null || before < 0 || after < 0) return null;
        int length = text.length();
        anchor = Math.max(0, Math.min(anchor, length));
        caret = Math.max(0, Math.min(caret, length));
        int first = Math.min(anchor, caret), last = Math.max(anchor, caret);
        int start = first - Math.min(before, first);
        int end = last + Math.min(after, length - last);
        if (start < first && Character.isLowSurrogate(text.charAt(start))) ++start;
        if (end > last && Character.isHighSurrogate(text.charAt(end - 1))) --end;
        return new int[] {start, end, anchor - start, caret - start};
    }
}
