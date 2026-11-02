# Text tools: sort, uniq, cut, tr, wc, head, tail, cat, tee, paste, join and comm

`ext::text_sort`, `ext::text_uniq`, `ext::text_cut`, `ext::text_tr`,
`ext::text_wc` and `ext::text_head` reimplement the GNU coreutils programs of
the same names under `LC_ALL=C`. The sample programs `text-sort`,
`text-uniq`, `text-cut`, `text-tr`, `text-wc` and `text-head`
(`sample_programs/library/text_*.lani`) parse GNU's command lines and write
GNU's output byte for byte. `ext::text_lines` holds the byte machinery they
share.

Each is checked against GNU coreutils 9.4 by one generated oracle per tool
(`tests/fixtures/extended/TOOL_oracle.py`). Each oracle compares stdout, or
the output file, and the exit status. Error message wording is not
compared.

## Shared machinery: `ext::text_lines`

- `words(view)` gives a view of packed bytes as little-endian u64 words
  (`Words`), with a zero-padded tail word. The tools read and compare eight
  bytes at a time through it.
- `line_starts` and `byte_positions(w, a, b)` find every LF, or either of two
  bytes, eight bytes at a time with SWAR masks.
- `Out` is a word-at-a-time writer. It either streams to a descriptor or
  grows in memory. `put`, `put_byte`, `put_span` (any byte range of a
  `Words`, shifted into place a word at a time), `put_number` and `finish`
  write to it.
- `Lines` and `next_lines(r, eol, whole)` read a descriptor in chunks of
  whole lines. The buffer doubles when a line is longer than it.
- `open_input`, `open_output` (`-` is standard input or output), `read_all`
  and `write_all` wrap the descriptors.

## sort

`text-sort [-bfnrsuz] [-t SEP] [-k POS1[,POS2]]... [-o FILE] [FILE...]`

Supported:

- Keys: `-k` with field and character positions and the `b`, `f`, `n` and
  `r` modifiers. GNU's rules for inheriting the global options apply: a key
  with no ordering options of its own takes them all.
