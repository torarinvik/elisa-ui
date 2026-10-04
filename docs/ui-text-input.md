# Text-input policy

`UiTextInput` resolves a field's purpose into backend-neutral traits. Plain,
email, URL, number, search, and password fields select keyboard hints and
multiline behavior in Elisa; native/hosted adapters only apply those traits to
their text bridge.

Password traits are hardened regardless of caller options: secure entry is
enabled, multiline/autocorrect/suggestions are disabled, and clipboard plus
semantic value readback are denied. Secure text remains available through the
control's app-facing value API, but it is never exported as selected text or a
semantic value and never enters text undo/redo history. Enabling secure mode on
an existing field scrubs the shared undo/redo ring, including edits to other
fields; subsequent edits to the secure field remain undo-ineligible. Secure
values are also rejected by the typed application-state persistence adapter.
Tree reset scrubs the retained text, secure storage, clipboard staging, and
history buffers. Number fields accept digits and common sign or decimal
characters while leaving locale-specific formatting to the host; other
purposes continue to accept composed Unicode input and IME commits.

UIKit canvas keyboard privacy follows the focused retained field's secure
flag: `isSecureTextEntry` is queried through the live-view boundary; correction,
spell checking, smart quotes and smart dashes are disabled for secure input.
`uikit_flat_sync_keyboard()` reloads native input views when the secure trait
changes while the keyboard is active. Call it after programmatic focus/privacy
changes; native touch and text-action focus paths already synchronize it.
The UIKit host fixture tests secure/nonsecure/no-focus trait queries and the
active-keyboard bridge: secure and normal transitions each request one native
reload, unchanged traits request none, and blur retires the keyboard without
an unnecessary reload. This uses a nonzero native-view stand-in, not headless
keyboard state, so the native begin/end/reload boundary is exercised.
The simulator app builds on the existing stale compiler. Physical password-keyboard
inspection and application of the other purpose hints on canvas bridges remain
open for Android canvas and physical-device acceptance; the portable trait
policy alone does not prove native purpose coverage.

Retained fields now expose `UiHandles::set_text_purpose(handle, purpose)`.
Invalid handles and nontext controls are rejected. Purpose normalization uses
the common policy; password purpose enables secure storage and scrubs history.
Changing purpose does not silently disable an explicit secure flag. Explicitly
disabling secure entry on a password-purpose field resets it to plain text.
`retained_text_purpose_test` verifies hostile-purpose normalization, secure
storage/readback gating, explicit privacy release and stale-handle rejection
when the same field slot is reused by a replacement tree.
It establishes ordinary undo history before the purpose change, verifies
password normalization clears undo/redo, proves secure edits remain undo-
ineligible, and confirms releasing privacy cannot resurrect that old history.
UIKit canvas applies email/URL/decimal keyboard hints and the search return
key, disables correction for non-prose purposes, and refreshes the active
keyboard when purpose changes. The host fixture verifies email/number queries,
password privacy hardening and each native refresh. Device keyboard inspection
remains separate unfinished acceptance work.

Android canvas now publishes the resolved purpose from the native owner thread
into a mutex-protected JNI owner/purpose snapshot. `EditorInfo` consumes that snapshot rather than
querying retained field traits across threads. Email/URL/numeric/search hints
are applied; password and unknown-purpose input suppress suggestions,
autocorrection and personalized learning. Every purpose disables extract UI.
An active purpose transition restarts the input connection, without repeating
show requests on unchanged frames. `check_android_ime_traits.sh` tests the
production mapping against SDK constants on the host, including hostile
purpose values. Device keyboard and IME restart inspection remain unverified.
Readiness, connection identity and purpose are read from one coherent snapshot:
nonediting has owner zero and purpose -1, and Java's text-editor query no longer reads retained state on its
own thread. Focus/surface/background loss and both teardown paths retire this
snapshot and hide once. The production native synchronizer host test verifies
publication before show, no repeated requests over unchanged frames, active
purpose restart, blur, idempotent interruption and restored editing. It runs
with `check_android_contacts.sh` in the ordinary suite.

