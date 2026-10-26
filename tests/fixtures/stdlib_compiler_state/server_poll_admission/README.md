# Public server generic admission

This is a focused admission control of the actual `ext::http_server` Protocol
and `ext::server_poll` public generic interfaces. The actual public-module
control now compiles and executes on Linux x86_64. No local replacement
traits or protocol implementation establishes that admission.

The finite control in `main.lani`:

- Import the real public modules, explicitly instantiate Driver/Factory/Handler
  dispatch and use the actual Event/Decision/Reply/Report types.
- Feed a canonical request into the real Protocol, inspect its retained head,
  and stage a handler-local response synchronously through Reply.stage while
  all field/body backing is alive. Overwrite scratch afterward and inspect
  the real staged output to detect an escaped view.
- Exercise a scalar error profile and nested owned transport/application
  errors, including Option/Result layers and independent Vec owners.
- Transfer one error through Report.take, check repeat take is disarmed,
  destroy the remaining Report twice and release the taken error separately.
  A counted destruction ledger checks exactly-once owner release.

`admission/probe.lani` implements the actual public Driver/Factory/Handler
traits with explicit generic types. Four real loopback pairs provide valid
connected socket owners for constructor consumption and cleanup. HTTP bytes
are fed directly to the real Protocol; output reservations are inspected
without pretending they were written to the peer. These test-only drivers
are not production network implementations. `None` transport telemetry remains
unavailable rather than a fabricated TLS-call count. The report separately
checks a synthetic full-width optional counter value. Factory.failure_stats
also returns synthetic zero Stats for method-dispatch admission; it does not
model the Protocol constructor's reserved work. This factory is never passed
to an actual Server and does not establish production accounting or liveness.

Compile the entry with `--stdlib-root stdlib --source-root extended` and this
directory as another `--source-root`; choose the output in the root's scratch
directory. It uses the ordinary syscall/native executable profile, with no
OpenSSL link or helper object required. The root must classify the resulting
ELF and execute it before recording acceptance. Expected successful output
is empty stdout/stderr and exit zero.

## Accepted finite control

The root's first compile returned zero with empty output:
`target/stdlib-work/server-poll-public-admission-first.log`. The emitted file
was classified as ELF64, little endian, x86_64 and passed executable ELF
validation. Its native run returned zero with empty stdout/stderr in less
than two seconds:
`target/stdlib-work/server-poll-public-admission-native-first.log`.

This accepts the actual imported generic interfaces, real Protocol
head/request decisions and synchronous reply staging, plus scalar/nested
error dispatch and Report ownership exercised by this control. The nested
ledger observes five error owners, three released by report destruction and
two retained in the taken application outcome until its separate release.
It does not execute the generic Server, verify scheduler fairness/accounting,
send HTTP over those loopback sockets or exercise TLS. Direct and connected
server acceptance require separate executable gates.

The root runs compilation/execution under its existing serialized queue, with
each command below two minutes. This control is about generic admission,
staging and manual ownership; it does not establish concurrent scheduling,
socket/TLS transfer, cryptography or the server increment's completion.
If the compiler rejects a source shape, preserve the exact failing source and
diagnostic beside a candidate reduction/control before changing the fixture.
