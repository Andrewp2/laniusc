#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

const FILE: u8 = 0;
const DIRECTORY: u8 = 1;
const CREATOR: u8 = 10;
const TYPE: u8 = 11;
const CONTRADICTION: u8 = 12;
const EXTRA: u8 = 13;
const MALFORMED: u8 = 14;
const DIRECTORY_DATA: u8 = 15;
const BOUNDS: u8 = 16;

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/extended/archive_profile/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("archive-profile", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("archive-profile: {error}"));
        let exe = common::TempArtifact::new("laniusc_archive_profile", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

struct Case { name: String, format: u8, mutation: u8, archive: Vec<u8>, expected: u8 }
fn case(name: impl Into<String>, format: u8, archive: Vec<u8>, expected: u8) -> Case {
    Case { name: name.into(), format, mutation: 0, archive, expected }
}
fn check(cases: Vec<Case>, no_filesystem: bool) {
    let mut request = Vec::new();
    for item in &cases {
        request.extend_from_slice(&[item.format, item.mutation, 0, 0]);
        request.extend_from_slice(&(item.archive.len() as u32).to_le_bytes());
        request.extend_from_slice(&item.archive);
    }
    assert!(request.len() <= 1_048_576);
    let input = common::TempArtifact::new("laniusc_archive_profile", "input", None);
    input.write_bytes(request);
    let trace = common::TempArtifact::new("laniusc_archive_profile", "trace", None);
    let mut command = if no_filesystem {
        let mut command = Command::new("strace");
        command.args(["-qq", "-o"]).arg(trace.path()).args(["-e", "trace=openat,mkdirat,unlinkat,renameat2,linkat,symlinkat,mknodat,chmod,fchmod,chown,fchown,utimensat"]).arg(executable().path());
        command
    } else { Command::new(executable().path()) };
    command.stdin(std::fs::File::open(input.path()).unwrap());
    let output = common::process_output_with_timeout("archive metadata profile", &mut command, Duration::from_secs(20));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), cases.len(), "{output:?}");
    for (item, actual) in cases.iter().zip(output.stdout) {
        assert_eq!(actual, item.expected, "{}: 98 denotes canonical-parser failure, not a profile decision", item.name);
    }
    if no_filesystem { assert!(std::fs::read(trace.path()).unwrap().is_empty()); }
    eprintln!("archive-profile cases={}", cases.len());
}

