# Explicit signal dispositions

`std::signal` sets Default or Ignore dispositions for named signals in the
calling Linux x86_64 process. It allocates no memory and installs no callback,
custom handler or signal-return trampoline.

```lanius
import std::signal;
let configured = std::signal::set_disposition(
    std::signal::Signal::BrokenPipe,
    std::signal::Disposition::Ignore);
// Check configured before starting work that depends on this policy.
```

`set_disposition(signal, disposition)` returns
`Result<i32,core::io::Error>`. Success is `Ok(0)`. Kernel errno 4 maps to
Interrupted, errno 11 to WouldBlock and other kernel errors to Host with the
positive errno. An impossible nonzero success status is InvalidCount.

| Signal | Linux x86_64 number |
| --- | --- |
| Hangup | 1 |
| Interrupt | 2 |
| Quit | 3 |
| User1 | 10 |
| User2 | 12 |
| BrokenPipe | 13 |
| Alarm | 14 |
| Terminate | 15 |
| Child | 17 |

## Process and thread contract

Dispositions affect every thread in the calling process. Applications must
coordinate changes with other code that manages signals: setting Default or
Ignore replaces the previous disposition. The function does not change the
calling thread's blocked-signal mask or send a signal. Ignored dispositions are
inherited across exec; custom handler dispositions are reset by exec. These are
Linux process semantics described in [signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html).

Default selects the kernel's normal action for the signal. Ignore suppresses
delivery of that signal. In particular, Ignore for BrokenPipe lets a failed
write to a closed pipe or socket return EPIPE instead of terminating the
process. This lets a command report an I/O error and destroy its owners. The
library changes no process policy until the application calls it.

Explicit Ignore for Child has the kernel's child-reaping semantics; it differs
from leaving Child at its default disposition. Applications that collect child
exit statuses must choose that policy deliberately. See
[sigaction(2)](https://man7.org/linux/man-pages/man2/sigaction.2.html).

This API supports only the listed signals and Default/Ignore. Signal masks,
waiting, delivery, alternate stacks, custom callbacks and handler trampolines
are outside this interface. It does not change the runtime's global signal
policy or the compiler's older signal primitive.

## Native boundary and evidence

The implementation uses `std::linux::call` with x86_64 syscall 13,
`rt_sigaction`. Its stack buffer uses the kernel layout: four 64-bit words for
handler, flags, restorer and signal set; the syscall's signal-set size is 8.
Default and Ignore use handler values 0 and 1, with flags, restorer and mask
zero. The layout is the Linux kernel ABI, rather than libc's public structure.

`tests/stdlib_signal_execution.rs` queries kernel state independently for every
named mapping in both directions. It writes to an actual closed stdout pipe
with BrokenPipe ignored and checks EPIPE, then restores Default in a separate
child and checks SIGPIPE termination. Only test children receive these signals.
Fault injection checks positive errno mapping, interruption, temporary
unavailability and invalid success statuses. Traces check that all cases are
allocation-free.

The real `tcp_exchange` consumer selects BrokenPipe Ignore before allocation
or output. Its closed-stdout integration regression checks status 3 and owner
cleanup after a complete network response.

All three focused signal tests passed. The final literal-pipe checks passed
for both ignored and restored-default dispositions. Logs are in
`target/stdlib-work/signals/`.
