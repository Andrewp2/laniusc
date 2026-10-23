# wave-tool

`sample_programs/library/wave_tool.lani` is a native stdin-to-stdout WAVE transformer using `ext::cli`, bounded stream I/O, `ext::wave`, `ext::audio`, finite decimal parsing and core formatting.

```sh
laniusc --stdlib-root stdlib --source-root extended sample_programs/library/wave_tool.lani -o wave-tool
chmod +x wave-tool
./wave-tool --gain 0.5 --mono --pcm-bits 24 < stereo.wav > quiet-mono.wav
./wave-tool --stats < stereo.wav > channels.csv
```

The default decodes input then writes canonical WAVE at the input's container format. It keeps rate/channel order/sample content subject to format conversion; it discards source metadata chunks and extensible declarations. `--gain FACTOR` applies a finite linear multiplier; `--mono` averages all channels equally after gain; `--pcm-bits 8|16|24|32` selects saturating PCM output. Gain overflow is an error. Floating output retains finite values outside [-1,+1]. No sample-rate conversion or playback is performed.

`--stats` writes CSV with `channel,frames,sample_rate,peak,rms,dc` for each resulting channel after gain and mono. Empty audio can be re-encoded; empty audio statistics return an error. `--stats` conflicts with `--pcm-bits`. Channel indices are zero based. `--help` prints usage and must appear alone. Short forms: `-g FACTOR`, `-m`, `-s`, `-h`. Repeated options, operands, invalid numbers and unknown options fail.

Resource flags: `--max-input-bytes N` (default/hard cap 67108864), `--max-samples N` (default/hard cap 8000000 interleaved samples), `--max-output-bytes N` (default/hard cap 67108864). Zero limits are valid and ordinarily cause a resource error. Argument capture is bounded to 24 arguments and 4096 bytes; gain literals are at most 64 bytes and decimal parsing uses bounded work. Total codec/transform/metrics work is linear in accepted bytes and samples. CSV uses bounded temporary storage proportional to channels.

All input bytes are collected, decoded and transformed before any stdout write. WAVE bytes or the complete CSV are staged before publication. Parse, signal, resource and allocation errors leave stdout empty. An output I/O error can leave a prefix already written to stdout; use a temporary destination plus rename when durable file replacement is needed. Short reads/writes and EINTR are handled by core I/O. All argument, input, sample, mono and output allocations are explicitly released on success and every error branch.

Exit codes: 0 success; 2 invalid arguments/WAVE/signal or resource limit; 3 I/O failure; 4 allocation failure. Errors write a diagnostic to stderr; diagnostic failure returns 3. WAVE support and reader tolerances are specified in [extended-wave.md](extended-wave.md).

`tests/extended_wave_tool_execution.rs` cross-checks all four PCM output widths against Python `wave`, gain plus mono, per-channel CSV metrics, argument/resource failures and empty/truncated input. Float64 cancellation regressions check that both mono output and CSV DC retain the exact mean of `[f64::MAX,1e-300,-f64::MAX]`. A strace mapping ledger injects ENOMEM at every allocation in a real gain/mono/PCM24 run (11 allocation sites in the checked workload), checks no mappings remain, retries read/write EINTR, rejects EIO, exercises positive short writes and `/dev/full`, and verifies staged stdout on pre-publication failures. Independent Python is test code only; the program is entirely Lanius.
