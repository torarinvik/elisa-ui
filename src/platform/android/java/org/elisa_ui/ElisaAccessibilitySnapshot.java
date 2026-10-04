package org.elisa_ui;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

/** Validated view of the bounded Elisa-to-Android semantic packet. */
final class ElisaAccessibilitySnapshot {
    static final int MAX_NODES = 256;
    static final int NONE = MAX_NODES;
    static final int HEADER_BYTES = 8;
    static final int RECORD_BYTES = 120;
    static final int MAX_BYTES = HEADER_BYTES + MAX_NODES * RECORD_BYTES + 3 * 1024;

    static final class Node {
        int id, role, action, parent, firstChild, nextSibling;
        int revision, selectionStart, selectionLength, collectionPosition;
        int collectionSize, collectionCount;
        float x, y, width, height, value, rangeMin, rangeMax;
        boolean enabled, focused, selected, hasRange, hasCollectionPosition;
        String label, help, text;
    }

    private final Node[] nodes;

    private ElisaAccessibilitySnapshot(Node[] nodes) {
        this.nodes = nodes;
    }

    static ElisaAccessibilitySnapshot parse(byte[] bytes) {
        if (bytes == null || bytes.length < HEADER_BYTES || bytes.length > MAX_BYTES) return null;
        ByteBuffer data = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        if (data.getInt(0) != 1) return null;
        int count = data.getInt(4);
        if (count < 0 || count > MAX_NODES) return null;
        int recordsEnd = HEADER_BYTES + count * RECORD_BYTES;
        if (recordsEnd > bytes.length) return null;
        Node[] nodes = new Node[count];
        boolean[] seen = new boolean[MAX_NODES];
        for (int index = 0; index < count; ++index) {
            int base = HEADER_BYTES + index * RECORD_BYTES;
            Node node = new Node();
            node.id = data.getInt(base);
            node.role = data.getInt(base + 4);
            node.x = data.getFloat(base + 8);
            node.y = data.getFloat(base + 12);
            node.width = data.getFloat(base + 16);
            node.height = data.getFloat(base + 20);
            node.action = data.getInt(base + 24);
            node.value = data.getFloat(base + 28);
            node.parent = data.getInt(base + 32);
            node.firstChild = data.getInt(base + 36);
            node.nextSibling = data.getInt(base + 40);
            node.enabled = data.getInt(base + 44) != 0;
            node.focused = data.getInt(base + 48) != 0;
            node.selected = data.getInt(base + 52) != 0;
            node.revision = data.getInt(base + 56);
            node.selectionStart = data.getInt(base + 60);
            node.selectionLength = data.getInt(base + 64);
            node.hasRange = data.getInt(base + 68) != 0;
            node.rangeMin = data.getFloat(base + 72);
            node.rangeMax = data.getFloat(base + 76);
            node.hasCollectionPosition = data.getInt(base + 80) != 0;
            node.collectionPosition = data.getInt(base + 84);
            node.collectionSize = data.getInt(base + 88);
            node.collectionCount = data.getInt(base + 92);
            node.label = text(bytes, recordsEnd, data.getInt(base + 96), data.getInt(base + 100));
            node.help = text(bytes, recordsEnd, data.getInt(base + 104), data.getInt(base + 108));
            node.text = text(bytes, recordsEnd, data.getInt(base + 112), data.getInt(base + 116));
            if (node.id < 0 || node.id >= MAX_NODES || seen[node.id]
                    || node.role < 0 || node.role > 13
                    || node.action < 0 || node.action > NONE
                    || !relationship(node.parent) || !relationship(node.firstChild)
                    || !relationship(node.nextSibling) || node.parent == node.id
                    || !finite(node.x) || !finite(node.y) || !finite(node.width) || !finite(node.height)
                    || !finite(node.value) || !finite(node.rangeMin) || !finite(node.rangeMax)
                    || node.width < 0 || node.height < 0 || node.selectionStart < 0 || node.selectionLength < 0
                    || node.label == null || node.label.isEmpty() || node.help == null || node.text == null
                    || (node.hasRange && node.rangeMax < node.rangeMin)
                    || (node.role == 7 && (!node.text.isEmpty() || node.selectionStart != 0 || node.selectionLength != 0))
                    || (node.role != 7 && (long)node.selectionStart + node.selectionLength > node.text.length())) return null;
            seen[node.id] = true;
            nodes[index] = node;
        }
        for (Node node : nodes) {
            if (node.parent < NONE && !seen[node.parent]) return null;
            int current = node.id;
            boolean reachesRoot = false;
            for (int depth = 0; depth <= count; ++depth) {
                Node ancestor = find(nodes, current);
                if (ancestor == null) return null;
                if (ancestor.parent == NONE) {
                    reachesRoot = true;
                    break;
                }
                current = ancestor.parent;
            }
            if (!reachesRoot) return null;
        }
        return new ElisaAccessibilitySnapshot(nodes);
    }

    int count() { return nodes.length; }
    Node[] nodes() { return nodes.clone(); }
    Node at(int index) { return index < 0 || index >= nodes.length ? null : nodes[index]; }
    Node find(int id) { return find(nodes, id); }

    private static Node find(Node[] nodes, int id) {
        for (Node node : nodes) if (node.id == id) return node;
        return null;
    }

    private static String text(byte[] bytes, int recordsEnd, int offset, int length) {
        if (offset < recordsEnd || length < 0 || offset > bytes.length || length > bytes.length - offset) return null;
        try {
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes, offset, length)).toString();
        } catch (CharacterCodingException invalidUtf8) {
            return null;
        }
    }

    private static boolean relationship(int id) { return id >= 0 && id <= NONE; }
    private static boolean finite(float value) { return !Float.isNaN(value) && !Float.isInfinite(value); }
}
