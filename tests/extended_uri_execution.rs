#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsStr,
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output},
};
fn executable(path: &str) -> common::TempArtifact {
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
    let exe = common::TempArtifact::new("laniusc_uri", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("uri", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn numbers(bytes: &[u8]) -> Vec<i32> {
    std::str::from_utf8(bytes)
        .unwrap()
        .split_whitespace()
        .map(|s| s.parse().unwrap())
        .collect()
}
#[test]
fn borrowed_uri_contracts_execute_bounds_limits_components_and_aliases() {
    let exe = executable("tests/fixtures/extended/uri_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_uri", "contracts", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,open,openat,socket,connect"])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

fn invoke(exe: &common::TempArtifact, inputs: &[Vec<u8>]) -> Vec<Vec<i32>> {
    let output = common::process_output_with_timeout(
        "URI model batch",
        Command::new(exe.path()).args(inputs.iter().map(|s| OsStr::from_bytes(s))),
        std::time::Duration::from_secs(10),
    );
    checked(&output, 0);
    let rows: Vec<_> = output
        .stdout
        .split(|b| *b == b'\n')
        .filter(|s| !s.is_empty())
        .map(numbers)
        .collect();
    assert_eq!(rows.len(), inputs.len());
    rows
}
struct Case {
    input: Vec<u8>,
    row: Vec<i32>,
}
type Authority<'a> = (Option<&'a [u8]>, &'a [u8], Option<&'a [u8]>, i32);
fn case(
    scheme: Option<&[u8]>,
    authority: Option<Authority<'_>>,
    path: &[u8],
    query: Option<&[u8]>,
    fragment: Option<&[u8]>,
) -> Case {
    let mut input = Vec::new();
    let mut spans = [None; 8];
    fn append(input: &mut Vec<u8>, value: &[u8]) -> Option<(usize, usize)> {
        let start = input.len();
        input.extend(value);
        Some((start, value.len()))
    }
    if let Some(scheme) = scheme {
        spans[0] = append(&mut input, scheme);
        input.push(b':');
    }
    if let Some((userinfo, host, port, _)) = authority {
        input.extend(b"//");
        let start = input.len();
        if let Some(userinfo) = userinfo {
            spans[2] = append(&mut input, userinfo);
            input.push(b'@');
        }
        spans[3] = append(&mut input, host);
        if let Some(port) = port {
            input.push(b':');
            spans[4] = append(&mut input, port);
        }
        spans[1] = Some((start, input.len() - start));
    }
    spans[5] = append(&mut input, path);
    if let Some(query) = query {
        input.push(b'?');
        spans[6] = append(&mut input, query);
    }
    if let Some(fragment) = fragment {
        input.push(b'#');
        spans[7] = append(&mut input, fragment);
    }
    let mut row = vec![0, authority.map_or(-1, |(_, _, _, kind)| kind)];
    for span in spans {
        if let Some((start, len)) = span {
            row.extend([start as i32, len as i32]);
        } else {
            row.extend([-1, -1]);
        }
    }
    Case { input, row }
}
fn check_cases(exe: &common::TempArtifact, cases: &[Case]) {
    for chunk in cases.chunks(64) {
        let inputs: Vec<_> = chunk.iter().map(|c| c.input.clone()).collect();
        let actual = invoke(exe, &inputs);
        for (case, row) in chunk.iter().zip(actual) {
            assert_eq!(row, case.row, "input={:?}", case.input);
        }
    }
}
#[test]
fn specification_examples_and_constructed_references_preserve_every_component() {
    let exe = executable("tests/fixtures/extended/uri_model.lani");
    let mut cases = vec![
        case(None, None, b"", None, None),
        case(
            Some(b"ftp"),
            Some((None, b"ftp.is.co.za", None, 0)),
            b"/rfc/rfc1808.txt",
            None,
            None,
        ),
        case(
            Some(b"http"),
            Some((None, b"www.ietf.org", None, 0)),
            b"/rfc/rfc2396.txt",
            None,
            None,
        ),
        case(
            Some(b"ldap"),
            Some((None, b"[2001:db8::7]", None, 2)),
            b"/c=GB",
            Some(b"objectClass?one"),
            None,
        ),
        case(Some(b"mailto"), None, b"John.Doe@example.com", None, None),
        case(
            Some(b"news"),
            None,
            b"comp.infosystems.www.servers.unix",
            None,
            None,
        ),
        case(Some(b"tel"), None, b"+1-816-555-1212", None, None),
        case(
            Some(b"telnet"),
            Some((None, b"192.0.2.16", Some(b"80"), 1)),
            b"/",
            None,
            None,
        ),
        case(
            Some(b"urn"),
            None,
            b"oasis:names:specification:docbook:dtd:xml:4.1.2",
            None,
            None,
        ),
        case(
            Some(b"foo"),
            Some((None, b"example.com", Some(b"8042"), 0)),
            b"/over/there",
            Some(b"name=ferret"),
            Some(b"nose"),
        ),
        case(
            Some(b"HTTP"),
            Some((Some(b"user:pw"), b"[::ffff:192.0.2.1]", Some(b"080"), 2)),
            b"/a%2Fb",
            Some(b"x=?/"),
            Some(b""),
        ),
    ];
    // RFC 3986 section 5.4's inputs exercise all relative-reference shapes.
    for path in [
        b"g".as_slice(),
        b"./g",
        b"g/",
        b"/g",
        b";x",
        b"g;x",
        b".",
        b"./",
        b"..",
        b"../",
        b"../g",
        b"../..",
        b"../../",
        b"../../g",
        b"../../../g",
        b"/./g",
        b"/../g",
        b"g.",
        b".g",
        b"g..",
        b"..g",
        b"./../g",
        b"./g/.",
        b"g/./h",
        b"g/../h",
        b"g;x=1/./y",
        b"g;x=1/../y",
        b"g:h/i",
    ] {
        if path == b"g:h/i" {
            cases.push(case(Some(b"g"), None, b"h/i", None, None));
        } else {
            cases.push(case(None, None, path, None, None));
        }
    }
    for scheme in [None, Some(b"x".as_slice()), Some(b"A+1-.".as_slice())] {
        for host in [
            b"".as_slice(),
            b"example.test",
            b"127.0.0.1",
            b"01.2.3.4",
            b"256.1.1.1",
            b"a%2fb",
            b"!$&'()*+,;=~",
            b"[::]",
            b"[Vf.a:!~]",
        ] {
            let kind = if host == b"127.0.0.1" {
                1
            } else if host == b"[::]" {
                2
            } else if host == b"[Vf.a:!~]" {
                3
            } else {
                0
            };
            for user in [
                None,
                Some(b"".as_slice()),
                Some(b"a:%40:!$&'()*+,;=~".as_slice()),
            ] {
                for port in [
                    None,
                    Some(b"".as_slice()),
                    Some(b"000999999999999999999999999999999".as_slice()),
                ] {
                    for path in [b"".as_slice(), b"/", b"//a/../b;%00%FF:@"] {
                        cases.push(case(
                            scheme,
                            Some((user, host, port, kind)),
                            path,
                            Some(b"?a/%23:@!$&'()*+,;="),
                            Some(b"/?%00"),
                        ));
                    }
                }
            }
        }
    }
    // Construct from independently valid grammar atoms; expected spans come
    // from concatenation, rather than another splitting implementation.
    let mut state = 0x3986_2026_1024_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state >> 16
    };
    let atoms: &[&[u8]] = &[
        b"a",
        b"Z",
        b"0",
        b"-",
        b".",
        b"_",
        b"~",
        b"%00",
        b"%2F",
        b"%ff",
        b"!$&'()*+,;=",
        b"@",
        b":",
    ];
    for index in 0..1024 {
        let mut path = Vec::new();
        if index % 2 == 0 {
            path.push(b'/');
        }
        for part in 0..1 + next() % 5 {
            if part > 0 {
                path.push(b'/');
            }
            for _ in 0..1 + next() % 5 {
                let choice = next() as usize % atoms.len();
                path.extend(
                    atoms[if index % 2 != 0 && part == 0 && choice == 12 {
                        0
                    } else {
                        choice
                    }],
                );
            }
        }
        let query = [
            None,
            Some(b"".as_slice()),
            Some(b"x=%23%3F%FF?/:@+&".as_slice()),
        ][index % 3];
        let fragment = [None, Some(b"".as_slice()), Some(b"/?a:%20".as_slice())][index / 3 % 3];
        cases.push(case(None, None, &path, query, fragment));
    }
    for value in 0..=255u8 {
        let encoded = format!("%{value:02X}");
        let path = format!("/{encoded}");
        cases.push(case(
            Some(b"x"),
            Some((Some(encoded.as_bytes()), encoded.as_bytes(), None, 0)),
            path.as_bytes(),
            Some(encoded.as_bytes()),
            Some(encoded.as_bytes()),
        ));
    }
    check_cases(&exe, &cases);
}
#[test]
fn malformed_references_report_explicit_relative_offsets() {
    let exe = executable("tests/fixtures/extended/uri_model.lani");
    let cases: &[(&[u8], i32, i32)] = &[
        (b"%", 4, 0),
        (b"a%2", 4, 1),
        (b"%GG", 4, 0),
        (b"?x=%2x", 4, 3),
        (b"#%x2", 4, 1),
        (b"a b", 3, 1),
        (b"a\x7f", 3, 1),
        (b"a\xff", 3, 1),
        (b"a\\b", 3, 1),
        (b":x", 5, 0),
        (b"1x:a", 5, 0),
        (b"a_b:c", 5, 1),
        (b"a%20:b", 5, 1),
        (b"//a@@b", 6, 4),
        (b"//a[b]", 3, 3),
        (b"//user[info]@host", 3, 6),
        (b"//host:8x", 8, 8),
        (b"//host:1:2", 8, 8),
        (b"//host:%30", 8, 7),
        (b"//[::1", 7, 2),
        (b"//[]", 7, 2),
        (b"//[::1]x", 6, 7),
        (b"//[::1]:x", 8, 8),
        (b"//[v.a]", 7, 2),
        (b"//[v1.]", 7, 2),
        (b"//[v1.%30]", 7, 2),
        (b"//[v1.a/b]", 7, 2),
        (b"//[1:2:3:4:5:6:7]", 7, 2),
        (b"//[1:2:3:4:5:6:7:8:9]", 7, 2),
        (b"//[1::2::3]", 7, 2),
        (b"//[1:2:3:4:5:6:7:8::]", 7, 2),
        (b"//[::ffff:192.168.01.1]", 7, 2),
        (b"//[fe80::1%25zone]", 7, 2),
        (b"/a[b]", 3, 2),
        (b"?a[b]", 3, 2),
        (b"#a[b]", 3, 2),
        (b"#a#b", 3, 2),
    ];
    let actual = invoke(
        &exe,
        &cases
            .iter()
            .map(|(input, _, _)| input.to_vec())
            .collect::<Vec<_>>(),
    );
    for (&(input, code, offset), row) in cases.iter().zip(actual) {
        assert_eq!(row, vec![-1, code, offset], "input={input:?}");
    }
    // Every excluded raw byte is rejected in every component. NUL is covered
    // in the direct contract fixture because process arguments cannot carry it.
    let mut inputs = Vec::new();
    for value in 1..=255u8 {
        if value <= 32 || value >= 127 || b"<>\\^`{|}\"".contains(&value) {
            for (prefix, suffix) in [
                (b"".as_slice(), b"".as_slice()),
                (b"//u", b"@h"),
                (b"//h", b""),
                (b"/p", b""),
                (b"?q", b""),
                (b"#f", b""),
            ] {
                let mut input = prefix.to_vec();
                input.push(value);
                input.extend(suffix);
                inputs.push(input);
            }
        }
    }
    for chunk in inputs.chunks(64) {
        for (input, row) in chunk.iter().zip(invoke(&exe, chunk)) {
            assert_eq!(row[0], -1, "input={input:?}");
            assert_eq!(row[1], 3, "input={input:?}");
        }
    }
}
#[test]
fn bracketed_ipv6_matches_native_address_parser_and_ipvfuture_grammar() {
    let exe = executable("tests/fixtures/extended/uri_model.lani");
    let mut addresses = vec![
        "::".to_string(),
        "::1".to_string(),
        "1:2:3:4:5:6:7:8".to_string(),
        "1:2:3:4:5:6:192.0.2.1".to_string(),
        "::ffff:192.0.2.1".to_string(),
    ];
    let mut state = 0x3986_1f06_2026_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state >> 16
    };
    for index in 0..512 {
        let mut words = [0u16; 8];
        for word in &mut words {
            *word = next() as u16;
        }
        let begin = index % 8;
        let width = 1 + index / 8 % (8 - begin);
        words[begin..begin + width].fill(0);
        let address = std::net::Ipv6Addr::from(words);
        addresses.push(address.to_string());
        addresses.push(
            words
                .iter()
                .map(|v| format!("{v:04X}"))
                .collect::<Vec<_>>()
                .join(":"),
        );
        let mut compressed = words[..begin]
            .iter()
            .map(|v| format!("{v:x}"))
            .collect::<Vec<_>>()
            .join(":");
        compressed.push_str("::");
        compressed.push_str(
            &words[begin + width..]
                .iter()
                .map(|v| format!("{v:x}"))
                .collect::<Vec<_>>()
                .join(":"),
        );
        addresses.push(compressed);
    }
    for _ in 0..1024 {
        let mut address = String::new();
        for _ in 0..next() % 10 {
            if !address.is_empty() {
                address.push(':');
            }
            for _ in 0..next() % 7 {
                address.push(b"0123456789abcdef.x"[next() as usize % 18] as char);
            }
        }
        if next() % 2 == 0 {
            address.insert_str(next() as usize % (address.len() + 1), "::");
        }
        addresses.push(address);
    }
    for chunk in addresses.chunks(64) {
        let inputs: Vec<_> = chunk
            .iter()
            .map(|s| format!("//[{s}]").into_bytes())
            .collect();
        for (address, row) in chunk.iter().zip(invoke(&exe, &inputs)) {
            let valid = address.parse::<std::net::Ipv6Addr>().is_ok();
            assert_eq!(row[0] == 0, valid, "address={address:?}, row={row:?}");
            if valid {
                assert_eq!(row[1], 2);
            }
        }
    }
    let mut cases = Vec::new();
    for version in ["0", "F", "f09Ab", "000000000000000000000000000"] {
        for tail in ["x", "!$&'()*+,;=:", "A-._~09"] {
            for prefix in ["v", "V"] {
                let host = format!("[{prefix}{version}.{tail}]");
                cases.push(case(
                    None,
                    Some((None, host.as_bytes(), None, 3)),
                    b"/",
                    None,
                    None,
                ));
            }
        }
    }
    check_cases(&exe, &cases);
}
#[test]
fn dotted_hosts_use_strict_ipv4_first_match_and_registered_name_fallback() {
    let exe = executable("tests/fixtures/extended/uri_model.lani");
    let octets = [
        "0", "1", "9", "10", "99", "100", "199", "200", "249", "250", "255", "256", "999", "00",
        "01", "000", "9999",
    ];
    let mut cases = Vec::new();
    for (index, &octet) in octets.iter().enumerate() {
        for position in 0..4 {
            let mut pieces = ["0", "1", "255", "200"];
            pieces[position] = octet;
            let host = pieces.join(".");
            let kind = i32::from(host.parse::<std::net::Ipv4Addr>().is_ok());
            cases.push(case(
                None,
                Some((None, host.as_bytes(), None, kind)),
                b"",
                None,
                None,
            ));
        }
        for count in 1..=6 {
            let host = vec![octet; count].join(".");
            let kind = i32::from(host.parse::<std::net::Ipv4Addr>().is_ok());
            cases.push(case(
                Some(b"x"),
                Some((None, host.as_bytes(), Some(b""), kind)),
                b"/",
                None,
                None,
            ));
        }
        let host = format!(
            "{}.{octet}.{}.{}",
            octets[index * 3 % octets.len()],
            octets[index * 7 % octets.len()],
            octets[index * 11 % octets.len()]
        );
        let kind = i32::from(host.parse::<std::net::Ipv4Addr>().is_ok());
        cases.push(case(
            None,
            Some((None, host.as_bytes(), None, kind)),
            b"",
            None,
            None,
        ));
    }
    check_cases(&exe, &cases);
}
#[test]
fn default_length_boundary_and_large_borrowed_parses_allocate_no_storage() {
    let exe = executable("tests/fixtures/extended/uri_limits.lani");
    let trace = common::TempArtifact::new("laniusc_uri", "limits", None);
    let output = common::process_output_with_timeout(
        "large borrowed URI",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=2+",
            ])
            .arg(exe.path()),
        std::time::Duration::from_secs(10),
    );
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(!events.contains("INJECTED"), "parser allocated: {events}");
    assert_eq!(
        events.lines().filter(|s| s.starts_with("mmap(")).count(),
        1,
        "{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|s| s.starts_with("munmap(") && s.ends_with(" = 0"))
            .count(),
        1,
        "{events}"
    );
}