## Focus reveal and keyboard occlusion
UIKit now returns a single-line `UITextSelectionRect` for a nonempty retained
selection instead of an empty rectangle list. Invalid geometry locations fail
closed to zero; RTL endpoint ordering produces a positive bounded rectangle.
`uikit_text_input_test` covers caret/range geometry, invalid offsets, RTL extent,
UTF-16 selection/composition and secure readback. The simulator app builds;
the same fixture verifies geometry is zeroed after focus retirement and cannot
be queried through a foreign view identity. The canvas installs an editable
`UITextInteraction`, gated by retained hit testing to the live focused field.
Native editing gestures take precedence over direct-finger canvas scrolling;
indirect scrolling remains independent. Host checks reject background starts,
invalid coordinates, foreign views and retired focus. Native selection handles
use `UITextSelectionDisplayInteraction` and a gated canvas pan; Elisa owns
endpoint anchoring, grapheme snapping, cancellation restoration and document
revision checks. Handle contacts suppress compatibility pointer presses.
`UITextInteraction` alone did not expose an edit menu, so
the canvas installs a separate `UIEditMenuInteraction` with a non-delaying
long-press recognizer. Menu actions use Elisa's existing selector validation
and editing implementation. Select All remains open so the refreshed menu can
offer Copy/Cut; keyboard edits, blur and keyboard-trait changes dismiss it.
The menu captures its original retained tree/field identity and revalidates
ownership and action eligibility before dispatch. Host checks reject foreign
views, retired focus, recycled fields and disabled documents.

The simulator verifies long-press, Select All and replacement. This exposed a
native accessibility feedback bug: frame publication called the assistive-edit
setter and collapsed selection/cancelled composition even for identical text.
Semantic publication now uses a separate native setter that updates only the
accessibility object. Genuine VoiceOver value edits still enter the retained
editor. The simulator now verifies native Copy/Cut/Paste through the refreshed
menu as well as selection replacement. A third simulator test verifies secure
input reaches the retained editor through a boolean receipt status, exposes no
plaintext semantic value, and offers neither Copy nor Cut after Select All.
UIKit password semantics intentionally publish no spoken value; this test
does not weaken that contract to expose masked content or length.
The fourth simulator test drags the trailing handle and verifies typing replaces
only the selected prefix. A fifth test repeats the drag on a Hebrew document in
an RTL field and preserves its Hebrew suffix. Two further tests move the leading
handle in LTR and Hebrew RTL, preserving the prefix when replacing the suffix.
All nine XCUITests pass together, including Unicode prefix replacement and
background/resume selection preservation.
Host tests additionally
cover leading handles, cancellation, combining marks, text-revision changes and
focus/tree retirement. A mobile input interruption stamp also rejects an old
drag after focus loss/regain, background/foreground or surface recreation when
no callback was delivered during the inactive interval; host regressions cover
all three round trips. Native cancellation/interruption workflows, physical-device acceptance and
non-Latin native IME workflows remain open. `ELISA_UI_UITEST_ONLY` selects one
test for diagnosis; a selected-test pass is not full-gate acceptance.

UIKit base-writing-direction and selection-rectangle direction now report
Elisa's locale-resolved LTR/RTL field direction instead of `Natural`, matching
the retained geometry policy. Host tests verify Hebrew-locale direction and
reset to English; the simulator product builds with this bridge. RTL trailing
handle dragging now passes the native gate, as does leading-handle dragging in
both directions. Mixed-bidi visual navigation and native gesture cancellation/
interruption acceptance remain open.
Physical horizontal position, range-edge and extension callbacks now use the
same locale-resolved mirrored run. Unsupported vertical directions return no
position/range for this single-line adapter. Host tests cover LTR/RTL steps,
negative steps, invalid flags, retired focus and oversized signed offsets;
storage stepping also avoids negating the minimum signed integer. These are
single-run geometry checks, not mixed-bidi visual-run acceptance.
The four-test native regression gate passes with the direction bridge (98.552
seconds); the later extreme-offset hardening passes the host matrix and builds
for the simulator. Both validations explicitly permit the existing stale
compiler product.
The expanded five-test gate passes on the latest simulator product in 110.318
seconds, including Hebrew RTL trailing-handle replacement and the prior four
regressions. The RTL smoke document is opt-in via `ELISA_UI_UITEST_RTL`; ordinary
smoke launches retain the original empty LTR field.
The subsequent seven-test gate passes in 152.599 seconds, adding native leading
handle replacement in both directions. This still uses the explicit stale
compiler opt-in and does not establish physical-device or mixed-bidi parity.

UIKit character-range extension and character-at-point now use retained
extended-grapheme boundaries rather than one UTF-16 unit. Ordinary native
position offsets remain UTF-16. Host regressions verify combining clusters,
ZWJ-family emoji, interior surrogate positions, bounded document ends and RTL
whole-character extension; the focused matrix passes and the simulator product
builds. The seven-test native result above predates this character-range change;
native Unicode gesture acceptance is still open.

