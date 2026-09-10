# Refinement types

A refinement type is an ordinary type plus a bound the compiler carries with the
value: `i64 is UiChannel` is an `i64` that is between 0 and 255. The bound is
erased at run time -- the machine sees an `i64` -- and checked at compile time,
at every call that has to satisfy it.

## Why this repository has them

A packed colour. `Color` stores four `u8` fields, so a channel cannot be out of
range while it is a field. The moment it becomes a term in

    a * 16777216 + r * 65536 + g * 256 + b

it is an ordinary integer with no bound of its own, and an opaque colour packs
to `0xff000000` -- larger than any positive `i32`. The first version of this
arithmetic returned `i32`, and the framework traps on overflow rather than
wrapping, so it died with exit 133 inside a screenshot fixture. Both the wrong
version and the right one type-checked: nothing in `i32` or `i64` said which one
belonged there.

So the bound is written down instead:

    law UiChannel(self: i64) = self >= 0 and self <= 255
    law UiPackedArgb(self: i64) = self >= 0 and self <= 4294967295

and `UiCore::pack_channels` demands four proven channels and promises a proven
word. Passing an unconstrained integer is now a compile-time finding, not a
trap in whatever test happens to exercise that colour.

## The shape that works

Laws are proved from GUARDS, not from arithmetic over several premises. A
function that adds four bounded values cannot have its result's bound inferred,
so a law is ESTABLISHED in one place -- a small guarded constructor -- and
DEMANDED everywhere else:

    def channel(value: i64) -> i64 is UiChannel:      # establishes
        return 0 if value < 0
        return CHANNEL_MAX if value > CHANNEL_MAX
        return value

    def pack_channels(a: i64 is UiChannel, ...) -> ...  # demands

That split is the whole discipline. `channel` and `packed_word` are the only
places a value acquires a bound; every other signature in the family requires
one it did not create.

## What a refinement is not

It is not the repository's fail-closed sanitizing (`bounded_coordinate`,
`is_finite`, the event-queue rejections). Those exist because a native host or a
C caller can hand the framework nonsense at run time, and the answer there is to
clamp or refuse, not to prove. Refinements are for bounds that hold by
construction inside the framework, where clamping would hide the mistake rather
than report it. Use a law when a violation would be a bug in this repository;
use a sanitizer when it would be a fact about the outside world.

## Keeping them honest

A refinement fails silently in both directions: it can stop being checked, and
every call site keeps compiling as if the bound were there; or it can become
impossible to satisfy, and quietly falls out of use. `scripts/check_refinements.sh`
compiles one fixture that must be reported and one that must not, and holds
`src/` to the second standard. It runs in `scripts/run_tests.sh`.

The compiler reports an undischarged obligation as a non-blocking finding
(`refinement on argument N of "f" could not be proven statically`). It does not
fail the build by itself -- this repository's gate is what makes it fatal.