fn put16(out: &mut Vec<u8>, value: u16) { out.extend_from_slice(&value.to_le_bytes()); }
fn put32(out: &mut Vec<u8>, value: u32) { out.extend_from_slice(&value.to_le_bytes()); }
fn field(id: u16, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new(); put16(&mut out,id); put16(&mut out,body.len().try_into().unwrap()); out.extend_from_slice(body); out
}
// Independent classic ZIP fixture encoder, without the Lanius writer. Payloads
// are empty or one zero byte (its independently known CRC32 is 0xd202ef8d).
// The empty DEFLATE stream is the two literal bytes 03 00, never compressed here.
fn zip(name: &[u8], creator: u16, attrs: u32, local: &[u8], central: &[u8], payload: bool, deflated: bool) -> Vec<u8> {
    assert!(!payload || !deflated);
    let data: &[u8] = if deflated { &[3,0] } else if payload { &[0] } else { &[] };
    let crc = if payload { 0xd202ef8d } else { 0 };
    let size = u32::from(payload);
    let needed = if deflated { 20 } else { 10 };
    let method = if deflated { 8 } else { 0 };
    let mut out = Vec::new(); put32(&mut out,0x04034b50);
    for value in [needed,0,method,0,0] { put16(&mut out,value); }
    put32(&mut out,crc); put32(&mut out,data.len() as u32); put32(&mut out,size);
    put16(&mut out,name.len().try_into().unwrap()); put16(&mut out,local.len().try_into().unwrap());
    out.extend_from_slice(name); out.extend_from_slice(local); out.extend_from_slice(data);
    let start = out.len() as u32; put32(&mut out,0x02014b50);
    for value in [creator,needed,0,method,0,0] { put16(&mut out,value); }
    put32(&mut out,crc); put32(&mut out,data.len() as u32); put32(&mut out,size);
    for value in [u16::try_from(name.len()).unwrap(),u16::try_from(central.len()).unwrap(),0,0,0] { put16(&mut out,value); }
    put32(&mut out,attrs); put32(&mut out,0); out.extend_from_slice(name); out.extend_from_slice(central);
    let length = out.len() as u32-start; put32(&mut out,0x06054b50);
    for value in [0,0,1,1] { put16(&mut out,value); }
    put32(&mut out,length); put32(&mut out,start); put16(&mut out,0); out
}
fn basic(name: &[u8], creator: u16, attrs: u32) -> Vec<u8> { zip(name,creator,attrs,&[],&[],false,false) }
fn with_extra(id: u16, body: &[u8], central: bool) -> Vec<u8> {
    let extra = field(id,body);
    if central { zip(b"raw-name",20,0,&[],&extra,false,false) }
    else { zip(b"raw-name",20,0,&extra,&[],false,false) }
}
fn octal(destination: &mut [u8], value: u64) {
    let digits = format!("{value:0width$o}",width=destination.len()-1);
    assert_eq!(digits.len(),destination.len()-1);
    destination[..digits.len()].copy_from_slice(digits.as_bytes());
    *destination.last_mut().unwrap() = 0;
}
fn tar(name: &[u8], kind: u8, size: u64) -> Vec<u8> {
    let mut header = vec![0;512]; assert!(name.len() <= 100); header[..name.len()].copy_from_slice(name);
    octal(&mut header[100..108],0o7777); octal(&mut header[108..116],123); octal(&mut header[116..124],456);
    octal(&mut header[124..136],size); octal(&mut header[136..148],789); header[148..156].fill(b' '); header[156]=kind;
    if kind==b'1' || kind==b'2' { header[157..163].copy_from_slice(b"target"); }
    header[257..265].copy_from_slice(&[117,115,116,97,114,0,48,48]);
    let checksum: u64 = header.iter().map(|byte| u64::from(*byte)).sum();
    let text = format!("{checksum:06o}\0 "); header[148..156].copy_from_slice(text.as_bytes());
    if kind==0 || kind==b'0' || kind==b'7' { header.resize(header.len()+((size as usize+511)/512)*512,0); }
    header.resize(header.len()+1024,0); header
}

#[test]
fn tar_profile_uses_canonical_kinds_and_never_directory_size_as_data() {
    let mut cases = Vec::new();
    for kind in [0,b'0',b'1',b'2',b'3',b'4',b'5',b'6',b'7'] {
        let expected = match kind { 0|b'0'=>FILE,b'5'=>DIRECTORY,_=>TYPE };
        cases.push(case(format!("kind-{kind}"),1,tar(b"member",kind,0),expected));
    }
    cases.push(case("regular-with-data",1,tar(b"member",b'0',1),FILE));
    cases.push(case("directory-size-hint",1,tar(b"directory",b'5',123456),DIRECTORY));
    cases.push(case("regular-slash-is-still-regular",1,tar(b"regular/",b'0',0),FILE));
    cases.push(case("directory-with-slash",1,tar(b"directory/",b'5',0),DIRECTORY));
    for mutation in 1..=5 {
        let mut item=case(format!("tar-mutation-{mutation}"),1,tar(b"directory",b'5',0),if mutation==5 {DIRECTORY_DATA} else {BOUNDS}); item.mutation=mutation; cases.push(item);
    }
    check(cases,true);
}