Current Unicode follow-up: an opt-in combining-mark/ZWJ-family smoke document
passes a focused native trailing-handle test, replacing the complete combining
cluster while preserving the exact family emoji and suffix. The expanded
eight-test run is not accepted: Latin leading-handle replacement failed on both
attempts, leaving only `Z`; RTL and Unicode cases passed. A focused Latin-leading
recheck also failed after restoring no-extension behavior at document edges.
The host matrix remains green, but this native regression supersedes the older
seven-test acceptance for the current source. Gesture recognition needs further
diagnosis; no mixed-bidi, IME or physical-device completion is claimed.

Leading-handle trace follow-up: the original Latin test hit the native handle
but generated no pan callback with its approximately 19-point drag. Moving the
test target farther into the same text run preserves the original assertion
and passes both focused and combined LTR/RTL leading-handle checks. Temporary
traces were removed. The subsequent full eight-test run still fails its Unicode
case despite a focused Unicode pass; all seven prior cases pass. Exact retained
value diagnostics were added for that remaining failure. Assertion failures
now stop the gate without a retry; only non-assertion launch failures can retry.

Prior acceptance: all eight native tests pass in 166.042 seconds. Before
typing, the Unicode test waits for a boolean receipt confirming retained
UTF-16 selection 0..2, then asserts exact replacement `Z👩‍👩‍👧‍👦bcdefghij`.
The earlier failures remain recorded above; this passing run does not establish
their root cause or broader Unicode/IME parity. The gate includes the grapheme
and document-edge changes and explicitly permits the stale compiler product.

`bash scripts/check_mobile_input.sh` runs the focused wire/queue/contact/
gesture/mobile/focus/purpose/text/handle/layout/lifecycle matrix, plus UIKit
host fixtures on macOS and Android transport/trait gates. It enforces the
normal toolchain check; stale/dirty compiler use requires explicit opt-ins.
All 18 selected Elisa tests and Android host gates pass together on the
existing stale compiler. This is not full-suite, renderer-performance or
physical-device acceptance.

Android IME ingress is isolated in `ui_android_ime.elisa` with unchanged JNI
exports. Composition/commit calls now reject inactive/background/lost/stopped
surfaces, missing focused editors, negative byte lengths and missing nonempty
buffers before staging. The host regression drives actual provisional and
Chinese committed text through this path, checks rejected late callbacks leave
text/composition intact and verifies staging is scrubbed. The production
Showcase entry compiles to a host object with both exports present. This is not
an APK/device pass, a stale-connection ownership guarantee or a JNI-thread
serialization guarantee; those remain open along with Android native selection.

Android owner-thread transport foundation: `android_ime_queue.h` provides a
mutex-protected 16-command FIFO with 1024-byte counted payloads. It rejects
overflow explicitly, accepts only the published opaque owner identity, drops
and scrubs pending payloads when ownership changes, and scrubs consumed slots.
C/C++ host tests cover closed/stale owners, FIFO/overflow, empty composition,
scrubbing and 10,000 producer/consumer transfers; address/undefined-behavior
sanitizers and the focused matrix pass. JNI composition and commit now enqueue
with the owner captured by each Java connection. Queue rejection returns false
without mutating the connection's local Editable. The native looper
now drains a bounded batch, revalidates ownership after each callback, and purges
remaining commands if an application callback retires focus. Keyboard sync
publishes the queue owner and restarts input on same-purpose owner changes;
the JNI owner getter reads only that mutex-protected published identity.
The retained `elisa_android_ime_dispatch` consumer entry now revalidates the
owner before editing and rejects unknown operations, oversized payloads and
missing counted buffers. Host ingress tests exercise an accepted commit and
rejection after same-field refocus or a background/foreground round trip.
This entry is connected to the production queue consumer. Host transport tests
pin full UTF-16 conversion, supplementary scalars and oversized UTF-8 rejection
without delivering a truncated prefix. NDK C and Android Java compilation pass.
Keyboard insets now use a mutex-protected latest-value mailbox and are applied
on the native looper before the edit batch. Host tests cover coalescing, no
producer-side delivery, invalid values and discarding an inset after owner
retirement. NDK compilation passes for this path. APK/device acceptance remains
unverified. Diagnostic reports now enqueue an ordered barrier alongside edits;
only the native loop reads retained text and composition state. Retired-owner
reports are discarded, and secure/unknown-purpose reports redact both text and
composition metadata. Host tests verify edit-before-report order and pending
report retirement; NDK compilation passes. The integrated showcase APK rebuild
passed with the persistent `elisa-skia/out/elisa-android-arm64` library and
explicit stale/dirty stage1 opt-ins, producing
`build/android-ime-queue-validation/showcase/showcase.apk`. Initial compilation
had no device attached; the subsequent read-only Pixel_9 Android 37.1 emulator
run passes `check_android_ime.sh` for queued composition/replacement/commit,
supplementary-character cursor placement, visible/hidden keyboard insets and
root Back fallback. The gate no longer force-stops the Activity before root
Back and requires it to be foreground first. All expected reports and accepted
insets were emitted on the native owner thread. Physical-device, broader IME,
native selection/context-action and interruption acceptance remain open.
The full focused input matrix and transport sanitizers also pass.

