#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/http_message.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("http-message", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("http-message: {e}"));
        let exe = common::TempArtifact::new("laniusc_http_message", "exe", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("http-message", command, Duration::from_secs(5))
}
fn input(data: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_http_message", "input", None);
    file.write_bytes(data);
    file
}
fn invoke(args: &[&str], data: &[u8]) -> Output {
    let file = input(data);
    run(Command::new(executable().path())
        .args(args)
        .stdin(std::fs::File::open(file.path()).unwrap()))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(output.stdout.is_empty(), "{output:?}");
    }
}
fn report(output: &Output) -> BTreeMap<&str, usize> {
    checked(output, 0);
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .split_whitespace()
        .map(|item| {
            let (k, v) = item.split_once('=').unwrap();
            (k, v.parse().unwrap())
        })
        .collect()
}
fn request(headers: &[u8], body: &[u8]) -> Vec<u8> {
    [
        b"POST /a?b HTTP/1.1\r\nHost: example.test\r\n".as_slice(),
        headers,
        b"\r\n",
        body,
    ]
    .concat()
}
fn response(status: &str, headers: &[u8], body: &[u8]) -> Vec<u8> {
    [
        format!("HTTP/1.1 {status}\r\n").as_bytes(),
        headers,
        b"\r\n",
        body,
    ]
    .concat()
}
#[test]
fn offline_http_inspector_decodes_binary_pipelines_files_and_no_content_responses() {
    let body: Vec<u8> = (0..=255).collect();
    let wire = request(
        format!("Content-Length: {}\r\n", body.len()).as_bytes(),
        &[body.as_slice(), b"NEXT"].concat(),
    );
    let r = invoke(&[], &wire);
    let r = report(&r);
    assert_eq!(
        (r["body"], r["consumed"], r["remaining"]),
        (256, wire.len() - 4, 4)
    );
    let output = invoke(&["--decode"], &wire);
    checked(&output, 0);
    assert_eq!(output.stdout, body);
    let chunk = request(
        b"Transfer-Encoding: chunked\r\n",
        b"3; a=token; quoted=\"q\\\"x\"\r\na\0b\r\n2\r\n\xffz\r\n00\r\nX-Check: done\r\n\r\nPIPE",
    );
    let output = invoke(&["--decode"], &chunk);
    checked(&output, 0);
    assert_eq!(output.stdout, b"a\0b\xffz");
    let output = invoke(&[], &chunk);
    let r = report(&output);
    assert_eq!((r["trailers"], r["remaining"], r["framing"]), (1, 4, 2));
    for (method, status, headers, kind) in [
        ("HEAD", "200 OK", b"Content-Length: 99\r\n".as_slice(), 0),
        ("GET", "204 No Content", b"".as_slice(), 0),
        (
            "GET",
            "304 Not Modified",
            b"Content-Length: 500\r\n".as_slice(),
            0,
        ),
        ("CONNECT", "200 Connection Established", b"".as_slice(), 4),
        ("GET", "103 Early Hints", b"Link: </x>\r\n".as_slice(), 0),
    ] {
        let wire = response(status, headers, b"NEXT");
        let output = invoke(&["--response", method], &wire);
        let r = report(&output);
        assert_eq!((r["body"], r["remaining"], r["framing"]), (0, 4, kind));
    }
    let ignored_framing = b"HTTP/1.1 200 Tunnel\r\nContent-Length: invalid\r\nTransfer-Encoding: gzip, chunked\r\n\r\n\0tunnel\xff";
    let output = invoke(&["--response", "CONNECT"], ignored_framing);
    let r = report(&output);
    assert_eq!(
        (r["body"], r["remaining"], r["framing"], r["headers"]),
        (0, 8, 4, 2)
    );
    let output = invoke(&["--response", "CONNECT", "--decode"], ignored_framing);
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    let close = b"HTTP/1.0 200 OK\r\n\r\nabc\0\xff";
    checked(&invoke(&["--response", "GET"], close), 2);
    let output = invoke(&["--response", "GET", "--eof", "--decode"], close);
    checked(&output, 0);
    assert_eq!(output.stdout, b"abc\0\xff");
    let file = input(&wire);
    let output = run(Command::new(executable().path())
        .arg("--decode")
        .arg(file.path()));
    checked(&output, 0);
    assert_eq!(output.stdout, body);
    checked(&invoke(&["--validate"], &wire), 0);
    let help = invoke(&["--help"], b"");
    checked(&help, 0);
    assert_eq!(help.stdout,b"Usage: http-message [--response METHOD] [--decode|--validate] [--eof] [--max-input N] [--] [FILE|-]\n");
}
#[test]
fn http_strict_smuggling_boundaries_malformed_chunks_and_every_truncation_are_distinct() {
    let valid = request(
        b"Transfer-Encoding: chunked\r\n",
        b"3;foo=\"a\\b\"\r\nabc\r\n0\r\nX-T: value\r\n\r\n",
    );
    for at in 0..valid.len() {
        let output = invoke(&[], &valid[..at]);
        checked(&output, 2);
        assert!(
            output.stderr.starts_with(b"http-message: incomplete byte="),
            "at={at} {output:?}"
        );
    }
    let cases: Vec<Vec<u8>> = vec![
        b"GET / HTTP/1.1\nHost: x\n\n".to_vec(),
        b"GET / HTTP/1.1\rX".to_vec(),
        b"GET\t/ HTTP/1.1\r\nHost:x\r\n\r\n".to_vec(),
        b"GET / HTTP/1.1\r\n\r\n".to_vec(),
        b"GET / HTTP/1.1\r\nHost:x\r\nhost:x\r\n\r\n".to_vec(),
        b"GET /#f HTTP/1.1\r\nHost:x\r\n\r\n".to_vec(),
        b"GET /%GG HTTP/1.1\r\nHost:x\r\n\r\n".to_vec(),
        request(b"Content-Length: +1\r\n", b"x"),
        request(b"Content-Length: -1\r\n", b"x"),
        request(b"Content-Length: 1, 1\r\n", b"x"),
        request(b"Content-Length: 1\r\ncontent-length: 1\r\n", b"x"),
        request(b"Content-Length : 1\r\n", b"x"),
        request(b" Content-Length: 1\r\n", b"x"),
        request(
            b"Content-Length: 1\r\nTransfer-Encoding: chunked\r\n",
            b"0\r\n\r\n",
        ),
        request(
            b"Transfer-Encoding: chunked\r\ntransfer-encoding: chunked\r\n",
            b"0\r\n\r\n",
        ),
        request(b"Transfer-Encoding: chunked\r\n", b"+1\r\na\r\n0\r\n\r\n"),
        request(b"Transfer-Encoding: chunked\r\n", b"1\r\naX\r\n0\r\n\r\n"),
        request(b"Transfer-Encoding: chunked\r\n", b"0x1\r\na\r\n0\r\n\r\n"),
        request(
            b"Transfer-Encoding: chunked\r\n",
            b"1;a=\"unterminated\r\na\r\n0\r\n\r\n",
        ),
        request(
            b"Transfer-Encoding: chunked\r\n",
            b"0\r\nContent-Length: 3\r\n\r\n",
        ),
        request(
            b"Transfer-Encoding: chunked\r\nConnection: X-Hop\r\n",
            b"0\r\nX-Hop: bad\r\n\r\n",
        ),
    ];
    for wire in cases {
        let output = invoke(&["--decode"], &wire);
        checked(&output, 2);
        assert!(
            output.stderr.starts_with(b"http-message: malformed byte="),
            "wire={wire:?} {output:?}"
        );
    }
    for te in [
        "gzip",
        "gzip, chunked",
        "chunked, gzip",
        "chunked;foo=bar",
        "identity",
    ] {
        let wire = request(
            format!("Transfer-Encoding: {te}\r\n").as_bytes(),
            b"0\r\n\r\n",
        );
        let output = invoke(&[], &wire);
        checked(&output, 2);
        assert!(
            output
                .stderr
                .starts_with(b"http-message: unsupported byte="),
            "{output:?}"
        );
    }
    let output = invoke(
        &[],
        b"GET ftp://example.test/file HTTP/1.1\r\nHost: example.test\r\n\r\n",
    );
    checked(&output, 2);
    assert!(
        output
            .stderr
            .starts_with(b"http-message: unsupported byte="),
        "{output:?}"
    );
    for args in [
        vec!["--bad"],
        vec!["--response"],
        vec!["--decode", "--validate"],
        vec!["--max-input", "-1"],
        vec!["--max-input", "67108865"],
        vec!["-", "-"],
    ] {
        checked(&invoke(&args, &valid), 2);
    }
    checked(&invoke(&["--max-input", "5"], &valid), 2);
    checked(
        &invoke(&["--max-input", &valid.len().to_string()], &valid),
        0,
    );
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|v| format!("{v:02x}")).collect()
}
#[test]
fn http_valid_corpus_matches_h11_framing_and_python_http_client_body_oracles() {
    let mut cases: Vec<(bool, String, bool, Vec<u8>, Vec<u8>)> = Vec::new();
    let mut state = 0x9182_7381_u32;
    for n in 0..24 {
        let size = [0, 1, 2, 15, 16, 255, 256, 1023, 1024, 1025, 4095, 16384][n % 12];
        let body: Vec<u8> = (0..size)
            .map(|_| {
                state ^= state << 13;
                state ^= state >> 17;
                state ^= state << 5;
                state as u8
            })
            .collect();
        let fixed = request(
            format!("X-Case: {n}\r\nContent-Length: {size}\r\n").as_bytes(),
            &[body.as_slice(), b"PIPE"].concat(),
        );
        cases.push((true, "GET".into(), false, fixed, body.clone()));
        let mut chunks = Vec::new();
        for (i, piece) in body.chunks(1 + n * 11).enumerate() {
            chunks.extend_from_slice(
                format!("{:X};id={i}; quoted=\"a\\\"b\"\r\n", piece.len()).as_bytes(),
            );
            chunks.extend_from_slice(piece);
            chunks.extend_from_slice(b"\r\n");
        }
        chunks.extend_from_slice(b"0\r\nX-Sum: opaque\r\n\r\nPIPE");
        cases.push((
            true,
            "GET".into(),
            false,
            request(b"Transfer-Encoding: chunked\r\n", &chunks),
            body.clone(),
        ));
        if n < 12 {
            cases.push((
                false,
                "GET".into(),
                false,
                response(
                    "200 OK",
                    format!("Content-Length: {size}\r\n").as_bytes(),
                    &[body.as_slice(), b"PIPE"].concat(),
                ),
                body.clone(),
            ));
            cases.push((
                false,
                "GET".into(),
                false,
                response("200 OK", b"Transfer-Encoding: chunked\r\n", &chunks),
                body,
            ));
        }
    }
    cases.push((
        false,
        "HEAD".into(),
        false,
        response("200 OK", b"Content-Length: 999\r\n", b"PIPE"),
        vec![],
    ));
    cases.push((
        false,
        "GET".into(),
        true,
        response("200 OK", b"", b"close\0\xff"),
        b"close\0\xff".to_vec(),
    ));
    let corpus = cases
        .iter()
        .map(|(req, method, eof, wire, _)| {
            format!(
                "{} {} {} {}",
                usize::from(*req),
                method,
                usize::from(*eof),
                hex(wire)
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let corpus = input(corpus.as_bytes());
    let script = r#"import sys, h11, io, http.client
class Sock:
 def __init__(self,b): self.b=b
 def makefile(self,*a,**k): return io.BytesIO(self.b)
for line in open(sys.argv[1]):
 req,method,eof,wire=line.split(); req=int(req);eof=int(eof);wire=bytes.fromhex(wire)
 c=h11.Connection(h11.SERVER if req else h11.CLIENT,max_incomplete_event_size=65536)
 if not req:
  c.send(h11.Request(method=method.encode(),target=b'/',headers=[(b'host',b'x')]))
  c.send(h11.EndOfMessage())
 c.receive_data(wire)
 if eof:c.receive_data(b'')
 body=b''
 while True:
  e=c.next_event()
  if isinstance(e,h11.Data):body+=e.data
  if isinstance(e,h11.EndOfMessage):break
  if e is h11.NEED_DATA:raise RuntimeError('incomplete oracle vector')
 consumed=len(wire)-len(c.trailing_data[0])
 if not req:
  r=http.client.HTTPResponse(Sock(wire),method=method);r.begin();assert r.read()==body
 print(consumed,body.hex() or '-')
"#;
    let output = run(Command::new("python3")
        .args(["-c", script])
        .arg(corpus.path()));
    assert!(output.status.success(), "{output:?}");
    let lines: Vec<_> = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .collect();
    assert_eq!(lines.len(), cases.len());
    for ((req, method, eof, wire, expected), oracle) in cases.iter().zip(lines) {
        let (consumed, decoded) = oracle.split_once(' ').unwrap();
        let expected_hex = hex(expected);
        assert_eq!(
            decoded,
            if expected_hex.is_empty() {
                "-"
            } else {
                &expected_hex
            }
        );
        let mut args = Vec::new();
        if !req {
            args.extend(["--response", method.as_str()]);
        }
        if *eof {
            args.push("--eof");
        }
        let output = invoke(&args, wire);
        let r = report(&output);
        assert_eq!(
            r["consumed"],
            consumed.parse::<usize>().unwrap(),
            "{oracle}"
        );
        assert_eq!(r["body"], expected.len());
        args.push("--decode");
        let output = invoke(&args, wire);
        checked(&output, 0);
        assert_eq!(&output.stdout, expected);
    }
    let body = vec![0x80; 524_288];
    let wire = request(
        format!("Content-Length: {}\r\n", body.len()).as_bytes(),
        &body,
    );
    let output = invoke(&["--decode"], &wire);
    checked(&output, 0);
    assert_eq!(output.stdout, body);
}
fn allocations(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let tail = line.rsplit(" = ").next().unwrap();
            if tail.starts_with("0x") {
                assert!(
                    live.insert(tail.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "{events}");
    count
}
#[test]
fn http_offline_cli_stages_output_and_releases_resources_on_io_and_allocation_failures() {
    let wire = request(b"Content-Length: 2500\r\n", &vec![b'x'; 2500]);
    let file = input(&wire);
    let trace = common::TempArtifact::new("laniusc_http_message", "trace", None);
    let execute = |inject: Option<String>, status, file_mode: bool| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"]).arg(trace.path()).args([
            "-e",
            "trace=mmap,munmap,read,write,open,openat,close,socket,connect",
        ]);
        if let Some(inject) = inject {
            c.args(["-e", &inject]);
        }
        c.arg(executable().path()).arg("--decode");
        if file_mode {
            c.arg(file.path());
        } else {
            c.stdin(std::fs::File::open(file.path()).unwrap());
        }
        let output = run(&mut c);
        checked(&output, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("socket(") && !events.contains("connect("));
        let count = allocations(&events);
        (count, output)
    };
    let (count, output) = execute(None, 0, false);
    assert_eq!(output.stdout, vec![b'x'; 2500]);
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
    let bad = input(b"GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nab");
    let output = run(Command::new(executable().path())
        .arg("--decode")
        .arg(bad.path()));
    checked(&output, 2);
}
