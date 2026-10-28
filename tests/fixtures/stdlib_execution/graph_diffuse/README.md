# Graph diffusion application fixture

The reference assembles a small dense `I + lambda*L` in the specified original
record order, then solves it by exact `Fraction` Gaussian elimination. It does
not use CSR indexing, CG, Jacobi, recursive residuals or the production solver.
Separate scalar/two-node closed forms check the model itself. Large admission
cases use explicit identity solutions and do not create dense 4096-square
reference matrices.

Every successful output must contain all nodes in order, the exact `node,value`
header, fully quoted CRLF CSV and finite values. Small-system checks compare
the solution with elimination, recompute the true residual using ascending
dense binary64 products, and check component mass and the source min/max bound.
The residual predicate allows only `2e-14` relative slack at the stopping
boundary for independent norm rounding. There is no added absolute residual
tolerance. Loose tolerance cases explicitly expect the initial zero solution.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 36 | Closed forms, signed/ordered repeated sources, duplicate and reversed edges, ignored self-loops, disconnected components, zero lambda, zero-iteration convergence, final-step convergence, subnormals, maximum dimensions/records/input and seeded dense systems |
| rejection | 48 | Schema/CSV/UTF-8/finite/endpoint/field/record/input bounds, full validation before arithmetic, nonconvergence, full requested work, assembly overflow, lost-identity breakdown and ordinary dot overflow/underflow |
| cli | 55 | Nodes/iterations grammar and bounds, all finite option bounds, missing/duplicate options, argument caps, help validation/input bypass and attached/equal forms |
| io | 15 | Actual directory stdin, closed data/help stdout, traced baseline, eight reached mmap denials including six CG workspace buffers, read/write EINTR and SIGPIPE setup failure |

The I/O graph has seven nodes and two signed source terms. Its trace selects
the current solver's six consecutive seven-element binary64 reservations
(x/r/z/p/q/Jacobi diagonal), plus early construction and late output staging.
Each selected ENOMEM must actually occur with matching baseline mmap arguments,
return status 4 and publish no output. Allocation order is not a public ABI.
Every observed successful mmap must match a successful munmap of the same
address and size. This finite syscall observation is not a resource checker,
an exhaustive denial campaign, a lifetime/alias check or a leak-freedom proof.

The larger triplet and staging caps are application bounds, not independently
reached by these fixtures under the tighter record/node limits. The model
does not assert universal CG convergence or that finite rounded coefficients
remain SPD when enormous weights lose the identity contribution.

```sh
python3 -B tests/fixtures/stdlib_execution/graph_diffuse/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/graph_diffuse/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_diffuse/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_diffuse/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_diffuse/oracle.py io PATH_TO_ELF
```

Each native child has a 25-second deadline; each registered group has an
85-second deadline. Commands, input, stdout, stderr, status and optional traces
are retained per case. CPU controls check hand-derived systems, ignored huge
self-loops, ordered source rounding, exact-cap construction, canonical output,
false convergence rejection, all generated solution references, case counts
and a deliberately missing release.

## Acceptance

The four registered groups passed on 2026-10-28: model 36, rejection 48,
CLI 55 and I/O 15, totaling **154 native Linux x86_64 cases** in 17.42 seconds.
The driver used the GPU compiler to emit CPU output and passed the shared
strict ELF checker. Receipt:
`target/stdlib-work/graph-diffuse-runtime-first.log`.

Accepted evidence directories:

- Model: `/tmp/graph-diffuse-model-545r1cw2`.
- Rejection: `/tmp/graph-diffuse-rejection-u_jgi3yt`.
- CLI: `/tmp/graph-diffuse-cli-j_dh0dvh`.
- I/O: `/tmp/graph-diffuse-io-t6xfmbau`.

Executed application SHA-256:
`f73d63e0b7f06555457ca7ecd3a257b12de39eec63b5b0affac88d6d9a5a5045`.
Oracle SHA-256:
`9e18d964008cbf4c0d3a0a1a65649eb94fbb5f6773092e61b76b6d08f79f2fe4`.
Root-formatted driver SHA-256:
`4243d2f1eb2a37d9e1539ba51d9b1809ce3e091115515665093095f7a55ec452`.

Eleven CPU-only controls also passed. The native I/O receipt includes the
eight selected reached ENOMEM sites and matching observed successful
mapping/release pairs. This covers finite application behavior and those
faults; it does not establish leak freedom, universal convergence,
device-side execution, formal verification or exhaustive fault coverage.
