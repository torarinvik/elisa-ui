package org.elisa_ui;

import java.util.Arrays;

public final class AndroidSelectionStoreTest {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        byte[] source = new byte[] {'b', 'y', 't', 'e', 's'};
        long id = ElisaSelectionStore.remember(source);
        check(id > 0, "nonempty content gets a logical ID");
        byte[] chunk = new byte[3];
        check(ElisaSelectionStore.read(id, 1, chunk) == 3, "bounded offset read count");
        check(Arrays.equals(chunk, new byte[] {'y', 't', 'e'}), "chunk contains source bytes");
        check(ElisaSelectionStore.read(id, 5, chunk) == 0, "read at end is EOF");
        check(ElisaSelectionStore.read(id, 6, chunk) == -1, "offset beyond end is rejected");
        check(ElisaSelectionStore.release(id) == 1, "release succeeds once");
        check(ElisaSelectionStore.read(id, 0, chunk) == -1, "released bytes are inaccessible");
        check(ElisaSelectionStore.release(id) == 0, "duplicate release is rejected");

        long empty = ElisaSelectionStore.remember(new byte[0]);
        check(empty > 0 && ElisaSelectionStore.read(empty, 0, chunk) == 0,
                "zero-byte document remains a valid selection");
        check(ElisaSelectionStore.release(empty) == 1, "empty selection releases");
        check(ElisaSelectionStore.remember(
                new byte[ElisaSelectionStore.MAX_BYTES_PER_SELECTION + 1]) == 0,
                "oversized selection is rejected");

        byte[] max = new byte[ElisaSelectionStore.MAX_BYTES_PER_SELECTION];
        long first = ElisaSelectionStore.remember(max);
        long second = ElisaSelectionStore.remember(max);
        check(first > 0 && second > 0, "per-selection bounds allow the total byte ceiling");
        check(ElisaSelectionStore.remember(new byte[] {1}) == 0,
                "aggregate byte ceiling is enforced");
        check(ElisaSelectionStore.release(first) == 1 && ElisaSelectionStore.release(second) == 1,
                "aggregate capacity returns on release");

        long[] ids = new long[ElisaSelectionStore.MAX_SELECTIONS];
        for (int i = 0; i < ids.length; ++i) ids[i] = ElisaSelectionStore.remember(new byte[0]);
        check(ElisaSelectionStore.remember(new byte[0]) == 0,
                "selection-count ceiling is enforced");
        for (long selectionId : ids) check(ElisaSelectionStore.release(selectionId) == 1,
                "all bounded slots can be released");
        System.out.println("android selection store: all checks passed");
    }
}
