package org.elisa_ui;

// Connection-local lifetime, separate from the retained editor's owner token.
final class ElisaImeSession {
    private final long owner;
    private boolean closed;
    private Integer monitor;
    private int batchDepth;
    ElisaImeSession(long owner) { this.owner = owner; }
    boolean live() { return !closed && owner != 0; }
    boolean close() {
        if (closed) return false;
        closed = true;
        monitor = null;
        batchDepth = 0;
        return true;
    }
    void clearMonitor() { monitor = null; }
    boolean beginBatch() {
        if (!live() || batchDepth == Integer.MAX_VALUE) return false;
        ++batchDepth;
        return true;
    }
    int endBatch() {
        if (!live() || batchDepth == 0) return -1;
        return --batchDepth;
    }
    boolean inBatch() { return live() && batchDepth > 0; }
    boolean outermostBatch() { return live() && batchDepth == 1; }
    void monitor(int token) { if (live()) monitor = token; }
    Integer monitorFor(long currentOwner) {
        if (!live() || owner != currentOwner) { monitor = null; return null; }
        return monitor;
    }
}
