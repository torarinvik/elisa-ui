package org.elisa_ui;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/** Bounded host-owned bytes behind opaque mobile service selection IDs. */
public final class ElisaSelectionStore {
    public static final int MAX_BYTES_PER_SELECTION = 16 * 1024 * 1024;
    public static final int MAX_BYTES_TOTAL = 32 * 1024 * 1024;
    public static final int MAX_SELECTIONS = 16;

    private static final Object LOCK = new Object();
    private static final Map<Long, byte[]> SELECTIONS = new HashMap<Long, byte[]>();
    private static final AtomicLong NEXT_ID = new AtomicLong(1);
    private static long bytesTotal;

    private ElisaSelectionStore() {}

    public static long remember(byte[] bytes) {
        if (bytes == null || bytes.length > MAX_BYTES_PER_SELECTION) return 0;
        synchronized (LOCK) {
            if (SELECTIONS.size() >= MAX_SELECTIONS ||
                    bytesTotal + bytes.length > MAX_BYTES_TOTAL) return 0;
            long id = NEXT_ID.getAndIncrement();
            if (id <= 0) return 0;
            SELECTIONS.put(id, bytes);
            bytesTotal += bytes.length;
            return id;
        }
    }

    /** Returns copied bytes, zero at EOF, or -1 for an invalid/released selection. */
    public static int read(long id, long offset, byte[] target) {
        if (id <= 0 || offset < 0 || target == null) return -1;
        synchronized (LOCK) {
            byte[] bytes = SELECTIONS.get(id);
            if (bytes == null || offset > bytes.length) return -1;
            int start = (int) offset;
            int count = Math.min(target.length, bytes.length - start);
            if (count > 0) System.arraycopy(bytes, start, target, 0, count);
            return count;
        }
    }

    public static int release(long id) {
        if (id <= 0) return 0;
        synchronized (LOCK) {
            byte[] bytes = SELECTIONS.remove(id);
            if (bytes == null) return 0;
            bytesTotal -= bytes.length;
            return 1;
        }
    }
}