Owner identity follow-up: retained focus now has a revision that changes on
focus changes, clearing/reset and virtual-row retirement, but not repeated focus
requests for the same editor. Android's owner-thread snapshot returns a stable
nonzero token for the current session/tree/field/focus/interruption identity,
zero for nonediting surfaces, and a new token after retirement. Host tests pin
composition stability, blur/refocus and interruption behavior. The snapshot is
now mutex-published for JNI reads and queue draining; Java connections capture
it and enqueue edits. UIKit handle
captures now also reject a same-field clear/refocus round trip; its host
regression passes. The previous nine-test native result predates this guard.

Connection-traits coherence follow-up: Java creates its connection and applies
EditorInfo traits from one native owner/purpose pair. An owner-only retirement
invalidates traits until the owner thread republishes both together. Purpose
changes also retire the retained owner token, preventing an old connection from
editing with stale keyboard/privacy traits. Host ingress tests pin that rejection;
transport tests exercise 10,000 concurrent coherent publications/reads.
The focused field also records a traits revision on every effective purpose or
privacy transition. Android includes it in the owner identity, so changing
purpose/privacy away and back without an intervening snapshot cannot revive an
old connection. Identical effective traits do not advance the revision. Ingress
regressions cover purpose and privacy round trips without intermediate queries.

Android composition finish follow-up: `finishComposingText` now queues a
distinct owner-checked unmark operation instead of replacing the provisional
run with an empty string. It preserves text and caret while clearing the marked
range. Retained ingress tests verify non-Latin provisional text survives finish,
unexpected replacement payloads are rejected, and stale-owner finish cannot
reach the editor. Transport tests verify finish is delivered only on drain.

Android selection follow-up: the production `ElisaInputConnection` now lives
in its own Java source and queues `setSelection` with its captured owner. The
native looper converts UTF-16 endpoints through retained range helpers, keeping
anchor/caret direction and normalizing to grapheme boundaries. Host ingress
checks cover reverse selection, surrogate interiors, combining marks, extreme
endpoint clamping, negative endpoints and stale owners. Transport tests cover
deferred delivery and malformed selection payload rejection; NDK and SDK Java
compilation pass. Native selection handles, platform selection/readback updates,
context actions and device acceptance remain unfinished.

Surrounding deletion foundation: `UiFlat::delete_surrounding_utf16` removes
both surrounding ranges atomically while protecting the selection/composition
span and retaining anchor/caret direction. The deleted boundaries expand to
whole graphemes, counts clamp to document bounds, and removed storage is
scrubbed. `text_surrounding_test` covers reverse selection, emoji/combining
boundaries, composing-span preservation, no-op/missing-focus behavior,
composition undo coalescing and secure undo denial. It joins the focused input
matrix (now 19 Elisa fixtures on macOS). Android `deleteSurroundingText` now
queues this operation with its captured owner, rejects negative counts and
returns queue failure before changing the local Editable. The consumer rejects
malformed payloads; retained ingress tests reject stale owners and verify a
current-owner deletion protects the selected span. `deleteSurroundingTextInCodePoints`
now queues a distinct scalar-count operation: traversal is bounded by retained
text bytes, supplementary characters count once, and the resulting deletion
expands to whole graphemes through the same atomic operation. Tests distinguish
scalar counts from UTF-16 counts, exercise forward deletion and partial ZWJ
requests, and clamp extreme counts. Retained Android ingress rejects negative
counts and stale owners; transport tests verify deferred scalar delivery.
Device acceptance is still unverified.

