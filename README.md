# crumblez

A Zig port of [femtomc/crumble](https://github.com/femtomc/crumble), a Strudel-style
pattern engine for algorithmic music.

## Current status

This repository is in bootstrap stage.

Implemented so far:

- Zig 0.15.2 package + build/test wiring
- Core timing primitives:
  - `Fraction`
  - `TimeSpan`
  - `Hap(T)`
  - `State`
- Minimal pattern core:
  - `Pattern(T)` with `pure` and `silence`
  - `query`, `queryArc`, `firstCycle`
- Unit tests for the modules above

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
