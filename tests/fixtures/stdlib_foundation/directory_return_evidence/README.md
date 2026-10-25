# Directory return admission observation

The preserved source was the production `stdlib/std/directory.lani` during the
first focused native walk admission. `directory-contracts-third.log` and the
explicitly qualified/annotated `directory-contracts-qualified.log` both report
LNC0006 at `let directory: Directory = core::result::unwrap(opened)` before native
code runs. The complete qualified source and its SHA-256 are retained here.

The source used the normal repository `stdlib` root and
`tests/fixtures/stdlib_foundation/directory_contracts.lani` entry. The exact test
was `cargo test --test stdlib_directory_execution
directory_iteration_walk_limits_and_cleanup_execute -- --exact --nocapture`,
with the established stdlib-build target and shared GPU lock. The second log
uses `std::directory::open` and an explicit `Result<Directory, Error>` annotation.

The direct `empty_directory() -> Directory` call also failed after introducing
caller-owned construction; that source is retained before the Reader rename.
`directory-contracts-into.log` records the direct-return failure.
Renaming just the owner type to Reader (while retaining the imported
`std::file_ops::Kind::Directory` variant), and updating the fixture annotation,
admitted the full native walk/limits/cleanup contract: one test passed in 5.13s.
An otherwise identical nine-word CursorOwner direct-return control independently
compiled and ran with status zero. The retained reader log records the full walk
result.
`reader_positive_control.lani` is derived from the before-reader source by just
that type-name replacement; no field layout or algorithm changes are included.

These controls support a type/variant spelling collision as the specific
candidate. No compiler field ceiling or general root cause is claimed. The
public owner is named Reader; ergonomic open results and atomic caller-owned
construction are both supported. Retained source files are diagnostic data,
not alternate production modules or minimized compiler regression tests.

The retained logs omit preceding build warnings and normalize trailing whitespace;
raw captured logs remain under `target/stdlib-work/directory-return-raw-logs/`.
The later general type/value-row guard and native regression controls are recorded
in [variant_type_collision](../../stdlib_compiler_state/variant_type_collision/README.md).
The Reader spelling remains the public iterator-owner API.