Initial Android selection metadata follow-up: `EditorInfo.initialSelStart` and
`initialSelEnd` now come from the same coherent snapshot as owner and purpose,
not hard-coded zero. The owner thread publishes UTF-16 anchor/caret endpoints
without sorting away reverse selection. Nonediting or owner-only retirement
clears both positions. Host ingress tests cover conversion/direction and inactive
queries; keyboard-sync tests cover selection-only publication without restart;
the concurrent transport fixture verifies all four snapshot fields stay paired.
The snapshot also includes composing start/end (-1 when absent). Changed owner,
traits, selection or composing metadata now schedules
`InputMethodManager.updateSelection` on Java's UI thread; that callback reads the
latest coherent snapshot and rejects retired/nonediting activity state. Unchanged
frames do not repeat notifications. Host tests pin selection-only notifications,
UTF-16 composing endpoints and absent marks. Native
selection UI remains unfinished. The prior emulator gate predates these new
connection-creation/live-selection metadata fields.

Android readback follow-up: `getTextBeforeCursor`, `getTextAfterCursor` and
`getSelectedText` now query a bounded UTF-8 document mirror published with the
same retained selection. JNI returns plain UTF-16 strings from that publication,
never queries widgets on Java's thread, rejects stale owners/negative counts and
omits partial surrogate pairs at bounded slice edges. Secure, unknown-purpose,
retired and nonediting readback is denied; retained staging and native mirrors
are scrubbed before secure/nonediting publication. The legacy diagnostic text
entry uses the same retained readback guard. Host tests cover conversion,
direction, slice boundaries, privacy denial and scrubbing. Reads represent the
latest published state, not a promise that queued edits are already applied.
One-shot `getExtractedText` and API-31 `getSurroundingText` now use a single
native document publication with text and both endpoints copied under one
mutex. Surrounding windows retain reverse selection and document offsets,
clamp extreme counts and omit half-surrogate edges. Host tests exercise the
production window arithmetic and native coherent document/privacy behavior;
NDK compilation, sanitizer checks and the integrated APK build pass. Monitoring
requests with a valid request now register a connection-local token; changed
publications send a full bounded `updateExtractedText` on Java's UI thread.
Text-only changes now trigger publication notifications even when every
selection/composition endpoint stays the same. Owner mismatch, denied readback,
close, replacement and native hide clear the monitor. Host transport tests pin
text-only changes and unchanged-state suppression. Device query/monitoring
acceptance, API-30 loading verification and native selection/context UI remain
unfinished.

Connection-close follow-up: Android's connection now uses a terminal local
session state separate from retained ownership. Close clears monitoring and the
local Editable, requests at most one owner-checked composition finish, and later
readback, composition/commit, selection, surrounding deletion and key forwarding
return null/false before calling native editing. Creating a replacement closes
the prior connection even if the retained owner has not changed. Pure Java
tests exercise closure idempotence, monitor retirement/non-revival and zero
owners. Already accepted queued operations remain ordered; close is not a
promise that pending native work has synchronously completed. Device close and
replacement acceptance remain unverified.

Composing-region follow-up: `setComposingRegion` now queues an owner-checked
metadata operation on existing retained text, preserving selection and value.
Android-style negative/end-of-document clipping, reversed endpoints and retained
grapheme normalization apply; a collapsed range finishes composition. Host
ingress tests cover supplementary/combining text, stale owners, clipping and
unchanged selection; transport tests cover deferred and malformed delivery.
The Java connection now uses BaseInputConnection full-editor mode so queued
text edits do not also enter its synthetic-key fallback. Host suite and APK
build verification cover integration; runtime acceptance of these latest paths
remains open.

Batch-notification follow-up: the Android connection tracks nested
`beginBatchEdit`/`endBatchEdit` calls locally and defers selection/extracted-text
notifications while a batch is open. The outermost end delivers the latest
pending publication; inner ends do not. Unmatched ends do not underflow, and
close clears batch and notification state. Pure Java session tests cover nested
entry/exit, unmatched ends and terminal close. Outermost batches now also defer
native document/selection publication through ordered queue markers. This does
not make retained edits an atomic transaction; broader runtime batch acceptance
remains unfinished.

