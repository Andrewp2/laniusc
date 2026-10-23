# Audio buffers and signal operations

`ext::audio` is Lanius code for finite, interleaved binary64 sample buffers. It has no audio device, playback, capture, resampling, filtering or channel-position host service.

```lani
import ext::audio;
let buffer: ext::audio::Buffer = ext::audio::zeros(48000,2,48000,96000).unwrap();
ext::audio::set_sample(buffer.as_view(),0,0,0.5).unwrap();
ext::audio::gain(buffer.as_view(),0.75).unwrap();
let left: ext::audio::Metrics = ext::audio::metrics(buffer.as_view(),0).unwrap();
buffer.destroy();
```

`Buffer` owns an `alloc::vec::Vec<f64>`, channel count and sample rate. A frame contains one sample from each channel, in channel order. `zeros(frames,channels,rate,max_samples)` allocates silence; `from_view(view,max_samples)` copies samples into an independent allocation. `try_clone(max_samples)` also copies. Rates must be nonzero, channels 1–65535, and samples at most 268435455 and the caller's limit. Zero frames are supported. Counts and indices use signed `i32`; rate is `u32`.

`View` borrows a `core::slice::View<f64>` plus channels/rate. `view` and `validate` reject negative or overflowing signed extents, incomplete frames and invalid metadata. They cannot prove the physical backing extent or lifetime: the caller must provide initialized storage covering the range and retain it for the full borrow. Views may begin at nonzero offsets. `sample` and `set_sample` check frame and channel bounds; the setter rejects NaN and infinities. A view factory validates metadata without scanning sample contents; `check_finite` scans all samples. `sample` retrieves an existing value without a finite check.

Lanius owners copy shallowly. Keep one active owner; borrow through methods and end views before destroying or moving storage. Do not destroy shallow copies. `destroy()` frees storage, clears metadata and may be called again on the same owner. `as_view()` after destruction is invalid. Direct alteration of owner fields must preserve these invariants. No implicit destructor runs.

| Operation | Contract |
| --- | --- |
| `gain(view,factor)` | Multiply in place. Preflight all finite inputs and all products; any nonfinite input/factor or product overflow leaves every sample unchanged. |
| `clip(view,low,high)` | Clamp in place to finite ordered bounds, after a full finite scan. Errors leave all samples unchanged. |
| `mix(left,right,right_gain,max_samples)` | Return a new buffer containing `left + right*right_gain`. Shapes/rates must match. Inputs can overlap. Nonfinite inputs or arithmetic overflow fail before allocation. |
| `mono(view,max_samples)` | Return an independent one-channel buffer, averaging every frame equally. Does not infer speaker weights from channel indices. |
| `metrics(view,channel)` | Return channel peak, RMS, DC mean and frame count. Empty channels return `Empty`; only the selected channel is scanned for finite values. |

All operations are linear in sample count. A full channel metrics sweep is linear in total samples. RMS uses scaled sums of squares to avoid raw-square overflow and underflow, following the scaled sum representation used by [LAPACK LASSQ](https://netlib.org/lapack/explore-html/d8/d76/group__lassq.html). DC and mono return the correctly rounded exact arithmetic mean of their finite binary64 inputs, independent of input order. They retain cancellation residuals across the full exponent range and permit an exact sum outside binary64 range before division. Exact zero, including all-negative-zero input, returns +0; a negative nonzero mean that rounds below the subnormal range returns -0. RMS follows binary64 arithmetic and can underflow for unrepresentable results. Averaging and mixing do not clip; PCM output clips explicitly. Gain/clip/metrics allocate no memory. Buffer creation/mix/mono either return a complete owner or free internal storage before returning an error. Inputs remain unchanged on allocation failure.

`from_pcm(code,bits)` and `to_pcm(value,bits)` support 8,16,24,32 bits. Codes are signed, including the conceptual signed representation for PCM8. Decode is exactly `code / 2^(bits-1)`, so the negative endpoint is -1 and the positive endpoint is one quantum below +1. WAVE PCM8 adds/subtracts the unsigned bias 128 in the codec. Encoding saturates finite values to the code range, then rounds to nearest with ties to even. All supported integer codes round-trip exactly through binary64. NaN and infinities return `NonFinite`; unsupported widths return `UnsupportedBits`; out-of-range input codes return `Bounds`.

Errors are explicit: `InvalidMetadata`, `Bounds`, `Shape`, `NonFinite`, `Overflow`, `AllocationFailed`, `Limit`, `Empty`, `UnsupportedBits`. Mutators validate before writing; returned owners require explicit destruction. No operation allocates through Rust or Python production code.

The mean uses a fixed superaccumulator, the exact fixed-point approach described in [Neal (2015)](https://www.cs.toronto.edu/~radford/ftp/xsum.pdf), §§2–3 and the discussion of exact means on p. 21. This implementation uses two non-overlapping 34-word unsigned magnitudes with immediate carry propagation, rather than Neal's overlapping signed chunks. Each finite binary64 input is decoded exactly as an integer multiple of 2^-1074. Each magnitude needs at most 2098 value bits plus 31 count bits; 34 × 64 = 2176 bits cover that bound. Subtracting the two magnitudes preserves every cancellation residual.

For rounding `M / count` in these integer units, let `b` be the highest bit of the nonzero exact magnitude and `d = floor(log2(count))`. Starting long division at bit `b` and stopping at `max(0,b-d-53)` retains 53 or 54 quotient bits when the stopping index is positive; stopping at zero may retain fewer bits, including a zero quotient. The division remainder stays below `count`. If 54 bits remain, the lowest quotient bit is the guard; otherwise one further division step obtains the guard. A nonzero remainder or any unconsumed low input bit makes the result sticky. Guard, sticky and quotient parity determine nearest-even rounding, including subnormal ties and a carry into the next exponent. Thus division rounds once from the exact rational mean; it does not first round an overflowing or inexact sum. The arrays occupy 544 bytes of stack storage, with no heap allocation; division examines at most 85 source bits for a signed 32-bit count.

Native evidence lives in `tests/extended_audio_execution.rs`: 638 operation cases with independent exact Fraction and 2500-digit Decimal mean oracles and bit-for-bit result checks, including permutations of `[f64::MAX,1e-300,-f64::MAX]`, mixed exponents, cancellation into subnormals, normal/subnormal half-ULP ties, 8192-value overflowing sums, and signed-zero rules. Other cases cover nonzero borrowed offsets, empty/invalid metadata, overflow atomicity, subnormal/maximum-value RMS, exhaustive PCM16 round-trips and half-step PCM rounding. The companion WAVE tests cover PCM8 exhaustively and seeded PCM24/32 codes.
