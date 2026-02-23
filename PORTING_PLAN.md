# crumblez porting plan

This plan ports `femtomc/crumble` (Rust) into `crumblez` (Zig) in small,
verifiable milestones.

## Phase 0: bootstrap (in progress)

- [x] Create repo + workshop submodule
- [x] Initialize Zig package/build/test setup
- [x] Port foundational time/event types (`Fraction`, `TimeSpan`, `Hap`, `State`)
- [x] Add minimal `Pattern` support (`pure`, `silence`, `query`)

## Phase 1: pattern semantics parity (core)

- [ ] Port key constructors/combinators:
  - `stack`, `slowcat`, `fastcat`, `sequence`, `cat`
  - `fast`, `slow`, `early`, `late`, `rev`
- [ ] Port utility combinators:
  - `euclid`, `euclid_rot`
  - `range`, `saw`, `sine`, `cosine`, `tri`, `square`
- [ ] Port representative Rust tests for semantic parity

## Phase 2: richer composition model

- [ ] Add combinator/applicative/monadic ops (`app_*`, `bind`, joins)
- [ ] Add context/location propagation support
- [ ] Add higher-level helpers (`every`, `ply`, `timecat`, `interleave`, etc.)

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
