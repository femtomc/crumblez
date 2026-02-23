# crumblez

A Zig port of [femtomc/crumble](https://github.com/femtomc/crumble), a Strudel-style
pattern engine for algorithmic music.

## Current status

Phase-1 core parity checkpoint is now delivered.

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
- Focused Rust→Zig semantic parity tests plus mapping note in `PHASE1_RUST_TEST_MAPPING.md`

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
