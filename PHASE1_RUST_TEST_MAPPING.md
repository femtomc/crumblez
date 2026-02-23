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
