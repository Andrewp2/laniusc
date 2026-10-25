# Signal processing

`ext::signal` provides finite binary64 complex arithmetic, radix-2 FFTs, real-input windowed FFTs, standard windows, spectral magnitude/power, and bounded direct linear convolution. Production code is Lanius and uses portable `core::math` trigonometry. There is no host DSP, playback, device, or external FFT dependency.

## Complex arithmetic

`Complex { re: f64, im: f64 }` is a plain value. `complex(re,im)` checks finite components. `add`, `sub`, `mul`, `scale`, and `conjugate` return `Result<Complex,Error>`. They reject nonfinite operands with `NonFinite`; nonfinite computed components return `NumericalFailure`. Multiplication uses ordinary binary64 products and sums, so intermediate overflow may fail even when a differently evaluated mathematical result would fit. Underflow and rounding follow binary64 arithmetic.

`magnitude(z)` returns `sqrt(re²+im²)` using the larger component as a scale. `power(z)` returns `re²+im²` using `large * (large * (1 + (small/large)²))`. These forms avoid raw squaring overflow and avoid dropping two small squared contributions before adding them. A genuinely unrepresentable norm/power returns `NumericalFailure`. Both return +0 for zero magnitude. They do not promise correctly rounded transcendental results.

## Fourier transforms

```lani
let limits: ext::signal::Limits = ext::signal::default_limits();
let transformed = ext::signal::fft(input,ext::signal::Direction::Forward,limits).unwrap();
let restored = ext::signal::fft(transformed.as_view(),ext::signal::Direction::Inverse,limits).unwrap();
// Views borrow their owners. Destroy each owner once after its final use.
restored.destroy(); transformed.destroy();
```

`fft(View<Complex>, Direction, Limits)` returns an independently owned `Vec<Complex>`. Forward computes

`X[k] = sum(x[j] * exp(-i * 2*pi*j*k/N))`.

Inverse uses the positive exponent and divides the completed transform by `N`. Forward is unnormalized; inverse has the factor `1/N`. Output order is natural frequency order: index `k` is `k/N` cycles per sample; bins above `N/2` represent negative frequencies. Output is never bit-reversed.

Length zero returns an empty owner; length one returns a copy. Other lengths must be powers of two. `next_size(count,limits)` gives the least power of two at least `count`, with zero mapping to zero, or a length error. It does not silently truncate data. `fft_work(count)` returns the exact abstract work charge for a supported length.

The implementation is iterative radix-2 decimation in time: copy input, permute into bit-reversed order, and combine pairs in stages of length 2,4,...,N. At each stage offset the twiddle comes directly from `sin_cos` of a bounded angle, then is reused across all blocks at that offset. There is no accumulating trigonometric recurrence. Unity and quarter-turn twiddles are exact. The kernel takes O(N log N) time and uses the single O(N) output buffer plus constant scratch space.

Every input component must be finite. Every butterfly component must remain finite. On failure, the output owner is destroyed and no result is returned. The algorithm does not globally normalize the input by its largest component: such scaling can erase small cancellation residuals across a wide exponent range. Both directions run unscaled butterflies; inverse normalization happens at the end. Consequently an inverse of `[MAX,MAX]` can fail on its intermediate sum although its normalized mathematical result would be finite. Callers needing another scale must choose and account for it explicitly.

These FFTs are numerical approximations. Rounding, underflow, and cancellation can make a small or zero exact bin have a large relative error; accuracy must be assessed against an input norm, not relative to each cancelled bin. No exact residual or bitwise forward/inverse round-trip guarantee is made. Focused tests use direct DFT sums and norm-scaled tolerances, plus exact impulse/cardinal cases. Nonfinite arithmetic is always an error rather than successful NaN/Inf output.

## Windows and real input

`Window` is `Rectangular`, `Hann`, `Hamming`, or `Blackman`. `window_value(kind,periodic,index,length)` computes one coefficient. `windowed(View<f64>,kind,periodic,limits)` returns a new sample vector. Negative lengths or invalid indices fail; an empty vector stays empty and every singleton window has coefficient one.

For lengths greater than one, let `d = N` when periodic, otherwise `d = N-1`, and `a = 2*pi*j/d`:

| Window | Coefficient |
| --- | --- |
| Rectangular | `1` |
| Hann | `0.5 - 0.5*cos(a)` |
| Hamming | `0.54 - 0.46*cos(a)` |
| Blackman | `0.42 - 0.5*cos(a) + 0.08*cos(2*a)` |

Periodic windows suit spectrum analysis; symmetric windows include both endpoints for filter design. Coefficients are clamped to their analytic range `[0,1]` to remove arithmetic roundoff. Hann/Blackman's first endpoint and symmetric last endpoint are exactly zero.

