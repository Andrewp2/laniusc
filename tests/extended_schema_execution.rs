#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    time::Duration,
};

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = format!("tests/fixtures/extended_library/schema_{name}.lani");
    let entry = root.join(&path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(&path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_schema", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[derive(Clone)]
struct Case {
    schema: String,
    instance: String,
    work: u64,
    nodes: i32,
    sd: i32,
    vd: i32,
    scratch: i32,
}
impl Case {
    fn new(s: impl Into<String>, i: impl Into<String>) -> Self {
        Self {
            schema: s.into(),
            instance: i.into(),
            work: 100_000_000,
            nodes: 100_000,
            sd: 64,
            vd: 64,
            scratch: 32768,
        }
    }
}
fn run(exe: &common::TempArtifact, cases: &[Case]) -> Vec<[i32; 8]> {
    let mut input = Vec::new();
    for c in cases {
        for v in [
            c.schema.len() as i32,
            c.instance.len() as i32,
            c.work as i32,
            (c.work >> 32) as i32,
            c.nodes,
            c.sd,
            c.vd,
            c.scratch,
        ] {
            input.extend(v.to_le_bytes());
        }
        input.extend(c.schema.as_bytes());
        input.extend(c.instance.as_bytes());
    }
    let file = common::TempArtifact::new("laniusc_schema", "input", None);
    file.write_bytes(&input);
    let output = common::process_output_with_timeout(
        "schema model",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(25),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), cases.len() * 32);
    output
        .stdout
        .chunks_exact(32)
        .map(|r| {
            std::array::from_fn(|i| i32::from_le_bytes(r[4 * i..4 * i + 4].try_into().unwrap()))
        })
        .collect()
}
const REFERENCE: &str = r#"
import json,sys
from decimal import Decimal
from fractions import Fraction
from jsonschema import Draft202012Validator, validators, ValidationError
number=Draft202012Validator.TYPE_CHECKER.redefine('integer',lambda c,v:isinstance(v,(int,Decimal)) and not isinstance(v,bool) and v==int(v))
def multiple(validator,divisor,value,schema):
 if validator.is_type(value,'number') and (Fraction(value)/Fraction(divisor)).denominator!=1:yield ValidationError('not multiple')
Validator=validators.extend(Draft202012Validator,{'multipleOf':multiple},type_checker=number)
for line in sys.stdin:
 s,i=json.loads(line)
 schema=json.loads(s,parse_float=Decimal);instance=json.loads(i,parse_float=Decimal)
 print(int(Validator(schema).is_valid(instance)))
"#;
fn reference(cases: &[Case]) -> Vec<bool> {
    let text = cases
        .iter()
        .map(|c| serde_json::to_string(&[&c.schema, &c.instance]).unwrap() + "\n")
        .collect::<String>();
    let file = common::TempArtifact::new("laniusc_schema", "reference", None);
    file.write_bytes(text.as_bytes());
    let output = common::process_output_with_timeout(
        "Python jsonschema",
        Command::new("python3")
            .args(["-c", REFERENCE])
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        Duration::from_secs(25),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|v| v == "1")
        .collect()
}
fn pair(out: &mut Vec<Case>, s: &str, instances: &[&str]) {
    for i in instances {
        out.push(Case::new(s, *i));
    }
}
#[test]
fn schema_executes_supported_rules_against_independent_2020_12_validator() {
    let exe = executable("model");
    let mut cases = Vec::new();
    for s in [
        "true",
        "false",
        "{}",
        r#"{"type":["null","boolean","integer","string","array","object"]}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                "null",
                "true",
                "false",
                "0",
                "1.00",
                "0.3",
                r#""é🙂""#,
                "[]",
                "{}",
            ],
        );
    }
    for t in [
        "null", "boolean", "integer", "number", "string", "array", "object",
    ] {
        let s = format!(r#"{{"type":"{t}"}}"#);
        pair(
            &mut cases,
            &s,
            &[
                "null",
                "true",
                "0",
                "1.00",
                "1e-1",
                "9007199254740993",
                r#""x""#,
                "[]",
                "{}",
            ],
        );
    }
    for s in [
        r#"{"const":{"x":1,"y":[null,true,1.00]}}"#,
        r#"{"enum":[{"x":1,"y":[null,true,1.0]},2,"two",false]}"#,
        r#"{"enum":[]}"#,
        r#"{"enum":[1,1.0,1e0]}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                r#"{"y":[null,true,1e0],"x":1.00}"#,
                r#"{"x":1,"y":[null,1,1]}"#,
                "1",
                "2",
                "false",
                "0",
                r#""two""#,
            ],
        );
    }
    for s in [
        r#"{"minimum":-2,"maximum":3}"#,
        r#"{"exclusiveMinimum":-2,"exclusiveMaximum":3}"#,
        r#"{"multipleOf":0.1}"#,
        r#"{"multipleOf":3e-2}"#,
        r#"{"multipleOf":9007199254740993}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                "-3",
                "-2",
                "-1.90",
                "0",
                "0.03",
                "0.3",
                "3",
                "3.01",
                "9007199254740993",
                "18014398509481986",
                "9007199254740992",
                r#""1""#,
            ],
        );
    }
    for s in [
        r#"{"minLength":1,"maxLength":2}"#,
        r#"{"minLength":1e10}"#,
        r#"{"maxLength":1e20}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                r#""""#,
                r#""a""#,
                r#""é""#,
                r#""🙂""#,
                r#""e\u0301""#,
                r#""\u0000é🙂""#,
                "[]",
            ],
        );
    }
    for s in [
        r#"{"minItems":1,"maxItems":2}"#,
        r#"{"prefixItems":[{"type":"integer"},{"type":"string"}],"items":false}"#,
        r#"{"items":{"type":"integer"}}"#,
        r#"{"uniqueItems":true}"#,
        r#"{"contains":{"type":"integer"}}"#,
        r#"{"contains":{"type":"integer"},"minContains":0,"maxContains":1}"#,
        r#"{"contains":false,"minContains":0}"#,
        r#"{"minContains":10,"maxContains":0}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                "[]",
                "[1]",
                "[1,2]",
                r#"[1,"x"]"#,
                r#"[1,"x",true]"#,
                "[1,1.0]",
                r#"[{"a":1,"b":2},{"b":2.0,"a":1.0}]"#,
                r#"[true,"x"]"#,
                "{}",
            ],
        );
    }
    for s in [
        r#"{"type":"object","properties":{"a":{"type":"integer"}},"required":["a"],"additionalProperties":false}"#,
        r#"{"properties":{"a":false},"additionalProperties":{"type":"string"}}"#,
        r#"{"minProperties":1,"maxProperties":2}"#,
        r#"{"dependentRequired":{"a":["b","c"]}}"#,
        r#"{"dependentSchemas":{"a":{"required":["b"]}}}"#,
        r#"{"propertyNames":{"minLength":1,"maxLength":2}}"#,
        r#"{"allOf":[{"properties":{"a":true}}],"additionalProperties":false}"#,
    ] {
        pair(
            &mut cases,
            s,
            &[
                "{}",
                r#"{"a":1}"#,
                r#"{"a":1,"b":2}"#,
                r#"{"a":1,"b":2,"c":3}"#,
                r#"{"a":"x"}"#,
                r#"{"b":"x"}"#,
                r#"{"":"empty"}"#,
                r#"{"é🙂":null}"#,
                r#"{"abc":1}"#,
                "[]",
            ],
        );
    }
    for s in [
        r#"{"allOf":[{"minimum":1},{"maximum":3}]}"#,
        r#"{"anyOf":[{"type":"integer"},{"type":"string"}]}"#,
        r#"{"oneOf":[{"type":"number"},{"type":"integer"}]}"#,
        r#"{"not":{"type":"boolean"}}"#,
        r#"{"if":{"type":"number"},"then":{"minimum":2},"else":{"const":"x"}}"#,
        r#"{"then":false,"else":false}"#,
    ] {
        pair(
            &mut cases,
            s,
            &["null", "false", "0", "1", "2", "3.5", r#""x""#, r#""y""#],
        );
    }
    for s in [
        r##"{"$defs":{"x":{"type":"integer"}},"$ref":"#/$defs/x","minimum":2}"##,
        r##"{"$defs":{"a/b":{"type":"string"}},"$ref":"#/$defs/a~1b"}"##,
        r##"{"$defs":{"m~n":{"type":"null"}},"$ref":"#/$defs/m~0n"}"##,
        r##"{"$defs":{"é":{"type":"boolean"}},"$ref":"#/%24defs/%C3%A9"}"##,
        r##"{"$ref":"#/allOf/0","allOf":[{"type":"number"}]}"##,
    ] {
        pair(&mut cases, s, &["null", "true", "1", "2", r#""hi""#]);
    }
    // Seeded model exploration combines independent rules with varied values.
    let mut seed = 0x8202_2020_u32;
    for _ in 0..1500 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let n = (seed % 101) as i32 - 50;
        let s=match seed%6{0=>format!(r#"{{"minimum":{},"exclusiveMaximum":{}}}"#,n,n+7),1=>format!(r#"{{"multipleOf":{}}}"#,1+(seed%19)),2=>format!(r#"{{"type":["integer","string"],"minLength":{},"maxLength":{}}}"#,seed%3,3+seed%5),3=>r#"{"type":"array","items":{"type":"integer","minimum":-30},"uniqueItems":true,"minItems":1,"maxItems":4}"#.to_owned(),4=>r#"{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"string"}},"additionalProperties":false,"dependentRequired":{"a":["b"]}}"#.to_owned(),_=>r#"{"if":{"type":"array"},"then":{"contains":{"type":"integer"},"minContains":0,"maxContains":2},"else":{"not":{"type":"null"}}}"#.to_owned()};
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let i = match seed % 7 {
            0 => n.to_string(),
            1 => format!("{n}.5"),
            2 => {
                serde_json::to_string(&["", "é🙂", "hello", "\0", "e\u{301}"][(seed % 5) as usize])
                    .unwrap()
            }
            3 => format!("[{n},{},{}]", seed % 9, n / 2),
            4 => format!(r#"{{"a":{n},"b":"x"}}"#),
            5 => "null".to_owned(),
            _ => r#"["x",true,1]"#.to_owned(),
        };
        cases.push(Case::new(s, i));
    }
    let expected = reference(&cases);
    let actual = run(&exe, &cases);
    assert_eq!(actual.len(), expected.len());
    for (index, ((c, r), want)) in cases.iter().zip(actual).zip(expected).enumerate() {
        assert!(
            r[0] <= 1,
            "case {index}: {} / {} => {r:?}",
            c.schema,
            c.instance
        );
        assert_eq!(
            r[0] == 0,
            want,
            "case {index}: {} / {} => {r:?}",
            c.schema,
            c.instance
        );
        assert!(r[5] > 0);
    }
}
#[test]
fn schema_rejects_invalid_unsupported_duplicate_and_unresolvable_rules_upfront() {
    let exe = executable("model");
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    let groups: &[(i32, &[&str])] = &[
        (
            3,
            &[
                "null",
                "0",
                "[]",
                r#"{"type":null}"#,
                r#"{"type":[]}"#,
                r#"{"type":["integer","integer"]}"#,
                r#"{"type":["number",1]}"#,
                r#"{"type":"Integer"}"#,
                r#"{"enum":1}"#,
                r#"{"minimum":true}"#,
                r#"{"maximum":"2"}"#,
                r#"{"exclusiveMinimum":true}"#,
                r#"{"multipleOf":0}"#,
                r#"{"multipleOf":-1}"#,
                r#"{"multipleOf":-0.0}"#,
                r#"{"minLength":-1}"#,
                r#"{"maxItems":0.1}"#,
                r#"{"minProperties":1e-2}"#,
                r#"{"uniqueItems":1}"#,
                r#"{"required":"x"}"#,
                r#"{"required":["a","a"]}"#,
                r#"{"required":[true]}"#,
                r#"{"dependentRequired":[]}"#,
                r#"{"dependentRequired":{"a":["b","b"]}}"#,
                r#"{"allOf":[]}"#,
                r#"{"anyOf":[true,3]}"#,
                r#"{"oneOf":{}}"#,
                r#"{"prefixItems":[]}"#,
                r#"{"items":[]}"#,
                r#"{"contains":[]}"#,
                r#"{"properties":[]}"#,
                r#"{"properties":{"x":null}}"#,
                r#"{"dependentSchemas":{"missing":1}}"#,
                r#"{"$defs":{"unused":{"items":[]}}}"#,
                r#"{"then":{"required":null}}"#,
                r#"{"else":1}"#,
                r#"{"if":true,"then":false,"else":{"minimum":"bad"}}"#,
                r#"{"not":42}"#,
                r#"{"$ref":1}"#,
                r#"{"$schema":1}"#,
                r#"{"title":false}"#,
                r#"{"description":1}"#,
                r#"{"examples":{}}"#,
                r#"{"deprecated":1}"#,
                r#"{"readOnly":"true"}"#,
                r#"{"writeOnly":null}"#,
                r#"{"$comment":false}"#,
            ],
        ),
        (
            4,
            &[
                r#"{"pattern":"x"}"#,
                r#"{"patternProperties":{}}"#,
                r#"{"format":"email"}"#,
                r#"{"contentEncoding":"base64"}"#,
                r#"{"contentMediaType":"application/json"}"#,
                r#"{"contentSchema":true}"#,
                r#"{"unevaluatedItems":false}"#,
                r#"{"unevaluatedProperties":false}"#,
                r#"{"$id":"https://x/"}"#,
                r#"{"$anchor":"x"}"#,
                r##"{"$dynamicRef":"#x"}"##,
                r#"{"$dynamicAnchor":"x"}"#,
                r#"{"$vocabulary":{}}"#,
                r#"{"definitions":{}}"#,
                r#"{"dependencies":{}}"#,
                r#"{"additionalItems":false}"#,
                r#"{"custom":true}"#,
                r#"{"$defs":{"unused":{"pattern":"x"}}}"#,
                r#"{"if":false,"then":{"format":"uri"}}"#,
            ],
        ),
        (
            5,
            &[
                r#"{"$schema":"http://json-schema.org/draft-07/schema#"}"#,
                r#"{"$defs":{"unused":{"$schema":"https://json-schema.org/draft/2020-12/schema"}}}"#,
            ],
        ),
        (
            6,
            &[
                r##"{"$defs":{"unused":{"$ref":"#/$defs/missing"}}}"##,
                r##"{"$ref":"https://example.com/s"}"##,
                r##"{"$ref":"other.json#"}"##,
                r##"{"$ref":"#named"}"##,
                r##"{"$ref":"#/$defs/missing","$defs":{}}"##,
                r##"{"$ref":"#/const","const":{"type":"integer"}}"##,
                r##"{"$ref":"#/$defs","$defs":{"x":true}}"##,
                r##"{"$ref":"#/allOf/01","allOf":[true,true]}"##,
                r##"{"$ref":"#/allOf/-","allOf":[true]}"##,
                r##"{"$ref":"#/allOf/2147483648","allOf":[true]}"##,
                r##"{"$ref":"#/%GG"}"##,
                r##"{"$ref":"#/%0"}"##,
                r##"{"$ref":"#/$defs/a~2b","$defs":{"a~2b":true}}"##,
                r##"{"$ref":"#/$defs/raw space","$defs":{"raw space":true}}"##,
                r##"{"$ref":"#/$defs/é","$defs":{"é":true}}"##,
                r##"{"$ref":"#/$defs/%FF","$defs":{"x":true}}"##,
                r##"{"$ref":"#/$defs/x/","$defs":{"x":true}}"##,
            ],
        ),
        (
            7,
            &[
                r#"{"type":"number","type":"string"}"#,
                r#"{"title":"a","\u0074itle":"b"}"#,
                r#"{"const":{"x":1,"x":2}}"#,
                r#"{"examples":[{"x":1,"x":2}]}"#,
            ],
        ),
    ];
    for (error, schemas) in groups {
        for s in *schemas {
            cases.push(Case::new(*s, "null"));
            expected.push((2, *error));
        }
    }
    for i in [r#"{"x":1,"x":2}"#, r#"[{"a":1,"\u0061":2}]"#] {
        cases.push(Case::new("true", i));
        expected.push((3, 7));
    }
    for (index, (result, want)) in run(&exe, &cases).into_iter().zip(expected).enumerate() {
        assert_eq!(
            (result[0], result[1]),
            want,
            "case {index}: {} / {}: {result:?}",
            cases[index].schema,
            cases[index].instance
        );
    }
    // Supported annotation shapes, including arbitrary data, do not constrain instances.
    let s = r#"{"$schema":"https://json-schema.org/draft/2020-12/schema","$comment":"comment","title":"t","description":"d","default":{"pattern":"data"},"examples":[{"unknown":"data"}],"deprecated":true,"readOnly":false,"writeOnly":true,"required":[],"dependentRequired":{"x":[]}}"#;
    assert_eq!(run(&exe, &[Case::new(s, "null")])[0][0], 0);
}
#[test]
fn schema_exact_numbers_pointer_tokens_recursive_schemas_and_property_name_locations() {
    let exe = executable("model");
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for (s, i, want) in [
        (
            r##"{"$defs":{"":{"type":"integer"}},"$ref":"#/$defs/"}"##,
            "1",
            true,
        ),
        (
            r##"{"$defs":{"":{"type":"integer"}},"$ref":"#/$defs/"}"##,
            "false",
            false,
        ),
        (
            r##"{"$defs":{"~1":{"type":"null"}},"$ref":"#/$defs/~01"}"##,
            "null",
            true,
        ),
        (
            r##"{"$defs":{"/":{"type":"boolean"}},"$ref":"#%2F$defs%2F%7E1"}"##,
            "false",
            true,
        ),
        (
            r##"{"$defs":{"a":{"$defs":{"b":false}}},"$ref":"#/$defs/a/$defs/b"}"##,
            "false",
            false,
        ),
        (
            r##"{"$defs":{"a":{"properties":{"":{"type":"null"}}}},"$ref":"#/$defs/a/properties/"}"##,
            "null",
            true,
        ),
        (
            r##"{"$defs":{"a":{"type":"integer"}},"propertyNames":{"$ref":"#/$defs/a"}}"##,
            r#"{"3":0}"#,
            false,
        ),
        (
            r##"{"$defs":{"key":{"enum":["é🙂",""]}},"propertyNames":{"$ref":"#/$defs/key"}}"##,
            r#"{"é🙂":null,"":1}"#,
            true,
        ),
        (
            r##"{"$defs":{"key":{"enum":["é🙂",""]}},"propertyNames":{"$ref":"#/$defs/key"}}"##,
            r#"{"wrong":false}"#,
            false,
        ),
        (
            r##"{"anyOf":[{"type":"null"},{"type":"array","items":{"$ref":"#"}}]}"##,
            "[null,[null,[]]]",
            true,
        ),
        (
            r##"{"anyOf":[{"type":"null"},{"type":"array","items":{"$ref":"#"}}]}"##,
            "[null,[1]]",
            false,
        ),
        (
            r##"{"type":"object","properties":{"child":{"$ref":"#"}},"additionalProperties":false}"##,
            r#"{"child":{"child":{}}}"#,
            true,
        ),
        (
            r##"{"type":"object","properties":{"child":{"$ref":"#"}},"additionalProperties":false}"##,
            r#"{"child":{"x":1}}"#,
            false,
        ),
        (
            r#"{"type":"integer"}"#,
            "1e9999999999999999999999999999999999999999999",
            true,
        ),
        (
            r#"{"type":"integer"}"#,
            "1e-9999999999999999999999999999999999999999999",
            false,
        ),
        (
            r#"{"const":1e9999999999999999999999999999999999999999999}"#,
            "10e9999999999999999999999999999999999999999998",
            true,
        ),
        (r#"{"const":9007199254740993}"#, "9007199254740992", false),
        (
            r#"{"const":-0.0}"#,
            "0e-99999999999999999999999999999999",
            true,
        ),
        (
            r#"{"minimum":1e9999999999999999999999999999999999999999999}"#,
            "1e9999999999999999999999999999999999999999998",
            false,
        ),
        (
            r#"{"maximum":1e-9999999999999999999999999999999999999999999}"#,
            "-1e9999999999999999999999999999999999999999999",
            true,
        ),
        (
            r#"{"multipleOf":3}"#,
            "1e9999999999999999999999999999999999999999999",
            false,
        ),
        (
            r#"{"multipleOf":3e9999999999999999999999999999999999999999999}"#,
            "9e9999999999999999999999999999999999999999999",
            true,
        ),
        (
            r#"{"multipleOf":1e-9999999999999999999999999999999999999999999}"#,
            "1",
            true,
        ),
        (
            r#"{"minItems":1e9999999999999999999999999999999999999999999}"#,
            "[]",
            false,
        ),
        (
            r#"{"maxProperties":1e9999999999999999999999999999999999999999999}"#,
            "{}",
            true,
        ),
        (
            r#"{"minLength":-0e9999999999999999999999999999999}"#,
            r#""""#,
            true,
        ),
        (
            r#"{"uniqueItems":true}"#,
            r#"[{"a":[1,{"b":true}],"x":2},{"x":2.0,"a":[1e0,{"b":true}]}]"#,
            false,
        ),
        (r#"{"uniqueItems":true}"#, "[0,false,1,true,\"1\"]", true),
    ] {
        cases.push(Case::new(s, i));
        expected.push(want);
    }
    for (index, (result, want)) in run(&exe, &cases).into_iter().zip(expected).enumerate() {
        assert!(
            result[0] <= 1,
            "case {index}: {} / {}: {result:?}",
            cases[index].schema,
            cases[index].instance
        );
        assert_eq!(
            result[0] == 0,
            want,
            "case {index}: {} / {}: {result:?}",
            cases[index].schema,
            cases[index].instance
        );
    }
    let result = run(
        &exe,
        &[Case::new(
            r##"{"$defs":{"key":{"minLength":2}},"propertyNames":{"$ref":"#/$defs/key"}}"##,
            r#"{"é":0}"#,
        )],
    )[0];
    assert_eq!((result[0], result[1], result[4]), (1, 9, 1));
    assert!(result[2] > 0 && result[3] > 0);
}
#[test]
fn schema_enforces_depth_work_scratch_nodes_and_cycles_as_operational_errors() {
    let exe = executable("model");
    let mut cases = Vec::new();
    let mut wants = Vec::new();
    for (s, i, stage, error) in [
        (r##"{"$ref":"#"}"##, "0", 3, 11),
        (
            r##"{"$defs":{"x":{"$ref":"#"}},"$ref":"#/$defs/x"}"##,
            "0",
            3,
            11,
        ),
        (r##"{"anyOf":[{"$ref":"#"},true]}"##, "0", 3, 11),
        (r##"{"not":{"$ref":"#"}}"##, "0", 3, 11),
        (r##"{"if":{"$ref":"#"},"then":true}"##, "0", 3, 11),
        (r##"{"contains":{"$ref":"#"}}"##, "[[]]", 1, 0),
    ] {
        cases.push(Case::new(s, i));
        wants.push((stage, error));
    }
    let mut c = Case::new("true", "0");
    c.nodes = 0;
    cases.push(c);
    wants.push((2, 8));
    let mut c = Case::new("true", "0");
    c.nodes = -1;
    cases.push(c);
    wants.push((2, 2));
    let mut c = Case::new("true", "0");
    c.sd = 129;
    cases.push(c);
    wants.push((2, 2));
    let mut c = Case::new("true", "0");
    c.vd = -1;
    cases.push(c);
    wants.push((2, 2));
    let mut c = Case::new(r#"{"$defs":{"unused":true}}"#, "0");
    c.sd = 0;
    cases.push(c);
    wants.push((2, 9));
    let mut c = Case::new(r#"{"items":true}"#, "[0]");
    c.vd = 0;
    cases.push(c);
    wants.push((3, 9));
    let mut c = Case::new(r#"{"const":[[[0]]]}"#, "[[[0]]]");
    c.vd = 2;
    cases.push(c);
    wants.push((3, 9));
    let mut c = Case::new("true", "0");
    c.work = 0;
    cases.push(c);
    wants.push((2, 10));
    let mut c = Case::new("true", "[0,1,2,3,4,5,6,7,8,9]");
    c.work = 10;
    cases.push(c);
    wants.push((3, 10));
    let mut c = Case::new(r#"{"multipleOf":3}"#, "6");
    c.scratch = 0;
    cases.push(c);
    wants.push((3, 12));
    for (index, (r, want)) in run(&exe, &cases).into_iter().zip(wants).enumerate() {
        assert_eq!(
            (r[0], if r[0] <= 1 { 0 } else { r[1] }),
            want,
            "case {index}: {} / {} => {r:?}",
            cases[index].schema,
            cases[index].instance
        );
    }
    for length in [127, 128, 129] {
        let defs = (0..length)
            .map(|n| {
                if n + 1 == length {
                    format!(r#""n{n}":true"#)
                } else {
                    format!(r##""n{n}":{{"$ref":"#/$defs/n{}"}}"##, n + 1)
                }
            })
            .collect::<Vec<_>>()
            .join(",");
        let mut c = Case::new(
            format!(r##"{{"$defs":{{{defs}}},"$ref":"#/$defs/n0"}}"##),
            "null",
        );
        c.vd = 128;
        let r = run(&exe, &[c])[0];
        if length <= 128 {
            assert_eq!(r[0], 0, "chain {length}: {r:?}");
        } else {
            assert_eq!((r[0], r[1]), (3, 9), "chain {length}: {r:?}");
        }
    }
    // Reusing exactly the reported successful validation work must succeed;
    // one fewer unit must return WorkLimit, including numeric digit work.
    let mut c = Case::new(
        r#"{"uniqueItems":true,"items":{"multipleOf":3}}"#,
        "[3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57,60]",
    );
    let r = run(&exe, &[c.clone()])[0];
    assert_eq!(r[0], 0);
    let work = (r[5] as u32 as u64) | ((r[6] as u32 as u64) << 32);
    c.work = work;
    assert_eq!(run(&exe, &[c.clone()])[0][0], 0);
    c.work -= 1;
    let r = run(&exe, &[c])[0];
    assert_eq!((r[0], r[1]), (3, 10));
    // A long string or long numeric token cannot evade a small work limit.
    let mut c = Case::new(
        r#"{"maxLength":999999}"#,
        serde_json::to_string(&"a".repeat(20000)).unwrap(),
    );
    c.work = 10000;
    let mut d = Case::new(r#"{"type":"integer"}"#, format!("1e{}", "9".repeat(10000)));
    d.work = 100000;
    for r in run(&exe, &[c, d]) {
        assert_eq!((r[0], r[1]), (3, 10));
    }
}
fn assert_heap_balanced(trace: &str) {
    let mut live = std::collections::HashSet::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") && !line.contains(" = -1 ") {
            let address = line
                .split(" = ")
                .nth(1)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap()
                .to_owned();
            assert!(live.insert(address), "mapping reused before free: {line}");
        }
        if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(live.remove(address), "unowned or double free: {line}");
            assert!(line.ends_with("= 0"), "{line}");
        }
    }
    assert!(live.is_empty(), "leaked mappings: {live:?}");
}
#[test]
fn schema_validation_is_allocation_free_on_strided_scratch_and_compilation_cleans_failed_allocations()
 {
    let trace = common::TempArtifact::new("laniusc_schema", "trace", None);
    let exe = executable("contracts");
    let output = common::process_output_with_timeout(
        "schema contracts trace",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"])
            .arg(exe.path()),
        Duration::from_secs(15),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stderr, b"ABCD");
    assert!(output.stdout.is_empty());
    let text = std::fs::read_to_string(trace.path()).unwrap();
    assert_heap_balanced(&text);
    let validation = text
        .split("write(2, \"B\"")
        .nth(1)
        .unwrap()
        .split("write(2, \"C\"")
        .next()
        .unwrap();
    assert!(
        !validation.contains("mmap(") && !validation.contains("munmap("),
        "{validation}"
    );
    let indexes = text
        .split("write(2, \"A\"")
        .nth(1)
        .unwrap()
        .split("write(2, \"B\"")
        .next()
        .unwrap();
    assert_eq!(
        indexes.lines().filter(|l| l.starts_with("mmap(")).count(),
        2,
        "{indexes}"
    );
    let fault = executable("allocation_failure");
    let baseline = common::process_output_with_timeout(
        "schema allocation baseline",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"])
            .arg(fault.path()),
        Duration::from_secs(5),
    );
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    assert_eq!(baseline.stderr, b"ABC");
    let text = std::fs::read_to_string(trace.path()).unwrap();
    assert_heap_balanced(&text);
    let count = text.lines().filter(|l| l.starts_with("mmap(")).count();
    assert_eq!(count, 4, "{text}");
    for nth in 1..=count {
        let output = common::process_output_with_timeout(
            "schema mmap failure",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap,write",
                    "-e",
                    &format!("inject=mmap:error=ENOMEM:when={nth}"),
                ])
                .arg(fault.path()),
            Duration::from_secs(5),
        );
        assert_eq!(output.status.code(), Some(0), "fault {nth}: {output:?}");
        assert!(output.stdout.is_empty());
        let text = std::fs::read_to_string(trace.path()).unwrap();
        assert!(text.contains("INJECTED"), "fault {nth}: {text}");
        assert_heap_balanced(&text);
        if nth > 2 {
            assert_eq!(output.stderr, b"AF", "fault {nth}");
        }
    }
}
#[test]
fn schema_large_batches_preserve_mathematical_uniqueness_and_global_work_limit() {
    let exe = executable("model");
    let array = format!(
        "[{}]",
        (0..12000)
            .map(|n| format!("{}", n * 3))
            .collect::<Vec<_>>()
            .join(",")
    );
    let mut c = Case::new(
        r#"{"type":"array","minItems":12000,"maxItems":12000,"items":{"type":"integer","multipleOf":3}}"#,
        array,
    );
    c.work = 250_000_000;
    let r = run(&exe, &[c])[0];
    assert_eq!(r[0], 0, "{r:?}");
    assert!(r[5] > 100000);
    // Distinct large objects compare unordered; a late duplicate with differently
    // ordered keys and numeric spelling must still invalidate uniqueItems.
    let mut values = (0..300)
        .map(|n| format!(r#"{{"a":{n},"b":[{n},true]}}"#))
        .collect::<Vec<_>>();
    values.push(r#"{"b":[299.0,true],"a":299e0}"#.to_owned());
    let mut c = Case::new(r#"{"uniqueItems":true}"#, format!("[{}]", values.join(",")));
    c.work = 500_000_000;
    let r = run(&exe, &[c])[0];
    assert_eq!((r[0], r[1]), (1, 13));
}
