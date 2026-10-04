package org.elisa_ui;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Host-JVM contract test for the bounded Elisa/Android semantic wire format. */
public final class ElisaAccessibilitySnapshotTest {
    private static int assertions;

    private static void check(String name, boolean condition) {
        ++assertions;
        if (!condition) throw new AssertionError(name);
    }

    private static byte[] packet(int[] ids, int[] roles, int[] parents,
                                 String[] labels, String[] helps, String[] values) {
        int textBytes = 0;
        for (int index = 0; index < ids.length; ++index) {
            textBytes += labels[index].getBytes(StandardCharsets.UTF_8).length;
            textBytes += helps[index].getBytes(StandardCharsets.UTF_8).length;
            textBytes += values[index].getBytes(StandardCharsets.UTF_8).length;
        }
        int recordsEnd = ElisaAccessibilitySnapshot.HEADER_BYTES
            + ids.length * ElisaAccessibilitySnapshot.RECORD_BYTES;
        ByteBuffer data = ByteBuffer.allocate(recordsEnd + textBytes).order(ByteOrder.LITTLE_ENDIAN);
        data.putInt(0, 1);
        data.putInt(4, ids.length);
        int cursor = recordsEnd;
        for (int index = 0; index < ids.length; ++index) {
            int base = ElisaAccessibilitySnapshot.HEADER_BYTES
                + index * ElisaAccessibilitySnapshot.RECORD_BYTES;
            data.putInt(base, ids[index]);
            data.putInt(base + 4, roles[index]);
            data.putFloat(base + 8, 1.0f);
            data.putFloat(base + 12, 2.0f);
            data.putFloat(base + 16, 30.0f);
            data.putFloat(base + 20, 10.0f);
            data.putInt(base + 24, ids[index]);
            data.putFloat(base + 28, 0.5f);
            data.putInt(base + 32, parents[index]);
            data.putInt(base + 36, ElisaAccessibilitySnapshot.NONE);
            data.putInt(base + 40, ElisaAccessibilitySnapshot.NONE);
            data.putInt(base + 44, 1);
            data.putInt(base + 68, 1);
            data.putFloat(base + 72, 0.0f);
            data.putFloat(base + 76, 1.0f);
            cursor = putText(data, base + 96, base + 100, cursor, labels[index]);
            cursor = putText(data, base + 104, base + 108, cursor, helps[index]);
            cursor = putText(data, base + 112, base + 116, cursor, values[index]);
        }
        return Arrays.copyOf(data.array(), cursor);
    }

    private static int putText(ByteBuffer data, int offsetField, int lengthField,
                               int cursor, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        data.putInt(offsetField, cursor);
        data.putInt(lengthField, bytes.length);
        data.position(cursor);
        data.put(bytes);
        return cursor + bytes.length;
    }

    public static void main(String[] args) {
        byte[] valid = packet(new int[]{4}, new int[]{1}, new int[]{256},
            new String[]{"Lagre ✓"}, new String[]{"Save changes"}, new String[]{""});
        ElisaAccessibilitySnapshot snapshot = ElisaAccessibilitySnapshot.parse(valid);
        check("one retained node parses", snapshot != null && snapshot.count() == 1);
        ElisaAccessibilitySnapshot.Node node = snapshot == null ? null : snapshot.find(4);
        check("stable ID, role, label and help survive the wire", node != null
            && node.role == 1 && node.label.equals("Lagre ✓") && node.help.equals("Save changes"));
        check("bounds, action and range metadata survive the wire", node != null
            && node.x == 1.0f && node.y == 2.0f && node.action == 4
            && node.hasRange && node.rangeMax == 1.0f);
        check("empty tree has a valid header", ElisaAccessibilitySnapshot.parse(new byte[]{1,0,0,0,0,0,0,0}).count() == 0);
        check("truncated records are rejected", ElisaAccessibilitySnapshot.parse(Arrays.copyOf(valid, 20)) == null);
        check("duplicate stable IDs are rejected", ElisaAccessibilitySnapshot.parse(packet(
            new int[]{1,1}, new int[]{1,1}, new int[]{256,256},
            new String[]{"A","B"}, new String[]{"",""}, new String[]{"",""})) == null);
        check("cyclic parent links are rejected", ElisaAccessibilitySnapshot.parse(packet(
            new int[]{1,2}, new int[]{10,10}, new int[]{2,1},
            new String[]{"A","B"}, new String[]{"",""}, new String[]{"",""})) == null);
        check("password values are rejected at the host boundary", ElisaAccessibilitySnapshot.parse(packet(
            new int[]{3}, new int[]{7}, new int[]{256},
            new String[]{"Password"}, new String[]{""}, new String[]{"secret"})) == null);
        byte[] passwordSelection = packet(new int[]{3}, new int[]{7}, new int[]{256},
            new String[]{"Password"}, new String[]{""}, new String[]{""});
        ByteBuffer.wrap(passwordSelection).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(ElisaAccessibilitySnapshot.HEADER_BYTES + 60, 1);
        check("password caret metadata is rejected at the host boundary", ElisaAccessibilitySnapshot.parse(passwordSelection) == null);

        byte[] invalidOffset = valid.clone();
        ByteBuffer.wrap(invalidOffset).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(ElisaAccessibilitySnapshot.HEADER_BYTES + 96, 8);
        check("text cannot alias the fixed record area", ElisaAccessibilitySnapshot.parse(invalidOffset) == null);
        byte[] invalidUtf8 = valid.clone();
        int labelOffset = ByteBuffer.wrap(invalidUtf8).order(ByteOrder.LITTLE_ENDIAN)
            .getInt(ElisaAccessibilitySnapshot.HEADER_BYTES + 96);
        invalidUtf8[labelOffset] = (byte)0xff;
        check("malformed UTF-8 is rejected", ElisaAccessibilitySnapshot.parse(invalidUtf8) == null);
        System.out.println("android accessibility snapshot: " + assertions + " assertions passed");
    }
}
