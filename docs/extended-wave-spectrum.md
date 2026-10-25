# wave-spectrum

`sample_programs/library/wave_spectrum.lani` reads WAVE from stdin, downmixes channels with the correctly rounded exact arithmetic mean from `ext::audio`, optionally applies a box FIR filter, applies a window, pads to a power of two, and emits positive-frequency spectral bins as CSV. It composes `ext::wave`, `ext::audio`, `ext::signal`, `ext::cli`, checked descriptor I/O, and core formatting. Production computation is Lanius.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended sample_programs/library/wave_spectrum.lani -o target/stdlib-work/wave-spectrum
timeout --kill-after=2s 100s target/stdlib-work/wave-spectrum --window hann --fft-size 4096 < sound.wav > spectrum.csv
```

The CSV header is `bin,frequency_hz,magnitude,power`. For transform size N and sample rate R, each row k has frequency `R*k/N`, magnitude `abs(X[k]/N)`, and power `abs(X[k]/N)^2`. Rows run from zero through N/2 inclusive, or just zero for N=1. Interior bins are not doubled and window gain is not corrected. Thus an unwindowed unit cosine on an exact interior bin has magnitude 0.5 at its positive bin. Power is a per-complex-coefficient value, not a calibrated power spectral density or a one-sided energy sum.

| Option | Default | Meaning |
| --- | --- | --- |
| `--window rect\|hann\|hamming\|blackman`, `-w` | hann | Window applied before zero padding |
| `--symmetric` | off | Use symmetric window endpoints; otherwise periodic |
| `--fft-size N`, `-n` | next power of two | Explicit power of two in 1..1,048,576, at least the filtered sample length |
| `--smooth N` | 1 | Full causal box FIR convolution with N coefficients, each `1/N`; N in 1..4096 |
| `--max-input-bytes N` | 16,777,216 | Complete WAVE input byte limit, at most 67,108,864 |
| `--max-samples N` | 65,536 | Interleaved decoded sample limit, at most 1,048,576 |
| `--max-output-bytes N` | 8,388,608 | Complete staged CSV limit, at most 67,108,864 |
| `--max-work N` | 268,435,456 | Cumulative abstract processing charge |
| `--help`, `-h` | off | Usage; must appear alone |

There are no file operands; use stdin/stdout redirection. Repeated options, invalid numbers, unknown windows/options, and operands fail. Empty WAVE audio is rejected. The sample limit counts all channels before downmixing. The signal library's default element and temporary output limits also apply; neither the input nor filtered output is truncated to fit an FFT size.

`--smooth N` retains the full `samples + N - 1` output, including the zero-extended filter tail, before windowing. This can change the automatically selected FFT size. It is an equal-weight FIR smoother with no speaker or physical-frequency assumptions. Direct convolution has an explicit N*M work cost; a large filter can exceed the budget before processing.

The cumulative budget charges four units per input byte, eight per decoded interleaved sample, the library's exact convolution/real-FFT/bin charges, and 512 per emitted bin for bounded CSV staging. These are abstract policy units, not machine instruction or byte-read counts. Input staging has its own byte limit; charge validation before decoding bounds the subsequent pipeline. Memory is bounded by the input/sample/temporary/output limits, and allocation failure is explicit.

All input, processing, and CSV formatting finish before the first stdout write. Invalid input, numerical errors, resource limits, and allocation failure publish no CSV prefix. All owners are destroyed on every exit path. Once writing begins, an I/O failure may leave a visible output prefix. Interrupted I/O retries; other read/write failures return status 3. No FFT succeeds with NaN or infinity: extreme finite samples may produce a numerical error when an intermediate transform or spectral power is not representable. See [the signal numerical contract](extended-signal.md).

Exit codes: 0 success/help, 2 invalid arguments/WAVE/signal or resource limit, 3 I/O failure including diagnostics, 4 allocation failure. Failures write one diagnostic to stderr when writable.

Focused tests compute independent direct DFTs from decoded logical samples, verify every window and optional filtering, parse CSV numerically, cover malformed/empty/oversized input and arguments, deny every allocation while checking cleanup, and inject read/write EIO and EINTR. See [WAVE format scope](extended-wave.md) for PCM/IEEE formats, extensible metadata, and reader tolerances.
