#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn compile(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_websocket_wire", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/websocket_wire.lani"))
}
fn run(c: &mut Command) -> Output {
    common::process_output_with_timeout("websocket-wire", c, Duration::from_secs(5))
}
fn input(data: &[u8]) -> common::TempArtifact {
    let f = common::TempArtifact::new("laniusc_websocket_wire", "input", None);
    f.write_bytes(data);
    f
}
fn invoke(args: &[&str], data: &[u8]) -> Output {
    let f = input(data);
    run(Command::new(executable().path())
        .args(args)
        .stdin(std::fs::File::open(f.path()).unwrap()))
}
fn checked(o: &Output, status: i32) {
    assert_eq!(o.status.code(), Some(status), "{o:?}");
    if status == 0 {
        assert!(o.stderr.is_empty(), "{o:?}");
    } else {
        assert!(o.stdout.is_empty(), "{o:?}");
    }
}
fn frame(op: u8, fin: bool, data: &[u8], masked: bool) -> Vec<u8> {
    let mut out = vec![op | if fin { 128 } else { 0 }];
    let mask = if masked { 128 } else { 0 };
    if data.len() < 126 {
        out.push(mask | data.len() as u8);
    } else if data.len() < 65536 {
        out.push(mask | 126);
        out.extend_from_slice(&(data.len() as u16).to_be_bytes());
    } else {
        out.push(mask | 127);
        out.extend_from_slice(&(data.len() as u64).to_be_bytes());
    }
    let key = [17, 34, 51, 68];
    if masked {
        out.extend_from_slice(&key);
    }
    out.extend(
        data.iter()
            .enumerate()
            .map(|(i, &b)| if masked { b ^ key[i % 4] } else { b }),
    );
    out
}
fn request(extra: &[u8]) -> Vec<u8> {
    [b"GET /chat HTTP/1.1\r\nHost: example.test\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n".as_slice(),extra,b"\r\n"].concat()
}
fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect()
}
#[test]
fn websocket_offline_requests_preserve_protocol_and_pipeline_validation() {
    let req=request(b"Sec-WebSocket-Protocol: chat, superchat\r\nSec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n");
    let out = invoke(&["--request"], &req);
    checked(&out, 0);
    assert_eq!(
        out.stdout,
        format!(
            "handshake=1 protocols=2 consumed={} remaining=0\n",
            req.len()
        )
        .as_bytes()
    );
    for extra in [
        b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n".as_slice(),
        b"Sec-WebSocket-Version: 13\r\n",
        b"Sec-WebSocket-Protocol: chat,chat\r\n",
        b"Sec-WebSocket-Extensions: x; p=\"bad value\"\r\n",
    ] {
        checked(&invoke(&["--request"], &request(extra)), 2);
    }
    let mut pipeline = req.clone();
    pipeline.extend(b"FRAME");
    let out = invoke(&["--request"], &pipeline);
    checked(&out, 0);
    assert!(out.stdout.ends_with(b"remaining=5\n"));
}
#[test]
fn websocket_binary_fragmented_messages_and_outgoing_frames_match_python_websockets() {
    let echo = compile("tests/fixtures/extended/websocket_echo_frames.lani");
    let mut corpus = String::new();
    let mut cases = Vec::new();
    let mut seed = 0x1627136fu32;
    for masked in [false, true] {
        for length in [0, 1, 2, 125, 126, 255, 1024, 65535, 65536, 131073] {
            let body: Vec<u8> = (0..length)
                .map(|_| {
                    seed ^= seed << 13;
                    seed ^= seed >> 17;
                    seed ^= seed << 5;
                    seed as u8
                })
                .collect();
            let mut wire = frame(2, true, &body, masked);
            wire.extend(frame(8, true, &[3, 232], masked));
            corpus.push_str(&format!(
                "{} {} {}\n",
                usize::from(masked),
                hex(&wire),
                if body.is_empty() {
                    "-".into()
                } else {
                    hex(&body)
                }
            ));
            cases.push((masked, wire, body, 2));
        }
    }
    for masked in [false, true] {
        let text = "A🙂é\0中𐀀".as_bytes();
        for split in 0..=text.len() {
            let mut wire = frame(1, false, &text[..split], masked);
            wire.extend(frame(9, true, b"ping\0", masked));
            wire.extend(frame(0, true, &text[split..], masked));
            wire.extend(frame(8, true, &[3, 232], masked));
            corpus.push_str(&format!(
                "{} {} {}\n",
                usize::from(masked),
                hex(&wire),
                hex(text)
            ));
            cases.push((masked, wire, text.to_vec(), 1));
        }
    }
    let data = input(corpus.as_bytes());
    let script = r#"import sys,hashlib
from websockets.frames import Frame
for row in open(sys.argv[1]):
 mask,wire,expected=row.split();expected=b'' if expected=='-' else bytes.fromhex(expected);wire=bytes.fromhex(wire);pos=0;message=b'';messages=[];kind=0
 def read(n):
  global pos
  if pos+n>len(wire):raise EOFError()
  result=wire[pos:pos+n];pos+=n
  if False:yield
  return result
 while pos<len(wire):
  parser=Frame.parse(read,mask=bool(int(mask)),max_size=16777216)
  try:next(parser);raise RuntimeError('unexpected suspension')
  except StopIteration as done:frame=done.value
  if frame.opcode in (1,2):kind=int(frame.opcode);message=b''
  if frame.opcode in (0,1,2):
   message+=frame.data
   if frame.fin:
    if kind==1:message.decode('utf-8')
    messages.append((kind,hashlib.sha256(message).hexdigest()))
 assert len(messages)==1 and messages[0][1]==hashlib.sha256(expected).hexdigest()
 print(messages[0][0],messages[0][1])
"#;
    let oracle = run(Command::new("python3")
        .args(["-c", script])
        .arg(data.path()));
    checked(&oracle, 0);
    let rows: Vec<_> = std::str::from_utf8(&oracle.stdout)
        .unwrap()
        .lines()
        .collect();
    assert_eq!(rows.len(), cases.len());
    for ((masked, wire, body, kind), row) in cases.iter().zip(rows) {
        let mut args = vec!["--decode"];
        if !masked {
            args.push("--client");
        }
        let out = invoke(&args, wire);
        checked(&out, 0);
        assert_eq!(&out.stdout, body, "{row}");
        assert!(row.starts_with(&format!("{kind} ")));
        // Echoing coalesces fragments, replies to Ping with Pong, and uses the
        // opposite masking direction. Python validates each emitted frame below.
        let mut payload = vec![if *masked { 0 } else { 1 }];
        payload.extend(wire);
        let out = invoke_fixture(&echo, &payload);
        checked(&out, 0);
        let wire_file = input(&out.stdout);
        let expected_file = input(body);
        let parsed = run(Command::new("python3")
            .args([
                "-c",
                r#"import sys
from websockets.frames import Frame
wire=open(sys.argv[1],'rb').read();expected=open(sys.argv[2],'rb').read();pos=0;messages=[];last=-1
while pos<len(wire):
 def read(n):
  global pos
  if pos+n>len(wire):raise EOFError()
  result=wire[pos:pos+n];pos+=n
  if False:yield
  return result
 parser=Frame.parse(read,mask=bool(int(sys.argv[3])),max_size=16777216)
 try:next(parser);raise RuntimeError('unexpected suspension')
 except StopIteration as done:f=done.value
 if f.opcode in (1,2):messages.append(f.data)
 if f.opcode==10:assert f.data==b'ping\0'
 last=f.opcode
assert messages==[expected] and last==8
"#,
            ])
            .arg(wire_file.path())
            .arg(expected_file.path())
            .arg(if *masked { "0" } else { "1" }));
        checked(&parsed, 0);
    }
}
fn invoke_fixture(exe: &common::TempArtifact, data: &[u8]) -> Output {
    let file = input(data);
    run(Command::new(exe.path()).stdin(std::fs::File::open(file.path()).unwrap()))
}
#[test]
fn websocket_malformed_partial_close_utf8_and_work_limits_produce_no_output() {
    let mut valid = frame(1, true, b"Hello", true);
    valid.extend(frame(8, true, b"", true));
    for at in 0..valid.len() {
        checked(&invoke(&["--decode"], &valid[..at]), 2);
    }
    let partial = frame(1, false, b"A", false);
    checked(&invoke(&["--client"], &partial), 2);
    checked(&invoke(&["--client", "--allow-open"], &partial), 0);
    let mut bad = vec![
        vec![193, 0],
        vec![131, 0],
        vec![129, 128, 0, 0, 0, 0],
        vec![9, 0],
        vec![137, 126, 0, 126],
        vec![130, 126, 0, 125],
        vec![130, 127, 0, 0, 0, 0, 0, 0, 255, 255],
        vec![130, 127, 128, 0, 0, 0, 0, 0, 0, 0],
        vec![130, 127, 0, 0, 0, 0, 128, 0, 0, 0],
        frame(0, true, b"a", false),
        [frame(1, false, b"a", false), frame(2, true, b"b", false)].concat(),
    ];
    for data in [
        &[192, 175][..],
        &[237, 160, 128],
        &[244, 144, 128, 128],
        &[240, 159],
    ] {
        bad.push(frame(1, true, data, false));
    }
    for code in [
        0u16, 999, 1004, 1005, 1006, 1015, 1016, 2000, 2999, 5000, 65535,
    ] {
        bad.push(frame(8, true, &code.to_be_bytes(), false));
    }
    bad.push(frame(8, true, &[3], false));
    bad.push(frame(8, true, &[3, 232, 255], false));
    for wire in bad {
        checked(&invoke(&["--client", "--allow-open", "--decode"], &wire), 2);
    }
    for code in [
        1000u16, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 3000, 3999,
        4000, 4999,
    ] {
        let wire = frame(8, true, &code.to_be_bytes(), false);
        checked(&invoke(&["--client"], &wire), 0);
    }
    let mut many = frame(2, false, b"", false);
    for _ in 0..65536 {
        many.extend(frame(0, false, b"", false));
    }
    checked(&invoke(&["--client", "--allow-open"], &many), 2);
    checked(&invoke(&["--max-input", "1"], &valid), 2);
    checked(&invoke(&["--max-output", "4", "--decode"], &valid), 2);
    let out = invoke(&["--max-output", "5", "--decode"], &valid);
    checked(&out, 0);
    assert_eq!(out.stdout, b"Hello");
}
fn freed(events: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut count = 0;
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(
                        result.split_whitespace().next().unwrap(),
                        args.split(',').nth(1).unwrap().trim()
                    )
                    .is_none(),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (address, tail) = args.split_once(',').unwrap();
            assert!(line.ends_with(" = 0"));
            assert_eq!(
                live.remove(address),
                Some(tail.split(')').next().unwrap().trim()),
                "{line}"
            );
        }
    }
    assert!(live.is_empty(), "{live:?}\n{events}");
    count
}
#[test]
fn websocket_cli_allocation_and_io_failures_release_owners_and_stage_output() {
    let mut wire = frame(2, true, &vec![255; 2500], true);
    wire.extend(frame(8, true, b"", true));
    let data = input(&wire);
    let trace = common::TempArtifact::new("laniusc_websocket_wire", "trace", None);
    let execute = |fault: Option<String>, code, file_mode: bool| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"]).arg(trace.path()).args([
            "-e",
            "trace=mmap,munmap,read,write,open,openat,close,socket,connect",
        ]);
        if let Some(ref fault) = fault {
            c.args(["-e", fault]);
        }
        c.arg(executable().path()).arg("--decode");
        if file_mode {
            c.arg(data.path());
        } else {
            c.stdin(std::fs::File::open(data.path()).unwrap());
        }
        let out = run(&mut c);
        checked(&out, code);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        assert!(!events.contains("socket(") && !events.contains("connect("));
        (freed(&events), out)
    };
    let (count, out) = execute(None, 0, false);
    assert_eq!(out.stdout, vec![255; 2500]);
    for at in 1..=count {
        execute(
            Some(format!("inject=mmap:error=ENOMEM:when={at}")),
            4,
            false,
        );
    }
    execute(Some("inject=read:error=EIO:when=1".into()), 3, false);
    execute(Some("inject=read:error=EINTR:when=1".into()), 0, false);
    execute(Some("inject=write:error=EIO:when=1".into()), 3, false);
    execute(Some("inject=open:error=EACCES:when=1".into()), 3, true);
    execute(Some("inject=close:error=EIO:when=1".into()), 3, true);
}
