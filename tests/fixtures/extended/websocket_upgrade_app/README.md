# Offline WebSocket upgrade application tests

`oracle.py MODE EXECUTABLE` exercises
`sample_programs/library/websocket_upgrade.lani` through stdin, stdout, stderr
and exit status. It never opens a network connection. The four modes are:

| Mode | Cases | Contract |
| --- | ---: | --- |
| `functional` | 22 | RFC sample, eight fresh nonce keys, header case/whitespace, exact subprotocol selection, declined extensions and boundary inputs |
| `rejection` | 30 | Malformed/incomplete requests, invalid keys, unoffered/case-mismatched protocols, trailing bytes and exceeded limits produce no stdout |
| `cli` | 15 | Help, option spellings, duplicate/missing/empty values, operands and argument caps |
| `io` | 4 | Real closed stdout readers, directory stdin and a failed stderr reader preserve typed exit status |

The functional oracle uses `http.client.HTTPResponse` for parsing and Python's
established `hashlib`/`base64` operations for the expected accept field. It
checks single required response fields, the exact selected token, no framing
headers, no extensions and no response body or trailing frame bytes. The RFC
sample's accept value is `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`. The eight other nonce
values come from the host random source; each input and result is saved in a
temporary evidence directory printed after success.

The oracle contains no application or library implementation. It does not
trace allocations, certify owner cleanup, inject every allocation failure or
establish connected WebSocket transport behavior.

## Verification status

The application compiled and all four direct native groups passed on Linux
x86_64 with OpenSSL 3. The accepted source SHA-256 is
`176e8b97cef65cde48c19afbb4681a8dad9f1ccd0d31e88fe866b72339700865`.
The compile log `target/stdlib-work/websocket-upgrade-app-compile-first.log`
is empty and the compiler exited zero.
The linked executable SHA-256 is
`83a760bf495d4d587c3255331ae910bb44655488903c8382f8019fb802c46a37`.

| Direct native receipt in `target/stdlib-work/` | Cases | Retained evidence |
| --- | ---: | --- |
| `websocket-upgrade-app-functional-first.log` | 22 | `/tmp/websocket-upgrade-functional-u4qgsyzv` |
| `websocket-upgrade-app-rejection-first.log` | 30 | `/tmp/websocket-upgrade-rejection-a5j9bd62` |
| `websocket-upgrade-app-cli-first.log` | 15 | `/tmp/websocket-upgrade-cli-y0kbs1_b` |
| `websocket-upgrade-app-io-first.log` | 4 | `/tmp/websocket-upgrade-io-w8a3hyg6` |

Each group passed on its first run. These are finite functional receipts,
including real OpenSSL acceptance and actual closed-reader failures; they do
not establish arbitrary memory safety or leak freedom. The Rust integration
driver built successfully with `--no-run` in 2.09 seconds; its build receipt
is `target/stdlib-work/websocket-upgrade-driver-build-first.log`. Rust libtest
runtime execution was not run; these direct runs are not Rust test passes.

CPU fixture controls also passed: syntax and literal lengths, case
construction, valid boundary padding and response-oracle signal. The oracle
accepted the RFC response and rejected a changed digest, wrong status, wrong
Upgrade value and trailing output.

The parent agent ran compiler/native commands under the shared library lock
and a timeout below two minutes. The focused commands are:

```sh
python3 -B tests/fixtures/extended/websocket_upgrade_app/oracle.py functional target/stdlib-work/websocket-upgrade.elf
python3 -B tests/fixtures/extended/websocket_upgrade_app/oracle.py rejection target/stdlib-work/websocket-upgrade.elf
python3 -B tests/fixtures/extended/websocket_upgrade_app/oracle.py cli target/stdlib-work/websocket-upgrade.elf
python3 -B tests/fixtures/extended/websocket_upgrade_app/oracle.py io target/stdlib-work/websocket-upgrade.elf
```

The integration target is `extended_websocket_upgrade_app_execution`.
