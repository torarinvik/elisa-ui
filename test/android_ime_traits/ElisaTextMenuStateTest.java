package org.elisa_ui;

public final class ElisaTextMenuStateTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    private static long[] state(long owner, long purpose, long start, long end, long serial) {
        return new long[]{owner, purpose, start, end, -1, -1, serial};
    }
    public static void main(String[] args) {
        ElisaTextMenuState menu = new ElisaTextMenuState();
        check(!menu.isActive());
        check(menu.update(state(9, 0, 0, 7, 99)) == ElisaTextMenuState.HIDE);
        menu.setActive(true);
        check(menu.update(null) == ElisaTextMenuState.HIDE);
        check(menu.update(new long[2]) == ElisaTextMenuState.HIDE);
        check(menu.update(state(1, 0, 0, 0, 0)) == ElisaTextMenuState.HIDE);
        long[] emptyRequest = state(1, 0, 0, 0, 1);
        check(menu.update(emptyRequest) == ElisaTextMenuState.SHOW);
        check(menu.update(emptyRequest) == ElisaTextMenuState.KEEP);
        menu.hide();
        check(menu.update(emptyRequest) == ElisaTextMenuState.HIDE);
        check(menu.update(state(1, 0, 0, 0, 2)) == ElisaTextMenuState.SHOW);
        check(menu.update(state(1, 0, 1, 1, 2)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(1, 0, 7, 0, 2)) == ElisaTextMenuState.SHOW);
        // User dismissal leaves the unchanged selection remembered, so the
        // next ordinary publication cannot reopen it.
        check(menu.update(state(1, 0, 7, 0, 2)) == ElisaTextMenuState.KEEP);
        check(menu.update(state(2, 0, 0, 0, 0)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(2, 0, 0, 0, 3)) == ElisaTextMenuState.SHOW);
        check(menu.update(state(0, 0, 0, 0, 0)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(2, 0, 0, 0, 3)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(2, 0, -1, 0, 4)) == ElisaTextMenuState.HIDE);
        check(ElisaTextMenuState.canExport(state(2, 0, 7, 0, 0)));
        check(!ElisaTextMenuState.canExport(state(2, 1, 7, 0, 0)));
        check(!ElisaTextMenuState.canExport(state(2, 99, 7, 0, 0)));
        check(!ElisaTextMenuState.canExport(emptyRequest));
        check(!ElisaTextMenuState.canExport(new long[2]));
        check(menu.update(state(2, 0, 0, 0, 5)) == ElisaTextMenuState.SHOW);
        menu.setActive(false);
        check(!menu.isActive());
        check(menu.update(state(2, 0, 0, 0, 5)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(2, 0, 0, 7, 6)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(2, 0, 0, 0, 8)) == ElisaTextMenuState.HIDE);
        menu.setActive(true);
        check(menu.update(state(2, 0, 0, 0, 8)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(3, 0, 0, 0, 0)) == ElisaTextMenuState.HIDE);
        check(menu.update(state(3, 0, 0, 0, 7)) == ElisaTextMenuState.SHOW);
        System.out.println("android text menu state: all checks passed");
    }
}
