# Offline HTTP message inspector

`sample_programs/library/http_message.lani` is a complete offline program using [`ext::http`](extended-http.md). It reads binary HTTP/1 bytes from stdin or one file, validates the first message, reports its boundary, or writes its decoded body. It does not implement a network client/server.

```sh
laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/http_message.lani -o http-message
./http-message capture.http
./http-message --decode request.http > body.bin
./http-message --response GET --eof response.http
cat request.http | ./http-message --validate
```

Usage: `http-message [--response METHOD] [--decode|--validate] [--eof] [--max-input N] [--] [FILE|-]`

With no file or with `-`, input comes from stdin. `--response METHOD` selects response parsing and supplies the original case-sensitive request method. Default parsing is a request. `--eof` explicitly permits a response whose body is delimited by closure to consume all remaining input; fixed/chunked truncation still fails. The whole input file is read first; this switch expresses how to interpret its end.

The default report is one deterministic ASCII line, for example:

```text
version=11 status=0 headers=1 framing=0 body=0 trailers=0 consumed=27 remaining=0
```

Version is 10/11 for HTTP/1.0/1.1; request status is zero. Framing codes are 0 empty, 1 fixed, 2 chunked, 3 close, and 4 successful CONNECT tunnel. `body` is decoded bytes, `trailers` counts separate trailer fields, and `consumed`/`remaining` show the exact message boundary and trailing input. `--decode` writes arbitrary decoded body bytes without a newline or text conversion. `--validate` writes no stdout on success. Only the first message is inspected: trailing bytes are reported and preserved, including pipelined requests or tunnel data.

The entire result is staged before stdout. Invalid/incomplete/unsupported messages write no stdout and produce `http-message: REASON byte=OFFSET` on stderr. Reasons are `incomplete`, `malformed`, `limit`, `unsupported`, and `invalid-state`. Offset semantics and the supported strict wire profile are documented with the library. Argument and input-I/O failures use the exit status and do not promise a diagnostic.

Exit status 0 means success/help, 2 means arguments, syntax, incomplete input or limits, 3 means input/output/open/close failure, and 4 means allocation failure. A failed stdout write can expose a prefix already accepted by the operating system. Interrupted reads are retried; other I/O failures release all owners. Opened files are explicitly closed on success and failure; stdin/stdout remain borrowed descriptors.

Default maximum input is 18,874,368 bytes. `--max-input N` accepts 0–67,108,864 and rejects input exceeding the cap before processing/output. Parser limits remain independently bounded (16 MiB decoded body by default, 64 KiB heads, 8 KiB lines, bounded header/trailer/chunk counts). Arguments are bounded to 32 and 65,536 total bytes. All input, decoded output and argument owners are destroyed on every exit path. File paths support non-UTF-8 bytes and are copied into packed storage before the filesystem ABI call.

Focused executable tests are in `tests/extended_http_message_execution.rs`; their independent Python parsers are test-only. Production parsing and decoding are entirely Lanius.