#[test]
fn zip_profile_checks_creator_types_attribute_bits_and_zero_size_directories() {
    let mut cases=vec![case("DOS-file-zero",2,basic(b"file",20,0),FILE),case("DOS-directory-zero",2,basic(b"dir/",20,0),DIRECTORY)];
    for bit in 0..32 {
        let expected=match bit {0|1|2|5=>FILE,4=>CONTRADICTION,_=>TYPE};
        cases.push(case(format!("DOS-attribute-bit-{bit}"),2,basic(b"file",20,1u32<<bit),expected));
    }
    cases.push(case("DOS-dir-bit",2,basic(b"dir/",20,16),DIRECTORY));
    cases.push(case("DOS-clear-dir-is-no-file-assertion",2,basic(b"dir/",20,32),DIRECTORY));
    for creator in [1,10,19,255] { cases.push(case(format!("creator-{creator}"),2,basic(b"file",(creator<<8)|20,0),CREATOR)); }
    for creator in [0,3] { cases.push(case(format!("producer-version255-{creator}"),2,basic(b"file",(creator<<8)|255,0),FILE)); }
    for (name,attrs,expected) in [
        (&b"file"[..],0x81a40000,FILE),(&b"dir/"[..],0x41ed0000,DIRECTORY),
        (&b"dir/"[..],0x41ed0010,DIRECTORY),(&b"file"[..],0x8fff0037,CONTRADICTION),
        (&b"file"[..],0x8fff0027,FILE),(&b"file"[..],0x01ff0000,FILE),
        (&b"dir/"[..],0x01ff0000,DIRECTORY),(&b"dir/"[..],0x81a40000,CONTRADICTION),
        (&b"file"[..],0x41ed0000,CONTRADICTION),(&b"file"[..],0x81a40010,CONTRADICTION),
    ] { cases.push(case(format!("Unix-{name:?}-{attrs:08x}"),2,basic(name,0x0314,attrs),expected)); }
    for mode in [0x1000,0x2000,0x3000,0x5000,0x6000,0x7000,0xa000,0xb000,0xc000,0xd000,0xe000,0xf000] {
        cases.push(case(format!("Unix-special-{mode:x}"),2,basic(b"file",0x0314,mode<<16),TYPE));
    }
    for bit in [3,6,7,8,9,10,11,12,13,14,15] { cases.push(case(format!("Unix-reserved-{bit}"),2,basic(b"file",0x0314,1u32<<bit),TYPE)); }
    cases.push(case("empty-name",2,basic(b"",20,0),CONTRADICTION));
    cases.push(case("empty-regular",2,basic(b"file",20,32),FILE));
    cases.push(case("directory-data",2,zip(b"dir/",20,0,&[],&[],true,false),DIRECTORY_DATA));
    cases.push(case("deflated-empty-directory",2,zip(b"dir/",20,16,&[],&[],false,true),DIRECTORY));
    for name in [b"../escape".as_slice(),b"/absolute",b"C:/file",b"bad\\leaf",b"a//b"] {
        cases.push(case(format!("path-policy-is-separate-{name:?}"),2,basic(name,20,0),FILE));
    }
    check(cases,true);
}

