package org.elisa_ui;

public final class ElisaImeSessionTest {
    public static void main(String[] args) {
        ElisaImeSession session = new ElisaImeSession(7);
        if (!session.live()) throw new AssertionError("live connection rejected");
        if (session.endBatch() != -1 || !session.beginBatch() || !session.beginBatch())
            throw new AssertionError("incorrect batch entry");
        if (!session.inBatch() || session.endBatch() != 1 || !session.inBatch() || session.endBatch() != 0 || session.inBatch())
            throw new AssertionError("incorrect nested batch exit");
        if (!session.beginBatch() || !session.outermostBatch()) throw new AssertionError("outer marker not identified");
        session.beginBatch();
        if (session.outermostBatch()) throw new AssertionError("nested marker identified as outer");
        session.endBatch(); session.endBatch();
        session.monitor(42);
        if (session.monitorFor(7) != 42) throw new AssertionError("monitor lost");
        if (session.monitorFor(8) != null || session.monitorFor(7) != null)
            throw new AssertionError("retired monitor revived");
        session.monitor(-1);
        session.beginBatch();
        if (!session.close() || session.close() || session.live())
            throw new AssertionError("closure is not terminal/idempotent");
        session.monitor(42);
        if (session.inBatch() || session.beginBatch() || session.endBatch() != -1)
            throw new AssertionError("closed batch revived");
        if (session.monitorFor(7) != null) throw new AssertionError("closed monitor revived");
        if (new ElisaImeSession(0).live()) throw new AssertionError("zero owner accepted");
        System.out.println("android IME sessions: all checks passed");
    }
}
