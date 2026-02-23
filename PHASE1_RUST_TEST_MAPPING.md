# Phase-1 Rust -> Zig parity test mapping

Source reference: upstream `femtomc/crumble` at `src/pattern.rs` (tests module).

Focused subset translated for current phase-1 implemented features:

| Rust test name | Zig test name | Notes |
| --- | --- | --- |
| `test_sequence` | `rust parity: test_sequence preserves value order` | Verifies `sequence`/`fastcat` first-cycle ordering. |
| `test_slow_hap_whole` | `rust parity: test_slow_hap_whole span semantics` | Verifies `slow(2)` whole/part span semantics in first cycle. |
| `test_rev` | `rust parity: test_rev reverses sequence by onset` | Sorts by onset and checks value reversal semantics. |
| `test_slowcat_alternates` | `rust parity: test_slowcat_alternates wraps on cycle 2` | Confirms cycle alternation and wraparound behavior (`a`,`b`,`a`). |

Already covered in existing Zig tests before this task (same phase-1 area):

- Rust `test_fast` -> Zig `fast doubles event count over first cycle`
- Rust `test_early` -> Zig `early shifts query sampling earlier`
- Rust `test_fastcat_two_things` -> Zig `fastcat splits cycle across patterns`
- Rust stack semantics -> Zig `stack combines events from both patterns`