#[test]
fn zip_profile_allowlists_and_validates_both_extra_header_shapes() {
    let mut cases=Vec::new();
    for central in [false,true] {
        for flags in 0u8..8 {
            let count=if central {u32::from(flags&1)} else {flags.count_ones()};
            let mut body=vec![flags]; body.resize(1+4*count as usize,0);
            cases.push(case(format!("UT-{central}-{flags}"),2,with_extra(0x5455,&body,central),FILE));
        }
        for (id,body) in [(0x5455,vec![]),(0x5455,vec![8]),(0x5455,vec![1]),(0x5455,vec![0,0]),(0x7875,vec![]),(0x7875,vec![1]),(0x7875,vec![1,0,1,0]),(0x7875,vec![1,1,0,0]),(0x7875,vec![1,255,0]) ] {
            cases.push(case(format!("bad-shape-{central}-{id:x}-{body:?}"),2,with_extra(id,&body,central),MALFORMED));
        }
        for width in [1usize,4,8,255] {
            let mut body=vec![1,width as u8]; body.resize(2+width,255); body.push(width as u8); body.resize(3+2*width,128);
            cases.push(case(format!("UIDGID-{central}-{width}"),2,with_extra(0x7875,&body,central),FILE));
        }
        for id in [0x7875,0x7075,0x6375] {
            cases.push(case(format!("unknown-version-{central}-{id:x}"),2,with_extra(id,&[2,0,0,0,0],central),EXTRA));
        }
        for id in [0x7075,0x6375] {
            for text in [b"".as_slice(),b"../ignored/",b"\xc3\xa9"] {
                let mut body=vec![1,255,255,255,255]; body.extend_from_slice(text);
                cases.push(case(format!("Unicode-{central}-{id:x}-{text:?}"),2,with_extra(id,&body,central),FILE));
            }
            for body in [vec![],vec![1],vec![1,0,0,0],vec![1,0,0,0,0,255],vec![1,0,0,0,0,192,175],vec![1,0,0,0,0,237,160,128]] {
                cases.push(case(format!("bad-Unicode-{central}-{id:x}-{body:?}"),2,with_extra(id,&body,central),MALFORMED));
            }
        }
        for id in [0x000a,0x000d,0x5855,0x756e,0x7855,0xffff] {
            cases.push(case(format!("unsupported-extra-{central}-{id:x}"),2,with_extra(id,&[],central),EXTRA));
        }
        for (id,body) in [(0x5455,vec![0]),(0x7875,vec![1,1,0,1,0]),(0x7075,vec![1,0,0,0,0]),(0x6375,vec![1,0,0,0,0])] {
            let mut extra=field(id,&body); extra.extend_from_slice(&field(id,&body));
            let archive=if central {zip(b"name",20,0,&[],&extra,false,false)} else {zip(b"name",20,0,&extra,&[],false,false)};
            cases.push(case(format!("duplicate-extra-{central}-{id:x}"),2,archive,MALFORMED));
        }
    }
    let mut all=Vec::new(); for (id,body) in [(0x5455,vec![0]),(0x7875,vec![1,1,0,1,0]),(0x7075,vec![1,0,0,0,0]),(0x6375,vec![1,0,0,0,0])] {all.extend_from_slice(&field(id,&body));}
    cases.push(case("all-four-local-and-central",2,zip(b"file",0x0314,0x81a40000,&all,&all,false,false),FILE));
    let mut full=vec![1,0,0,0,0]; full.resize(65531,b'a'); let full=field(0x7075,&full); assert_eq!(full.len(),65535);
    cases.push(case("maximum-extra-both-headers",2,zip(b"file",20,0,&full,&full,false,false),FILE));
    let alternate=field(0x7075,&[1,0,0,0,0,b'f',b'i',b'l',b'e']);
    cases.push(case("Unicode-path-cannot-turn-directory-into-file",2,zip(b"dir/",20,0,&alternate,&alternate,false,false),DIRECTORY));
    cases.push(case("central-does-not-store-all-UT-times",2,with_extra(0x5455,&[7,0,0,0,0,0,0,0,0,0,0,0,0],true),MALFORMED));
    check(cases,false);
}

#[test]
fn profile_public_entries_check_bounds_and_support_strided_metadata() {
    let mut cases=Vec::new();
    for mutation in 1..=11 {
        let mut item=case(format!("zip-mutation-{mutation}"),2,basic(b"file",20,0),if mutation==11 {CONTRADICTION} else {BOUNDS}); item.mutation=mutation; cases.push(item);
    }
    let mut strided=case("strided-stack-extra-both-headers",2,basic(b"file",20,0),FILE); strided.mutation=20; cases.push(strided);
    check(cases,false);
}