Native batch transport follow-up: raw queue begin/end markers now reserve one
slot for a matching end, so accepted begins can terminate under ordinary-edit
queue pressure. Nested/stray markers and payload-bearing controls are rejected;
owner changes purge pending data and the reservation. The native consumer
tracks an open batch on its owner thread and defers document/selection
publication until the ordered end; owner retirement cancels the deferral.
Host tests verify a saturated reserved end, FIFO order, stale-end rejection,
unchanged readback across drains inside an open batch, end publication and
retirement recovery. Java/JNI now emit markers only for the outermost batch;
closing an open batch uses the reserved end slot and finishes composition.
BaseInputConnection's internal bookkeeping does not emit redundant markers
around already-queued edits. Host tests cover saturated close and composition
finishing. Sanitizer checks and the isolated Android APK build pass. Retained
callbacks and rendering are not rolled back or made atomic by this transport
mechanism. The opt-in production-connection probe now passes on the read-only
Pixel_9 Android 37.1 AVD: nested begin/end, unchanged extracted readback while
the outer batch remains open, publication of `batch😀` at UTF-16 caret 7 after
the outer end, and closed-connection edit/readback rejection. An ordered native
`batch-inside` report confirms the retained edit is delivered within the batch.
The same gate still verifies composition replacement, keyboard inset show/hide
and unhandled root Back. This uses the explicitly permitted stale Stage1
product; it does not prove real IME batching, saturation/close during an open
batch on device, extracted-text monitor delivery, or physical-device behavior.

Android context-action follow-up: the production InputConnection now accepts
Select All through its owner-checked selection queue. The document end is
resolved on the native owner thread, without reading Java's cached plaintext;
secure-field host coverage verifies selection still works while readback is
denied. Closed connections reject the action. The Pixel_9 Android 37.1 runtime
probe now uses this context action inside its nested batch before replacement,
and the full focused input matrix and APK/runtime gate pass on the same stale
compiler opt-in. Copy/Cut/Paste now enqueue bounded, payload-free action codes
and execute the shared retained clipboard policy on the native owner thread.
Secure Copy/Cut, stale-owner and invalid-action rejection, deferred transport,
and a selected UTF-8 Copy/Cut/Paste round trip have host coverage. A true JNI
return acknowledges queue acceptance, not clipboard completion or eligibility;
the retained policy is rechecked at consumption. The focused suite and APK
build pass. The read-only Pixel_9 Android 37.1 runtime gate now independently
verifies Copy by overwriting the document and pasting the original `batch😀`
back, then verifies Cut empties the document and Paste restores the exact
Unicode value. Closed connections reject Paste. The batch, composition, inset
and root Back checks pass in the same run, with the stale compiler opt-in.
This exercises production InputConnection/JNI/retained clipboard adapters, not
visible native menu interaction. Secure clipboard behavior on device, native
handle/menu presentation and physical-device acceptance remain unfinished.
Unknown context actions explicitly return false.

Android floating-menu follow-up: the focus bridge is now a separate
`ElisaInputView`, with native floating ActionMode presentation driven by
published noncollapsed selection. Each menu captures the current document
owner and rechecks it before enqueueing the shared retained action. Secure or
unknown-purpose snapshots omit Copy/Cut; consumption still applies the actual
retained eligibility policy. Collapse, keyboard retirement, invisible windows
and detachment dismiss presentation. Unchanged selection does not repeatedly
reopen a dismissed menu. APK compilation and the Pixel_9 runtime gate pass,
including the native ActionMode creation callback plus the batch/clipboard/
inset/Back checks, on the same stale compiler opt-in. The menu is currently
anchored to the tiny IME focus bridge, not retained selection geometry. Canvas
long-press activation, selection-relative anchoring, native handles, visible
menu action taps and secure-menu/device acceptance remain unfinished.

Android long-press follow-up: contact ingress now applies a bounded retained
text capture after accepted application delivery. A single contact beginning
over the focused field captures its document owner and text revision; a shared
release-time LongPress result selects that document, allowing published
selection to activate the floating menu. Taps, drags, cancellation, second
contacts, refocus, text replacement and lifecycle retirement fail closed.
`android_text_gesture_test` covers these cases in the focused input matrix and
the production APK builds with the hook. This is release-time activation, not
a timer-driven menu while a finger remains down. Reentrant facts without the
matching recognizer result are ignored. Actual canvas long-press/menu-tap
acceptance, selection geometry anchoring, handles and physical devices remain
unfinished; earlier runtime menu evidence predates this new ingress hook.

