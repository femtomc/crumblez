# crumblez porting plan

This plan ports `femtomc/crumble` (Rust) into `crumblez` (Zig) in small,
verifiable milestones.

## Phase 0: bootstrap (completed)

- [x] Create repo + workshop submodule
- [x] Initialize Zig package/build/test setup
- [x] Port foundational time/event types (`Fraction`, `TimeSpan`, `Hap`, `State`)
- [x] Add minimal `Pattern` support (`pure`, `silence`, `query`)

## Phase 1: pattern semantics parity (core) (completed)

- [x] Port key constructors/combinators:
  - `stack`, `slowcat`, `fastcat`, `sequence`, `cat`
  - `fast`, `slow`, `early`, `late`, `rev`
- [x] Port utility combinators:
  - `euclid`, `euclid_rot`
  - `range`, `saw`, `sine`, `cosine`, `tri`, `square`
- [x] Port representative Rust tests for semantic parity (see `PHASE1_RUST_TEST_MAPPING.md`)
- [x] Complete phase-1 parity dependencies: Fraction parity updates and TimeSpan/Hap/State helper edge-case semantics

## Phase 2: richer composition model

### Phase 2A: composition helper baseline (completed)

- [x] Add higher-level helper baseline:
  - `first_of`, `every`, `when`
  - `ply`
  - `layer`, `superimpose`
  - `interleave`, `timecat`
- [x] Add focused parity-style coverage for phase-2A helpers
- [x] Validate phase-2A checkpoint with:
  - `zig fmt src`
  - `zig test src/root.zig`
  - `zig build test`

### Phase 2B: composition semantics deepening (next)

- [ ] Add combinator/applicative/monadic ops (`app_*`, `bind`, joins)
- [ ] Add context/location propagation support
- [ ] Deepen helper semantics beyond conservative phase-2A baseline (`every`, `interleave`, `timecat`, `superimpose` transform-overload behavior)

## Phase 3: DSL and runtime integration

- [ ] Port Lisp parser/evaluator (`lisp.rs`)
- [ ] Port scheduler/player loop in Zig style
- [ ] Decide and implement audio/OSC output strategy

## Phase 4: compatibility and hardening

- [ ] Build parity test corpus against Rust reference outputs
- [ ] Add fuzz/property tests for time arithmetic and combinator laws
- [ ] Benchmark memory + latency and optimize allocator behavior

## Success criteria

- Core pattern semantics behave equivalently to Rust `crumble`
- A representative set of upstream tests pass in Zig
- Zig API is ergonomic for future CLI/realtime integrations
