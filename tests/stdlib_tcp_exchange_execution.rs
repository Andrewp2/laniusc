#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{Read, Write},
    net::{Shutdown, TcpListener},
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::{
        Arc,
        OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/tcp_exchange.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("tcp-exchange", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("tcp-exchange: {error}"));
        let file = common::TempArtifact::new("laniusc_tcp_exchange", "exe", None);
        file.write_bytes(bytes);
        std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
fn payload(size: usize) -> Vec<u8> {
    (0..size)
        .map(|i| ((i * 37) ^ (i >> 7) ^ 0xa5) as u8)
        .collect()
}
struct Captured {
    request: Vec<u8>,
    half_closed: bool,
    sent: usize,
}
struct Peer {
    endpoint: String,
    stop: Arc<AtomicBool>,
    task: Option<JoinHandle<Captured>>,
}
fn pause(stop: &AtomicBool, duration: Duration) {
    let start = Instant::now();
    while !stop.load(Ordering::SeqCst) && start.elapsed() < duration {
        thread::sleep(Duration::from_millis(1));
    }
}
impl Peer {
    // This reference peer treats the request as opaque bytes. It sends an
    // independently supplied response only after the client's write half closes.
    fn new(
        ipv6: bool,
        response: Vec<u8>,
        fragment: usize,
        initial: Duration,
        between: Duration,
        hold: bool,
    ) -> Self {
        let listener = TcpListener::bind(if ipv6 { "[::1]:0" } else { "127.0.0.1:0" }).unwrap();
        listener.set_nonblocking(true).unwrap();
        let endpoint = listener.local_addr().unwrap().to_string();
        let stop = Arc::new(AtomicBool::new(false));
        let signal = stop.clone();
        let task = thread::spawn(move || {
            let mut captured = Captured {
                request: vec![],
                half_closed: false,
                sent: 0,
            };
            let start = Instant::now();
            let mut stream = loop {
                if signal.load(Ordering::SeqCst) {
                    return captured;
                }
                assert!(
                    start.elapsed() < Duration::from_secs(10),
                    "peer never accepted a connection"
                );
                match listener.accept() {
                    Ok((stream, _)) => break stream,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(1))
                    }
                    Err(error) => panic!("accept: {error}"),
                }
            };
            stream
                .set_read_timeout(Some(Duration::from_millis(200)))
                .unwrap();
            stream
                .set_write_timeout(Some(Duration::from_millis(200)))
                .unwrap();
            let mut chunk = [0u8; 97];
            loop {
                match stream.read(&mut chunk) {
                    Ok(0) => {
                        captured.half_closed = true;
                        break;
                    }
                    Ok(count) => captured.request.extend_from_slice(&chunk[..count]),
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                        ) && !signal.load(Ordering::SeqCst) =>
                    {
                        continue;
                    }
                    Err(_) => return captured,
                }
            }
            pause(&signal, initial);
            for part in response.chunks(fragment) {
                if signal.load(Ordering::SeqCst) {
                    return captured;
                }
                if stream.write_all(part).is_err() {
                    return captured;
                }
                captured.sent += part.len();
                pause(&signal, between);
            }
            if hold {
                while !signal.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_millis(1));
                }
            }
            let _ = stream.shutdown(Shutdown::Write);
            captured
        });
        Self {
            endpoint,
            stop,
            task: Some(task),
        }
    }
    fn finish(mut self) -> Captured {
        self.stop.store(true, Ordering::SeqCst);
        self.task.take().unwrap().join().unwrap()
    }
}
impl Drop for Peer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
    }
}
struct Trace {
    allocations: usize,
    sockets: usize,
    send_calls: usize,
    receive_calls: usize,
    received_bytes: usize,
    receive_eofs: usize,
}
fn cleanup(events: &str) -> Trace {
    let mut memory = BTreeMap::new();
    let mut descriptors = BTreeSet::new();
    let mut result = Trace {
        allocations: 0,
        sockets: 0,
        send_calls: 0,
        receive_calls: 0,
        received_bytes: 0,
        receive_eofs: 0,
    };
    for line in events.lines() {
        let returned = line
            .rsplit(" = ")
            .next()
            .unwrap()
            .split_whitespace()
            .next()
            .unwrap_or("");
        if let Some(args) = line.strip_prefix("mmap(") {
            if returned.starts_with("0x") {
                let length = args.split(',').nth(1).unwrap().trim();
                assert!(memory.insert(returned, length).is_none(), "{line}");
                result.allocations += 1;
            }
        } else if let Some(args) = line.strip_prefix("munmap(") {
            assert_eq!(returned, "0", "{line}");
            let (address, tail) = args.split_once(',').unwrap();
            assert_eq!(
                memory.remove(address),
                Some(tail.split(')').next().unwrap().trim()),
                "{line}"
            );
        } else if line.starts_with("socket(") {
            if let Ok(fd) = returned.parse::<i32>() {
                if fd >= 0 {
                    assert!(descriptors.insert(fd));
                    result.sockets += 1;
                }
            }
        } else if let Some(args) = line.strip_prefix("close(") {
            let fd = args.split(')').next().unwrap().parse::<i32>().unwrap();
            if descriptors.contains(&fd) {
                assert_eq!(returned, "0", "{line}");
                descriptors.remove(&fd);
            }
        } else if line.starts_with("sendto(") {
            result.send_calls += 1;
        } else if line.starts_with("recvfrom(") {
            result.receive_calls += 1;
            if let Ok(count) = returned.parse::<usize>() {
                result.received_bytes += count;
                result.receive_eofs += usize::from(count == 0);
            }
        }
    }
    assert!(
        memory.is_empty(),
        "leaked allocations: {memory:?}\n{events}"
    );
    assert!(
        descriptors.is_empty(),
        "unclosed socket owners: {descriptors:?}\n{events}"
    );
    result
}
fn invoke(arguments: &[&str], input: &[u8], inject: Option<&str>, full: bool) -> (Output, Trace) {
    invoke_sink(arguments, input, inject, full, false)
}
fn invoke_sink(
    arguments: &[&str],
    input: &[u8],
    inject: Option<&str>,
    full: bool,
    closed: bool,
) -> (Output, Trace) {
    let data = common::TempArtifact::new("laniusc_tcp_exchange", "input", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tcp_exchange", "trace", None);
    let mut command = Command::new("timeout");
    command.args(["--kill-after=1s", "12s", "strace"]);
    command.args(["-qq","-o"]).arg(trace.path()).args(["-e","trace=socket,connect,fcntl,getsockopt,getpeername,shutdown,sendto,recvfrom,poll,clock_gettime,rt_sigaction,read,write,mmap,munmap,close"]);
    if let Some(inject) = inject {
        command.arg("-e").arg(format!("inject={inject}"));
    }
    command
        .arg(executable().path())
        .args(arguments)
        .stdin(std::fs::File::open(data.path()).unwrap());
    if full {
        command.stdout(
            std::fs::OpenOptions::new()
                .write(true)
                .open("/dev/full")
                .unwrap(),
        );
    }
    if closed {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    // Command::output preserves an explicitly configured stdout. The generic
    // pipe-capturing helper would replace /dev/full and the closed pipe.
    let output = command.output().expect("run bounded tcp-exchange");
    assert_ne!(output.status.code(), Some(124), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    if inject.is_some() {
        let marker = if inject.unwrap().contains("delay_enter=") {
            "DELAYED"
        } else {
            "INJECTED"
        };
        assert!(
            events.contains(marker),
            "injection did not execute: {events}"
        );
    }
    let trace = cleanup(&events);
    (output, trace)
}
fn checked(output: &Output, status: i32, expected: &[u8]) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[test]
fn binary_empty_and_large_exchanges_match_independent_ipv4_ipv6_peers() {
    let _ = executable();
    for ipv6 in [false, true] {
        for length in [0, 257, 1048576] {
            let input = payload(length);
            let response: Vec<u8> = input.iter().rev().map(|b| b ^ 0x69).collect();
            let peer = Peer::new(
                ipv6,
                response.clone(),
                137,
                Duration::ZERO,
                Duration::ZERO,
                false,
            );
            let (out, trace) = invoke(&[&peer.endpoint], &input, None, false);
            checked(&out, 0, &response);
            let captured = peer.finish();
            assert!(captured.half_closed);
            assert_eq!(captured.request, input);
            assert_eq!(captured.sent, response.len());
            assert_eq!(trace.sockets, 1);
            if length > 1024 {
                assert!(trace.send_calls > 1 && trace.receive_calls > 1);
            }
        }
    }
}
#[test]
fn successful_receive_and_eof_must_observe_the_original_deadline() {
    let _ = executable();
    for response in [vec![], b"opaque".to_vec()] {
        let peer = Peer::new(
            false,
            response.clone(),
            137,
            Duration::ZERO,
            Duration::ZERO,
            false,
        );
        let (out, _) = invoke(&[&peer.endpoint, "5000"], b"", None, false);
        checked(&out, 0, &response);
        assert!(peer.finish().half_closed);

        let peer = Peer::new(
            false,
            response.clone(),
            137,
            Duration::ZERO,
            Duration::ZERO,
            false,
        );
        let (out, trace) = invoke(
            &[&peer.endpoint, "50"],
            b"",
            Some("recvfrom:delay_enter=200ms:when=1"),
            false,
        );
        checked(&out, 3, b"");
        let captured = peer.finish();
        assert!(captured.half_closed);
        assert_eq!(captured.sent, response.len());
        assert_eq!(trace.receive_calls, 1);
        assert_eq!(trace.received_bytes, response.len());
        assert_eq!(trace.receive_eofs, usize::from(response.is_empty()));
    }
}
#[test]
fn argument_input_response_limits_and_original_network_deadline_are_explicit() {
    let _ = executable();
    for args in [
        vec![],
        vec!["--help", "extra"],
        vec!["localhost:80"],
        vec!["127.0.0.1"],
        vec!["::1:80"],
        vec!["127.0.0.1:65536"],
        vec!["127.0.0.1:1", "-1"],
        vec!["127.0.0.1:1", "60001"],
        vec!["127.0.0.1:1", "1x"],
        vec!["127.0.0.1:1", "1", "16777217"],
        vec!["127.0.0.1:1", "1", "+1"],
        vec!["127.0.0.1:1", "1", "1", "extra"],
    ] {
        let (out, trace) = invoke(&args, b"", None, false);
        checked(&out, 2, b"");
        assert_eq!(trace.sockets, 0);
    }
    let long = "x".repeat(257);
    checked(&invoke(&[&long], b"", None, false).0, 2, b"");
    let help = invoke(&["--help"], b"", None, false);
    checked(
        &help.0,
        0,
        b"Usage: tcp-exchange ADDRESS [TIMEOUT_MS [MAX_BYTES]]\n",
    );
    assert_eq!(help.1.sockets, 0);
    checked(&invoke(&["--help"], b"", None, true).0, 3, b"");
    checked(&invoke_sink(&["--help"], b"", None, false, true).0, 3, b"");
    let (out, trace) = invoke(&["127.0.0.1:1", "5000", "0"], b"x", None, false);
    checked(&out, 2, b"");
    assert_eq!(trace.sockets, 0);
    let (out, trace) = invoke(&["127.0.0.1:1", "5000", "4"], b"12345", None, false);
    checked(&out, 2, b"");
    assert_eq!(trace.sockets, 0);
    let peer = Peer::new(false, vec![], 1, Duration::ZERO, Duration::ZERO, false);
    checked(
        &invoke(&[&peer.endpoint, "5000", "0"], b"", None, false).0,
        0,
        b"",
    );
    assert!(peer.finish().half_closed);
    let peer = Peer::new(
        false,
        b"12345".to_vec(),
        1,
        Duration::ZERO,
        Duration::ZERO,
        false,
    );
    checked(
        &invoke(&[&peer.endpoint, "5000", "4"], b"1234", None, false).0,
        2,
        b"",
    );
    assert_eq!(peer.finish().request, b"1234");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let refused = listener.local_addr().unwrap().to_string();
    drop(listener);
    checked(
        &invoke(&[&refused, "100"], b"request", None, false).0,
        3,
        b"",
    );
    checked(
        &invoke(&[&refused, "60000", "16777216"], b"", None, false).0,
        3,
        b"",
    );
    let peer = Peer::new(
        false,
        b"abc".to_vec(),
        1,
        Duration::ZERO,
        Duration::from_millis(140),
        false,
    );
    checked(
        &invoke(&[&peer.endpoint, "250"], b"opaque", None, false).0,
        3,
        b"",
    );
    let captured = peer.finish();
    assert_eq!(captured.request, b"opaque");
    assert!(captured.half_closed && captured.sent > 0 && captured.sent < 3);
    let peer = Peer::new(false, vec![], 1, Duration::ZERO, Duration::ZERO, true);
    checked(&invoke(&[&peer.endpoint, "0"], b"", None, false).0, 3, b"");
    peer.finish();
}
#[test]
fn allocation_and_host_io_failures_release_every_owner_without_publishing_response() {
    let _ = executable();
    let input = payload(8193);
    let response = payload(8193);
    let peer = Peer::new(
        false,
        response.clone(),
        137,
        Duration::ZERO,
        Duration::ZERO,
        false,
    );
    let (out, baseline) = invoke(&[&peer.endpoint, "5000", "16384"], &input, None, false);
    checked(&out, 0, &response);
    peer.finish();
    assert!(baseline.allocations >= 8);
    for at in 1..=baseline.allocations {
        let peer = Peer::new(
            false,
            response.clone(),
            137,
            Duration::ZERO,
            Duration::ZERO,
            false,
        );
        let inject = format!("mmap:error=ENOMEM:when={at}+");
        checked(
            &invoke(
                &[&peer.endpoint, "5000", "16384"],
                &input,
                Some(&inject),
                false,
            )
            .0,
            4,
            b"",
        );
        peer.finish();
    }
    for inject in [
        "rt_sigaction:error=EPERM:when=1",
        "read:error=EIO:when=1",
        "socket:error=EMFILE:when=1",
        "clock_gettime:error=EIO:when=1",
        "connect:error=ECONNREFUSED:when=1",
        "sendto:error=EPIPE:when=1",
        "sendto:retval=0:when=1",
        "shutdown:error=EIO:when=1",
        "recvfrom:error=EIO:when=1",
        "write:error=EIO:when=1",
        "write:retval=0:when=1",
    ] {
        let peer = Peer::new(
            false,
            response.clone(),
            137,
            Duration::ZERO,
            Duration::ZERO,
            false,
        );
        checked(
            &invoke(
                &[&peer.endpoint, "5000", "16384"],
                &input,
                Some(inject),
                false,
            )
            .0,
            3,
            b"",
        );
        peer.finish();
    }
    for inject in [
        "read:error=EINTR:when=1",
        "sendto:error=EINTR:when=1",
        "sendto:error=EAGAIN:when=1",
        "recvfrom:error=EAGAIN:when=1",
        "write:error=EINTR:when=1",
    ] {
        let peer = Peer::new(
            false,
            response.clone(),
            137,
            Duration::ZERO,
            Duration::ZERO,
            false,
        );
        checked(
            &invoke(
                &[&peer.endpoint, "5000", "16384"],
                &input,
                Some(inject),
                false,
            )
            .0,
            0,
            &response,
        );
        assert_eq!(peer.finish().request, input);
    }
    let peer = Peer::new(
        false,
        response.clone(),
        137,
        Duration::ZERO,
        Duration::ZERO,
        false,
    );
    checked(
        &invoke(&[&peer.endpoint, "5000", "16384"], &input, None, true).0,
        3,
        b"",
    );
    peer.finish();
    let peer = Peer::new(false, response, 137, Duration::ZERO, Duration::ZERO, false);
    checked(
        &invoke_sink(
            &[&peer.endpoint, "5000", "16384"],
            &input,
            None,
            false,
            true,
        )
        .0,
        3,
        b"",
    );
    peer.finish();
}
