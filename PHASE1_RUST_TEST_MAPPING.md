# Phase-1 Rust -> Zig parity test mapping

Source reference: upstream `femtomc/crumble` at `src/pattern.rs` (tests module).

Focused subset translated for current phase-1 implemented features:

| Rust test name | Zig test name | Notes |
| --- | --- | --- |
| `test_sequence` | `rust parity: test_sequence preserves value order` | Verifies `sequence`/`fastcat` first-cycle ordering. |
| `test_slow_hap_whole` | `rust parity: test_slow_hap_whole span semantics` | Verifies `slow(2)` whole/part span semantics in first cycle. |
| `test_rev` | `rust parity: test_rev reverses sequence by onset` | Sorts by onset and checks value reversal semantics. |
| `test_slowcat_alternates` | `rust parity: test_slowcat_alternates wraps on cycle 2` | Confirms cycle alternation and wraparound behavior (`a`,`b`,`a`). |
| `test_bjorklund_algorithm` | `rust parity: test_bjorklund_algorithm` | Direct vector parity checks for 3/8, 5/8, and 4/12 rhythms. |
| `test_euclid` + `test_euclid_edge_cases` | `rust parity: test_euclid and edge cases` | Verifies hit count and 0/8 + 8/8 behavior. |
| `test_euclid_positions` | `rust parity: test_euclid_positions and rotation` | Verifies 3/8 hit onsets and adds `euclid_rot` onset parity. |
| `test_euclid_5_8_positions` | `rust parity: test_euclid_5_8_positions` | Confirms 5 hits in a 5/8 Euclidean pattern. |
| `test_signal_range` | `rust parity: test_signal_range` | Checks sampled signal amplitudes stay within expected bounds for saw/sine/tri/square. |
| `test_range_scaling` | `rust parity: test_range_scaling` | Checks scaled sampled range values remain within requested bounds. |

Also covered in Zig semantic tests (phase-1 helpers):

- Rust `test_fast` -> Zig `fast doubles event count over first cycle`
- Rust `test_early` -> Zig `early shifts query sampling earlier`
- Rust `test_fastcat_two_things` -> Zig `fastcat splits cycle across patterns`
- Rust stack semantics -> Zig `stack combines events from both patterns`
- Utility signal shape checks -> Zig `utility saw stays in [-1,1) over first cycle`, `utility sine and cosine stay within unit amplitude`, `utility tri and square hit expected extrema`, `utility range ramps between provided bounds`

## Phase-2A parity-style mapping extensions

These entries cover newly landed combinators in `core/crumblez` with parity-style
semantics checks. Upstream Rust does not currently expose 1:1 test names for each
case, so these are tracked as Zig-side extensions scoped to phase-2A.

| Phase-2A feature | Zig test name | Notes |
| --- | --- | --- |
| `first_of` window transform | `phase2a parity: first_of transforms first cycle in each window` | Verifies transformed cycle then unmodified cycle across 2-cycle window. |
| `every` baseline semantics | `phase2a parity: every aliases first_of semantics` | Confirms conservative baseline (`every == first_of`) noted in implementation caveats. |
| `ply` | `phase2a parity: ply triples density for pure source` | Checks event density increase with `copies=3` over one cycle. |
| `layer` + `superimpose` | `phase2a parity: layer and superimpose stack values` | Verifies stacked event cardinality and value ordering. |
| `interleave` | `phase2a parity: interleave matches fastcat segmentation` | Confirms current phase-2A aliasing behavior to `fastcat`. |
| `timecat` | `phase2a parity: timecat applies weighted slices and skips non-positive weights` | Verifies weighted slicing plus skip of zero/negative weights. |

## Phase-2B parity-style mapping extensions

These entries cover the new applicative/monadic baseline landed in phase-2B.
They are tracked as Zig-side parity-style checks because upstream Rust tests do
not provide direct 1:1 names for each variant.

| Phase-2B feature | Zig test name | Notes |
| --- | --- | --- |
| `app_both` / `app_left` / `app_right` | `phase2b app operators apply function to value-pattern` | Baseline uses same-type function pointer mapping (`AppFn`), no capturing closures. |
| `join` / `outer_join` / `inner_join` / `squeeze_join` | `phase2b join variants flatten nested patterns` | Baseline currently guarantees flattening for nested pure(Pattern(T)); non-pure nested variants intentionally collapse to silence and are deferred. |
| `bind` / `outer_bind` / `inner_bind` / `squeeze_bind` | `phase2b bind variants map values to patterns` | Baseline uses allocator-aware callback (`BindFn`) with same-type mapping and validates value propagation. |