- Separators: `-t` (one byte, or `\0` for NUL), or runs of blanks.
- Orders: `-n` (GNU's `numcompare`), `-f`, `-r`, `-b`.
- `-s`, and `-u` (the first line of each run of equal lines is kept).
- `-z`, `-o` (the output may be one of the inputs), several input files.
- Long options, abbreviated as `getopt_long` allows.
- `-S`, `-T` and `--parallel` are accepted and ignored.

GNU's last-resort comparison of whole lines is applied unless `-s` or `-u` is
given.

Not supported: ordering options `d`, `g`, `h`, `i`, `M`, `R` and `V`, and
`-c`, `-m` and `--files0-from`. These exit 2. Errors also exit 2.

Under `LC_ALL=C`, GNU marks "no thousands separator" with `CHAR_MAX + 1`.
Read as an unsigned char that value is byte 0x80, so GNU treats 0x80 as a
thousands separator in `-n` keys. It is skipped among the leading zeros
(after a `-` too) and after each integer digit. For example, `1<0x80>5`
sorts as 15. `text-sort` does the same.

The sort is a stable multikey MSD radix sort:

- Each line has one u64 per comparison level (a key, then the whole line).
  The u64 packs the next 5 to 7 key bytes (big endian), how many of them the
  key still has, and the line's position in its run. The values are
  therefore distinct, and equal keys keep their input order.
- The values are radix sorted from their highest differing bit, with up to
  11 bits per pass. Each run of equal keys continues with the next bytes, or
  with the next level.
- Runs of at most twelve lines are insertion sorted by direct comparison.
- Input already in order under whole-line keys (bytes or `-f`, with or
  without `-r`, strictly in order with `-u`) is written as it is. The
  check stops at the first line that is out of order.
- Field bounds are found with one SWAR walk per line.
- A numeric key becomes one u64 that orders numbers exactly while they have
  at most 13 significant digits. Longer numbers fall back to `numcompare`.
- All work arrays are indexed by position, so a pass over a run reads them
  in order.
- At most 250,000,000 lines.

From 50,000 lines up, and when the output is a descriptor, the sort runs in
up to eight forked worker processes. The count is the number of CPUs the
process may use, capped at 8, as GNU caps its threads. Every array lives in
one shared anonymous mapping, made with `mmap` through `std::linux`, so no
native link is needed. The parent runs as worker 0. The steps are:

1. The workers compute key bounds and values for equal slices of the
   lines.
2. The parent makes one 11-bit radix pass, and each worker sorts and
   gathers a slice of whole buckets.
3. While one run of equal keys covers every line, steps 1 and 2 repeat on
   the next bytes or level.
4. Each worker finishes a slice of whole runs and writes its lines into a
   shared buffer. The parent writes the buffers in order.

The output is the same as the single-process sort.

## uniq

`text-uniq [-c] [-d] [-u] [-i] [-f N] [-s N] [-w N] [-z] [-N] [+N] [INPUT [OUTPUT]]`

- Follows GNU's rules for the order of options and operands: obsolete `-N`
  and `+N`, numbers parsed as `xstrtoumax` does, and `"%7lu "` counts.
- Fields are separated by blanks or LF, as in GNU.
- `-D` and `--group` are not supported.
- Lines are compared a word at a time. Neighbouring output lines are written
  as one span.

## cut

`text-cut -b LIST | -c LIST | -f LIST [-d DELIM] [-s] [--complement] [--output-delimiter=S] [-n] [-z] [FILE...]`

- The LIST is parsed, sorted, merged and complemented as GNU's
  `set_fields` does. `-c` means bytes, as in GNU.
- If the delimiter is the line end, the input is one record, as in GNU.
- `--output-delimiter=''` writes a NUL, as GNU does.
- Fields are found with one fused word scan per line. Neighbouring selected
  fields leave as one span when the output delimiter is the input delimiter.

## tr

`text-tr [-cdst] SET1 [SET2]`

- Sets use GNU's syntax: escapes, ranges, `[:class:]`, `[=c=]` and
  `[c*n]`. GNU's validation errors apply.
- Options stop at the first operand, as in GNU's `tr`.
- Translation runs eight bytes at a time when the changed bytes form at most
  four ASCII runs with one offset each, two words at a time where possible.
  Other sets use a table.
- `-d` and `-s` remove bytes eight at a time. A word's dropped lanes are
  gathered into a byte by one multiply, which indexes a 256-entry table of
  the three masks that close the gaps. When deleting alone, the kept bytes
  are tested instead if they form fewer runs (as with `-c`).

## wc

`text-wc [-clmwL] [FILE...]`

- Counts lines, words, bytes, characters (bytes under `LC_ALL=C`) and the
  longest line's display width, with GNU's column widths.
- Lines and words are counted eight bytes at a time.

## Shared command-line pieces: `ext::text_args` and `ext::text_source`

- `ext::text_args::count(view)` parses a count as GNU's `xstrtoumax` with
  the suffixes `bkKmMGTPEZYRQ0` does: leading blanks, an optional `+`, a
  bare suffix meaning 1, `kB`/`KB`/`kD` for powers of 1000 and `KiB` for
  1024. Its status is 0 (parsed), 1 (not a number) or 2 (past 64 bits).
  `lit`, `same`, `at`, `tail`, `say`, `emit` and `complain` are the small
  view and message helpers the sample programs share.
- `ext::text_source::Source` is a whole input held in memory with its line
  ends found up front: line i is bytes `[start(i), stop(i))` and
  `ended(i)` says whether an end byte follows it. `load(name, eol)` opens
  and reads a named input (`-` is standard input).
- `ext::text_lines::stat(fd)` and `seek(fd, offset, whence)` give the file
  kind, size, block size and `lseek`, for the tools that work on regular
  files in place.

## head

`text-head [-c [-]NUM] [-n [-]NUM] [-q] [-v] [-z] [FILE...]`, and GNU's
obsolete first argument `-NUM[bcklmqvz]`.

- Counts use GNU's suffixes. A leading `-` copies all but the last NUM
  lines or bytes. An elided byte count past 2^63 - 1 is an error, as in
  GNU.
- `==> NAME <==` headers appear when there are several operands (or with
  `-v`), with a blank line before every header but the first. A file that
  cannot be opened gets no header.
- The first NUM lines are found by counting end bytes eight at a time in
  256 KiB chunks. Only the chunk holding the last wanted line is scanned
  for its position.
- GNU leaves a regular file's offset just past what it printed, so a
  second `-` operand on the same standard input carries on from there.
  text-head does the same: it seeks back over the unused part of the last
  chunk.
- For a regular file larger than its block size, `-c -NUM` copies up to
  the file's size less NUM. `-n -NUM` reads back from the end in 8 KiB
  blocks aligned as GNU aligns them. It counts the end bytes in each block
  and copies up to the line it finds. The file offset afterwards matches
  GNU's, including when the file has too few lines. Other inputs, such as
  pipes, are read to the end and held in memory.

## Oracles

| Tool | Oracle | Cases | Failures |
|---|---|---|---|
| wc | `wc_oracle.py` | 2,000 | 0 |
| tr | `tr_oracle.py` | 2,000 | 0 |
| cut | `cut_oracle.py` | 2,000 | 0 |
| uniq | `uniq_oracle.py` | 2,000 | 0 |
| sort | `sort_oracle.py` | 2,000 | 0 |
| head | `head_oracle.py` | 2,000 | 0 |

The sort oracle also passed 2,000 cases under each of two other seeds (7
and 8). Every 25th sort case has 20,000 to 120,000 lines, so the forked
workers are checked as well.

`tests/extended_textutils_execution.rs` builds each sample program and runs
its oracle over fewer cases (600 each, 400 for sort).

## Speed on 100 MB

`big100.txt` is `big.txt` repeated to 100,000,000 bytes (2,851,521 lines,
the last one cut short). It was read from a file on standard input with
output to `/dev/null`, under `LC_ALL=C`, against GNU coreutils 9.4: best of
five runs, alternating with GNU, on the same shared laptop.

| Command | Wall (ms) | GNU wall (ms) | Wall ratio | CPU (ms) | GNU CPU (ms) | CPU ratio |
|---|---|---|---|---|---|---|
| `text-head -n 2000000` | 66 | 84 | 0.79 | 64 | 77 | 0.83 |
| `text-head -c 90000000` | 15 | 44 | 0.35 | 15 | 43 | 0.34 |
| `text-head -n -1000` | 20 | 53 | 0.37 | 18 | 49 | 0.38 |
| `text-head -c -1000` | 22 | 76 | 0.28 | 20 | 49 | 0.40 |
| `text-head -n -1000000` | 66 | 55 | 1.20 | 54 | 50 | 1.07 |

## Speed

Each command ran on `big.txt` (42 MB, 1,200,000 generated lines of three
tab-separated fields: a word with digits, a signed integer and a decimal
followed by words) or on `sorted.txt` (the same lines in order). Input came
from a file on standard input and output went to `/dev/null`, under
`LC_ALL=C`, against GNU coreutils 9.4. Each figure is the best of five runs
(three for sort), alternating with GNU. The machine is a shared 16-CPU
laptop that other jobs kept busy, so wall times vary by about 20%. CPU time
is user plus system time, summed over sort's workers and GNU's threads.

| Command | Input | Wall (ms) | GNU wall (ms) | Wall ratio | CPU (ms) | GNU CPU (ms) | CPU ratio |
|---|---|---|---|---|---|---|---|
| `text-sort` | big.txt | 330 | 279 | 1.18 | 1190 | 867 | 1.37 |
| `text-sort -r` | big.txt | 382 | 319 | 1.20 | 1291 | 979 | 1.32 |
| `text-sort -n` | big.txt | 353 | 390 | 0.90 | 1304 | 1360 | 0.96 |
| `text-sort -u` | big.txt | 295 | 283 | 1.04 | 1025 | 763 | 1.34 |
| `text-sort -f` | big.txt | 309 | 339 | 0.91 | 1117 | 1016 | 1.10 |
| `text-sort -s -k3,3` | big.txt | 316 | 404 | 0.78 | 1247 | 1206 | 1.03 |
| `text-sort -k2,2n` | big.txt | 570 | 589 | 0.97 | 1911 | 1876 | 1.02 |
| `text-sort -t. -k2` | big.txt | 1000 | 1068 | 0.94 | 2285 | 1971 | 1.16 |
| `text-sort -k1,1 -k2,2nr` | big.txt | 1020 | 1503 | 0.68 | 2389 | 1982 | 1.21 |
| `text-sort` | sorted.txt | 358 | 314 | 1.14 | 345 | 401 | 0.86 |
| `text-uniq` | sorted.txt | 120 | 77 | 1.56 | 120 | 76 | 1.57 |
| `text-uniq -c` | sorted.txt | 191 | 142 | 1.34 | 191 | 142 | 1.35 |
| `text-uniq -d` | sorted.txt | 89 | 65 | 1.37 | 88 | 64 | 1.38 |
| `text-uniq -u` | sorted.txt | 124 | 77 | 1.61 | 123 | 76 | 1.61 |
| `text-uniq -f1` | sorted.txt | 181 | 90 | 2.01 | 180 | 89 | 2.02 |
| `text-uniq -i` | sorted.txt | 123 | 78 | 1.58 | 122 | 77 | 1.58 |
| `text-uniq -ic` | sorted.txt | 194 | 147 | 1.32 | 193 | 146 | 1.32 |
| `text-uniq -w5 -c` | sorted.txt | 116 | 65 | 1.78 | 115 | 64 | 1.79 |
| `text-cut -f2` | big.txt | 135 | 76 | 1.77 | 134 | 75 | 1.78 |
| `text-cut -d' ' -f1,3` | big.txt | 183 | 110 | 1.66 | 182 | 109 | 1.67 |
| `text-cut -b1-10` | big.txt | 102 | 69 | 1.48 | 101 | 68 | 1.49 |
| `text-cut -c5-` | big.txt | 131 | 96 | 1.35 | 130 | 96 | 1.36 |
| `text-cut --complement -f2` | big.txt | 194 | 103 | 1.87 | 193 | 103 | 1.88 |
| `text-cut -f1,3 --output-delimiter=:` | big.txt | 195 | 100 | 1.95 | 195 | 100 | 1.95 |
| `text-tr a-z A-Z` | big.txt | 39 | 32 | 1.21 | 38 | 31 | 1.22 |
| `text-tr -d 0-9` | big.txt | 181 | 94 | 1.92 | 179 | 92 | 1.95 |
| `text-tr -s ' '` | big.txt | 98 | 79 | 1.25 | 98 | 78 | 1.25 |
| `text-tr -cd 'a-z\n'` | big.txt | 203 | 105 | 1.92 | 190 | 99 | 1.93 |
| `text-tr '\t' ,` | big.txt | 52 | 44 | 1.19 | 51 | 41 | 1.24 |
| `text-wc` | big.txt | 91 | 633 | 0.14 | 91 | 632 | 0.14 |
| `text-wc -l` | big.txt | 31 | 14 | 2.22 | 29 | 13 | 2.26 |
| `text-wc -w` | big.txt | 96 | 816 | 0.12 | 96 | 815 | 0.12 |
| `text-wc -L` | big.txt | 570 | 564 | 1.01 | 570 | 563 | 1.01 |
| `text-wc -m` | big.txt | 1 | 2 | 0.78 | 1 | 1 | 0.74 |

The two `tr -d` rows were measured later, at a higher load, after the
gap-closing masks moved into a table. Two modes are over 2x GNU's wall
time:

- `wc -l` (31 ms against 14 ms). GNU counts LFs with AVX2. Here each
  word load spends most of its instructions on the slice header and the
  bounds check, so the count waits on the x86 backend keeping slice
  headers in registers.
- `uniq -f1`, at 2.0 to 2.3. The field skip adds about 50 ns a line,
  most of it the same per-access cost.

Every other mode is within 2x. `text-wc` and `text-wc -w` count words
eight bytes at a time and are about seven times as fast as GNU. On
`sorted.txt`, `text-sort` writes the input as it is after one comparison
pass, and GNU's merge sort is also fast on input that is already in order.
