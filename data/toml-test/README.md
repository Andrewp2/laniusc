# Official TOML conformance data

`v2.2.0/` contains exactly the TOML 1.1.0 index, its 214 valid inputs, 467 invalid
inputs, 214 upstream typed expected results, and the license from
[`toml-lang/toml-test` v2.2.0](https://github.com/toml-lang/toml-test/tree/v2.2.0).
The pinned commit is `ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c`.
`SOURCE.json` records archive provenance and every copied file's SHA-256;
the verifier independently anchors the complete file-hash manifest.

```sh
timeout --kill-after=2s 100s python3 tools/toml_test/corpus.py --verify
```

The importer only copies source data from a checksum-matched official archive.
It does not implement TOML. The executable tests query Lanius's real typed
document and encoding APIs through a test-only binary harness. Upstream JSON
expected results are test data; no host parser or JSON transport implements
the production library.

Preserve every corpus byte, including CRLF, trailing whitespace, invalid UTF-8
and intentionally incomplete syntax. The local Git attributes disable text
normalization/diffs for these immutable upstream fixtures. Inspect individual
files directly when investigating a case; the manifest verifier detects edits.

The corpus's license is retained at `v2.2.0/LICENSE`. No tests outside the
official `files-toml-1.1.0` index are silently substituted for this version.
