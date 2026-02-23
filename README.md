# crumblez

A Zig port of [femtomc/crumble](https://github.com/femtomc/crumble), a Strudel-style
pattern engine for algorithmic music.

## Current status

Phase-1 core parity is delivered, phase-2A helper baseline is delivered, and
phase-2B applicative/monadic baseline is now delivered (with documented scope
limits).

Implemented so far:

- Zig 0.15.2 package + build/test wiring
- Core timing/event/state primitives:
  - `Fraction` parity pass (arith/cmp/min/max, `sam`/`nextSam`/`cyclePos`, floor/ceil, gcd/lcm, safe `fromF64` policy)
  - `TimeSpan`
  - `Hap(T)`
  - `State`
- Composable pattern core:
  - `Pattern(T)` with `pure`, `silence`
  - query helpers (`query`, `queryArc`, `firstCycle`)
  - phase-1 combinators/transforms: `stack`, `slowcat`, `fastcat`/`sequence`/`cat`, `fast`, `slow`, `early`, `late`, `rev`
  - utility-phase combinators/signals: `euclid`, `euclid_rot`, `range`, `saw`, `sine`, `cosine`, `tri`, `square`
  - phase-2A composition baseline: `first_of`, `every` (current alias semantics), `when`, `ply`, `layer`, `superimpose`, `interleave` (current `fastcat` alias), `timecat` (weighted slices)
  - phase-2B applicative/monadic baseline: `app_both`, `app_left`, `app_right`, `join`, `outer_join`, `inner_join`, `squeeze_join`, `bind`, `outer_bind`, `inner_bind`, `squeeze_bind`
- Focused Rust→Zig semantic parity tests plus mapping notes in `PHASE1_RUST_TEST_MAPPING.md` (including phase-2A and phase-2B parity-style extensions)

Validation status (current checkpoint):

- `zig fmt src`
- `zig test src/root.zig`
- `zig build test`
- Current result: passing (`63/63` tests)

## Near-term roadmap

See [`PORTING_PLAN.md`](./PORTING_PLAN.md) for phased port milestones.

## Development

```bash
zig build
zig build test
```

## Notes

- Target Zig version: `0.15.2`
- License intent is AGPL-3.0 (matching upstream crumble/Strudel lineage)