Empty-field activation follow-up: an accepted Android long press now records
an explicit owner-bound presentation request even when Select All leaves a
collapsed range. Owner-thread publication consumes the request once and adds a
menu serial to the coherent JNI snapshot; Java can therefore present Paste on
an empty field without exporting plaintext or manufacturing a selection.
Open batches defer request publication, retirement clears the published serial,
and stale pending requests are consumed without reaching the new document.
Java remembers the observed owner/serial pair so an unchanged publication does
not replay a dismissed explicit request. Copy/Cut remain absent for collapsed
selection. Host gesture and transport tests cover empty activation, single
consumption, refocus rejection, batch deferral and owner retirement; the focused
matrix, sanitizer checks and APK build pass on the stale compiler opt-in.
Actual empty-field menu/Paste taps and the other native selection acceptance
requirements remain unverified.

Menu presentation-state follow-up: `ElisaTextMenuState` now owns the pure Java
show/hide/keep decision. An unchanged publication preserves an explicitly
opened collapsed/empty-field menu instead of dismissing it just because the
selection is empty. Remembered request serials are not replayed after dismissal
or retirement; changed collapsed positions dismiss, and malformed snapshots
fail closed. Reverse selection remains eligible for export, but secure,
unknown-purpose and collapsed snapshots do not expose Copy/Cut. The production
view uses this tested policy; the host Java gate and APK build pass. This does
not add native menu tap, anchoring or handle-drag acceptance evidence.

Android presentation interruption follow-up: the activity explicitly enables
menu presentation on resume and disables/dismisses it on pause and destruction.
The menu-state policy starts inactive; background selection notifications cannot
open a menu, and explicit request serials observed while suspended are retired
instead of replayed on resume. Native menu creation and action callbacks also
check the presentation-active flag, independently of retained owner validation.
This only changes transient presentation, not retained selection or text.
Java host tests cover initial inactivity, paused notifications, request replay
denial and new-owner activation. APK compilation passes; device pause during
an open menu or menu action remains unverified.

Canvas long-press runtime follow-up: the Pixel_9 Android 37.1 gate now sends a
real stationary 1.2-second MotionEvent press to the focused canvas field after
the connection probe finishes. Native down/up timestamps span 1.210 seconds;
the owner-thread policy produces explicit menu request serial 1, which reaches
the floating ActionMode creation callback. One Back destroys that menu; the
subsequent root Back backgrounds the activity, with foreground verified before
root navigation. Both predictive and legacy application Back entry points now
dismiss an active text menu before forwarding retained navigation. Batch,
Unicode clipboard, composition and visible/hidden inset checks pass in the same
run on the unchanged stale compiler product. This confirms release-time canvas
activation and Back precedence, not hold-time activation, visible menu-action
taps, empty-field Paste, selection-relative anchoring, native handles or pause
during an open menu.

Android long-press, clipboard and secure-field acceptance: the opt-in probe
checks visible Copy, empties the retained field while preserving exact
`batch😀`, then requires the empty-field menu to show Paste but not Copy/Cut;
the observed Paste tap restores the exact Unicode value. A self-targeted
instrumentation APK correlates floating-toolbar item IDs with the active
Showcase window and taps only observed bounds. The secure phase focuses the
real Password field, checks password/no-suggestions/no-personalized-learning
EditorInfo traits, writes and selects only the synthetic `probe-secret`, then
queues an owner-bound Copy attempt. An ordered native report is `secure=redacted`,
the preexisting `batch😀` clipboard sentinel remains unchanged, and the
accessibility audit sees Paste but no Copy/Cut or synthetic value. No secret
value appears in the app log. The strict `check_android_ime.sh` gate passes on
the read-only Pixel_9 Android 37.1 AVD, including composition, batch, long press,
visible Copy, empty-field Paste, secure clipboard denial/menu policy, keyboard
inset show/hide, menu dismissal and root Back fallback. It used current Stage1
HEAD `98abcee1214b8d720915f3cd60361e78056bad58` (`origin/main`, clean), product
SHA-256 `734fad7984b0c6de3b50e6d57585e3c8573f975c33e4560f647a1209f9ed828d` and
runtime `0db509f791ec1b075049dadc51a44f6e51e93e7c8fa9e6db4acbc336b7de022e`,
with the strict current-toolchain check and no stale/dirty override. This is
emulator-only evidence. Root-view presentation remains window-relative, not
selection-relative; native handles, mid-drag interruption and physical-device
acceptance remain open.

