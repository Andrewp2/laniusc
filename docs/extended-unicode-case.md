# Unicode string casing

`ext::unicode_case` implements Unicode 17.0.0 full lowercasing,
uppercasing, titlecasing and case folding over counted UTF-8
`core::text::Text`. It allocates no memory. The definitions are
[Unicode 17 chapter 3, section 3.13](https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3/)
and the pinned `SpecialCasing.txt`, `CaseFolding.txt`, `UnicodeData.txt`,
`DerivedCoreProperties.txt` and `PropList.txt` under
`data/unicode/17.0.0`.

```lanius
pub enum Kind { Lower, Upper, Title, Fold }
pub enum Locale { Root, Turkic, Lithuanian }
pub enum Error {
    Bounds, InvalidUtf8(i32), SizeOverflow,
    OutputCapacity(i32), WorkLimit(u64)
}
pub struct Report { bytes: i32, scalars: i32, work: u64 }
pub fn measure(input: core::text::Text, kind: Kind, locale: Locale,
    work_limit: u64) -> core::result::Result<Report, Error>;
pub fn transform_into(input: core::text::Text, kind: Kind, locale: Locale,
    output: core::slice::View<u8>, work_limit: u64)
    -> core::result::Result<Report, Error>;
```

`Root` uses the complete default algorithms, including final sigma and
full expansions such as `ß` → `SS` and `ﬃ` → `FFI`. Contexts always refer
to the immutable original input. The possessive `Case_Ignorable*` in
`Final_Sigma` takes precedence over `Cased` for characters that have both
properties, including U+0345. A sigma preceded only by U+0345 becomes
ordinary sigma; `AΣ` followed only by U+0345 becomes final sigma.

Titlecasing uses the complete default Unicode 17 word boundaries from
[`ext::unicode_words`](extended-unicode-words.md). In each segment,
characters before the first cased character are preserved, that first
character receives its full title mapping, and every remaining character
receives its full lowercase mapping. Thus `CAN'T` becomes `Can't`.
This differs from Python's `str.title()` at apostrophes. All contexts
retain the complete original text across word boundaries.

`Turkic` applies exactly the Turkish and Azerbaijani (`tr` and `az`)
rules in Unicode 17 `SpecialCasing.txt`, including removal of U+0307
after original capital I and the `Not_Before_Dot` condition. `Lithuanian`
applies exactly that file's `lt` rules: `More_Above` inserts a dot when
lowercasing the listed capital I/J forms; `After_Soft_Dotted` removes a
dot when uppercasing; the listed precomposed accented I forms expand.
Combining classes 0 and 230 block the contexts exactly as specified;
other combining classes may intervene. These named locale choices are
data tailorings, without locale discovery, CLDR services or additional
language rules. In default titlecasing, a combining dot following the
first cased character receives its lowercase mapping, as R3 specifies.

Folding uses the full `C` and `F` mappings from `CaseFolding.txt`.
`Turkic` additionally applies the `T` overrides; both `Root` and
`Lithuanian` use default folding. Folding is independent of casing
contexts: Turkic folding of `I` + U+0307 retains the dot after its
mapped dotless I, whereas Turkic lowercasing removes the dot and maps
the I to ordinary i. The operations do not normalize input or output,
remove default ignorables, or implement NFKC case folding.

Both APIs revalidate the selected UTF-8 bytes, including fabricated
`Text` records. `InvalidUtf8` carries the first malformed sequence's
byte offset relative to the selection. Surrogates, overlong sequences,
truncation and values above U+10FFFF are rejected. Embedded NUL,
noncharacters, private use and unassigned scalars are valid and retained
unless they have a specified mapping. `Bounds` checks logical signed
metadata and overflow; callers must supply physical backing for each
selected range. Keep all backing storage alive and keep input and output
disjoint for the entire call. Native arrays and byte slices made from
raw storage both follow their own element strides.

`measure` reports exact output bytes and scalars. It reserves the work
of a successful transform, so a subsequent `transform_into` on the same
input succeeds with exactly `Report.work` when capacity is sufficient.
Each call has an independent budget. `OutputCapacity` carries the exact
required byte count; `SizeOverflow` means a count would exceed i32.
No NUL terminator is appended. Every returned error leaves the entire
output selection unchanged; successful calls preserve its unused suffix
and all surrounding storage. The engine first validates and measures,
then repeats the deterministic transformation to commit bytes.

Work is an explicit algorithmic budget rather than a timer or CPU
instruction count. It charges one unit per validated input scalar,
two per scalar visited by the transformation or a forward casing
context (both passes), and two plus UTF-8 byte width per emitted scalar.
For titlecasing it also reserves six times input byte length before word
segmentation, covering both cursor scans at at most three examinations
per scalar per scan. Fixed table lookup costs and constant bookkeeping
are included in their charged operation. `WorkLimit` reports units
successfully charged before the next operation would exceed the limit;
that operation is not performed. Empty input uses zero work.
Prefix contexts occupy fixed state; forward context intervals do not
overlap, giving linear work in input and output size, plus the fixed
Unicode property lookup cost. No scratch buffer or allocator is needed.

`python3 tools/unicode17/generate_case.py --check` verifies that the
full override and `Soft_Dotted` tables reproduce from the pinned,
hash-checked UCD files. Focused native execution tests cover every
Unicode scalar for root full lower/upper/title and default/Turkic full
folding, all conditional contexts with positive and blocked examples, every
`Soft_Dotted` scalar and a representative of every nonzero combining class,
all 1,944 official word boundary vectors, deterministic generated
contexts, long ignored/combining sequences, exact work thresholds,
UTF-8 and capacity failures, output guards, native/raw strides and
allocation failure injection. An independent Python reference reads
the official data and evaluates contexts directly; host Python casing
provides a second differential oracle over the repertoire whose inputs and official mapped targets are assigned in
that host version. This excludes mappings added in Unicode 17 whose target
was unassigned in the older host, such as U+019B → U+A7DC.