`real_fft(samples, fft_size, kind, periodic, limits)` applies the selected window over the **original sample length**, pads with zeroes to `fft_size`, and performs the forward transform in one owned complex buffer. The size must be supported and at least the input length. Zero input with zero size is empty; zero input with a positive supported size transforms zero padding. It returns the full complex transform; real-input Hermitian symmetry permits callers to select positive bins with a borrowed subview.

## Convolution and spectral bins

`convolve(left,right,limits)` returns the full real linear convolution, with output length `left.len + right.len - 1`, or zero when either input is empty. Input ranges can overlap because the output is independent. All input samples are checked for finiteness, including when the output is empty. The direct algorithm takes O(N*M) time and O(output length) owned storage. It is intended for bounded FIR filters; it does not automatically switch to an FFT algorithm.

Each product uses binary64 rounding; the existing `ext::statistics::CompensatedSum` applies Neumaier compensation when accumulating those products. Product, partial-sum, compensation, or final-result overflow returns `NumericalFailure` and frees the partial owner. Compensation does not recover product-rounding errors or guarantee relative accuracy after severe cancellation. Compare error to the sum of absolute products. Exact-input tests include a cancellation residual that an uncompensated sum would lose. `convolve_work(N,M)` exposes the charge used for preflight, including empty inputs.

`bins(View<Complex>,factor,limits)` returns `Vec<Bin>`, with `Bin { magnitude, power }`. The finite nonnegative factor scales the complex components **before** magnitude/power evaluation, avoiding avoidable overflow in an unnormalized norm. Zero scaling is allowed, but nonfinite source components are still rejected. Negative factors return `Bounds`. The function performs no one-sided doubling, window-gain correction, logarithms, frequency assignment, or decibel conversion. Callers choose those presentation conventions explicitly.

## Bounds, ownership, and work

`Limits { max_len, max_output_bytes, max_work }` defaults to 1,048,576 elements, 16,777,216 output bytes, and 268,435,456 abstract work units. `max_len` must lie in `0..=MAX_LENGTH`, where `MAX_LENGTH = 67,108,864`; `max_output_bytes` must be nonnegative. This hard element bound keeps all complex/bin allocations within the vector allocator's signed byte capacity and keeps size arithmetic bounded.

Charges are deterministic policy units, **not counts of CPU instructions, byte visits, or transcendental iterations**:

| Operation | Charge |
| --- | --- |
| FFT | `N * (4 + 8*log2(N))`; zero for N=0 |
| Window | `4*N` |
| Real windowed FFT | FFT charge plus `4*input_length` |
| Convolution | `N+M+2*L+8*N*M`, where L is the output length |
| Bins | `4*N` |

Each function checks limits before scanning inputs or allocating output. Helpers and scalar complex functions have fixed bounded work. Limits apply per call. Element and output-byte limits are separate, and all owned vector allocations use fallible operations. Errors are `InvalidLimits`, `Bounds`, `Size`, `LengthLimit`, `OutputLimit`, `WorkLimit`, `NonFinite`, `NumericalFailure`, and `AllocationFailed`. FFT size validation can precede view validation.

Borrowed `View` metadata must have nonnegative start/length and their sum must fit `i32`. The caller must provide physical backing for that entire range and keep it alive and unchanged throughout the call; logical checks cannot prove backing or lifetime. No function mutates borrowed input. A returned `Vec` is one manual owner; copies alias its allocation. Destroy it exactly once after using its borrowed views. Any failed operation destroys all internal owners. There is no public in-place FFT with a partially mutated error state.

## Sources and verification

The radix-2 decomposition and bit permutation follow Cooley and Tukey, [“An Algorithm for the Machine Calculation of Complex Fourier Series” (1965)](https://www.cs.jhu.edu/~misha/ReadingSeminar/Papers/Cooley65.pdf), pp. 297–300, especially equations 14–22. The paper uses a positive exponent; this API follows the [FFTW forward sign and frequency ordering](https://www.fftw.org/fftw3_doc/The-1d-Discrete-Fourier-Transform-_0028DFT_0029.html) and adds inverse `1/N` normalization. Direct twiddle computation follows [FFTW's accuracy guidance](https://fftw.org/accuracy/comments.html). Window definitions and periodic/symmetric interpretation match the primary [SciPy Hann](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.windows.hann.html), [Hamming](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.windows.hamming.html), and [Blackman](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.windows.blackman.html) documentation; direct full convolution uses the [standard full convolution convention](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.convolve.html).

Focused native tests compare against independent direct DFT and exact Fraction convolution models, cover real symmetry, windows, inverse/round trips, cardinal transforms, compensated cancellation, all resource categories, nonfinite and overflow errors, borrowed offsets, scale workloads, and allocator denial with a mapping ledger. The real `wave-spectrum` consumer exercises parsing, downmix, optional filtering, window/FFT/bin APIs, staging, and I/O fault cleanup. Python and Rust are oracle/test drivers only.