Interruption presentation follow-up: accepted focus loss, background and
surface loss now immediately ask the native view to dismiss its menu, deactivate
selection display and cancel a captured handle pan. Elisa owns that lifecycle
decision; retained selection and first-responder state are not cleared by the
presentation primitive. The attached-surface host fixture verifies all three
calls, foreign-view rejection and headless no-op behavior. The focused matrix
passes and the simulator app builds. The nine-test native gate passes in
189.025 seconds with this change: select Unicode range 0..2, press Home,
reactivate the same process, verify retained selection and handle/keyboard
recovery, then commit exact emoji-preserving replacement. Mid-drag interruption,
lock/unlock, process restoration and physical-device acceptance remain open.

UIKit simulator evidence: the smoke app selects Email purpose on a retained
field. `check_uikit_touch.sh` passes all nine XCUITests, including the native @ key
after switching from the already-active Name keyboard, plus cancellation/taps
and committed-text round-trip. This confirms native purpose switching in the
simulator on the existing stale compiler, not physical-device secure-keyboard
or Android IME acceptance.


Viewport-size or content-inset changes re-reveal an eligible focused text
field through its scroll ancestors. Nested reveal reflows after each inner
offset change so the outer viewport uses the updated descendant frame and
does not over-scroll. Ordinary offset changes do not trigger automatic focus
reveal, preserving user scrolling. `UiHandles::reveal(handle)` requests it
explicitly and rejects stale, hidden or disabled targets.
`mobile_focus_reveal_test` verifies keyboard-inset reveal, ordinary-scroll
preservation, explicit reveal and minimal nested offsets.
The same fixture verifies disabled fields and hidden ancestor subtrees cannot
request reveal or attract scrolling during keyboard-inset relayout.
It also rebuilds the tree with the same field slot: the retired typed handle
is rejected while the replacement handle can request reveal, proving the
generation guard rather than only an out-of-range check.
Geometry/text-layout regressions also pass on the existing stale compiler. This reveals the field's
retained box; device keyboard/caret/selection-handle workflows and caret-only
reveal for oversized multiline fields still need acceptance work.

Range units are explicit at the boundaries. The retained editor stores
selection and marked positions as UTF-8 byte offsets; `UiFlat::set_selection`
and the legacy `UiHandles::set_selection` accept those byte offsets and floor
them to extended-grapheme boundaries. `UiHandles::set_selection_utf16` accepts
UTF-16 code units, as do the selection/marked getters and the AppKit/UIKit text
protocol adapters. SDL3 and the C callback contract express IME composition
ranges as UTF-8 scalar counts, not bytes; those adapters bound the scalar range
before mapping it into the retained editor. UTF-16 offsets inside a surrogate
pair resolve to the scalar's leading boundary, then selection setters apply the
grapheme boundary rule. `UiFlat::text_range_location` and `text_range_length`
use UTF-16 units; `text_range_pointer` and `text_range_byte_length` address the
corresponding UTF-8 storage. These units must not be interchanged.

Editor diagnostic underlines are independent of the IME marked-text range.
`UiHandles::set_text_underline` stores bounded underline slots in UTF-16 units;
ranges clamp to the current field text, transparent ink clears a slot, and a
zero-width range paints a short marker. The retained painter maps those
boundaries through the same text advances used for caret placement, so a
diagnostic underline does not replace or move the active composition
decoration. `widget_layout_diagnostic_underline_test` covers supplementary-
plane offsets, clamping, zero-width markers, and clearing diagnostics while
composition remains active. This is retained/painted-field behavior; native-
control editor integrations remain backend-specific.

The retained `TextField` is single-line. Committed, programmatic, and clipboard
insertions normalize control and Unicode line-separator bytes to spaces;
`widget_layout_text_test` pins multiline clipboard paste to the normal insert
path.

Word-wise caret movement and deletion are reachable from the keyboard on every
backend that routes through the flat keyboard handler (SDL3, WasmBrowser,
UIKit): Alt/Option or Control with Left/Right moves by word, Shift extends the
selection, and Alt/Option or Control with Backspace/Delete removes a word.
Alt/Option is tracked as an independent modifier so macOS and desktop
Linux/Windows conventions both work. The AppKit canvas reaches the same shared
helpers through its menu selectors, so both input paths agree.
`test/word_navigation_test.elisa` covers the routing and the grapheme-safe word
boundaries.

Known hosted limitation: the current `wasmbrowser:window/guest@0.1.0`
`key-code` enum has `shift` and `control` but no `alt`, so Control+Left/Right
and Control+Backspace/Delete work in the hosted backend while Option/Alt does
not. Adding `alt` is a WasmBrowser WIT change (WB-05), not a local override;
until then the hosted adapter uses the Control convention.
