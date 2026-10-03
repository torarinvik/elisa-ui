package org.elisa_ui;

/** Presentation decisions only; native retained policy still authorizes edits. */
final class ElisaTextMenuState {
    static final int KEEP = 0, HIDE = 1, SHOW = 2;
    private long owner, start = -1, end = -1, purpose = -1;
    private long requestOwner, requestSerial;
    private boolean active;

    boolean isActive() { return active; }
    void setActive(boolean enabled) { active = enabled; if (!active) hide(); }

    void hide() { owner = 0; start = end = purpose = -1; }

    int update(long[] state) {
        if (!active) {
            // Retire explicit requests observed while suspended so resume
            // cannot replay a background notification into presentation.
            if (state != null && state.length > 6 && state[0] != 0 && state[6] != 0) {
                requestOwner = state[0]; requestSerial = state[6];
            }
            hide();
            return HIDE;
        }
        if (state == null || state.length < 6 || state[0] == 0 || state[1] < 0 ||
                state[2] < 0 || state[3] < 0) {
            hide();
            return HIDE;
        }
        boolean explicit = state.length > 6 && state[6] != 0 &&
                (requestOwner != state[0] || requestSerial != state[6]);
        if (explicit) { requestOwner = state[0]; requestSerial = state[6]; }
        if (!explicit && owner == state[0] && purpose == state[1] &&
                start == state[2] && end == state[3]) return KEEP;
        owner = state[0]; purpose = state[1]; start = state[2]; end = state[3];
        return start != end || explicit ? SHOW : HIDE;
    }

    static boolean canExport(long[] state) {
        return state != null && state.length >= 6 && state[0] != 0 &&
            state[1] >= 0 && state[1] <= 5 && state[1] != 1 &&
            state[2] >= 0 && state[3] >= 0 && state[2] != state[3];
    }
}
