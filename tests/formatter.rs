use laniusc::formatter::format_source;

#[test]
fn formatter_formats_small_alpha_sample() {
    let source = "module app;import core::bool;pub fn choose(flag:bool,a:i32,b:i32)->i32{let value:i32=core::bool::choose_i32(flag,a,b);return value;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
module app;
import core::bool;
pub fn choose(flag: bool, a: i32, b: i32) -> i32 {
    let value: i32 = core::bool::choose_i32(flag, a, b);
    return value;
}
"
    );
}

#[test]
fn formatter_is_idempotent_for_alpha_slice() {
    let cases = [
        "fn main(){return 1;}",
        "fn pick(flag:bool)->i32{if flag{return 1;}else{return 0;}}",
        "module core::array;pub fn first(values:[i32;4])->i32{return values[0];}",
        "pub extern \"lanius_std\" fn open_read(path_ptr:u32,path_len:usize)->i32;",
        "fn comments(){// keep me\nlet x:i32=1;/* keep { me; } */return x;}",
        "fn neg(x:i32)->i32{let a:i32=10-3;let b:i32=-x;return-b;}",
    ];

    for source in cases {
        let once = format_source(source);
        let twice = format_source(&once);
        assert_eq!(once, twice, "formatter must be idempotent for {source:?}");
    }
}

#[test]
fn formatter_preserves_string_and_char_literal_contents() {
    let source =
        r#"fn literals(){let s:str="  {not code;} // still text  ";let c:char='\n';return 0;}"#;

    let formatted = format_source(source);

    assert!(formatted.contains(r#""  {not code;} // still text  ""#));
    assert!(formatted.contains(r#"'\n'"#));
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_keeps_boundary_block_comments_standalone() {
    let source = "fn comments(){/* before */if ready{/* inside */return 1;}/* after */let value:i32=/* inline */0;return value;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
fn comments() {
    /* before */
    if ready {
        /* inside */
        return 1;
    }
    /* after */
    let value: i32 = /* inline */ 0;
    return value;
}
"
    );
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_normalizes_crlf_after_line_comments() {
    let source = "fn main(){// keep comment text\r\nreturn 1;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
fn main() {
    // keep comment text
    return 1;
}
"
    );
    assert!(
        !formatted.contains('\r'),
        "formatted source should use LF line endings"
    );
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_distinguishes_unary_and_binary_minus() {
    let source =
        "fn main(){let diff:i32=10-3;let neg:i32=-diff;let both:i32=diff- -neg;return-neg;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
fn main() {
    let diff: i32 = 10 - 3;
    let neg: i32 = -diff;
    let both: i32 = diff - -neg;
    return -neg;
}
"
    );
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_formats_prefix_logical_not_after_keywords() {
    let source = "fn main(flag:bool)->bool{if!flag{return!!flag;}else{return flag!=false;}}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
fn main(flag: bool) -> bool {
    if !flag {
        return !!flag;
    } else {
        return flag != false;
    }
}
"
    );
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_places_where_clause_predicates_on_their_own_lines() {
    let source = "trait Rel<T>{pub fn related(left:T,right:T)->bool where T:Eq<T>;}fn keep<T,U>(left:T,right:U)->T where T:Rel<U>{return left;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
trait Rel<T> {
    pub fn related(left: T, right: T) -> bool
    where
        T: Eq<T>;
}
fn keep<T, U>(left: T, right: U) -> T
where
    T: Rel<U>
{
    return left;
}
"
    );
    assert_eq!(format_source(&formatted), formatted);
}

#[test]
fn formatter_places_brace_delimited_comma_items_on_separate_lines() {
    let source = "fn main(){let point:Point=Point{x:1,y:2};let value:i32=match key{1=>10,2=>20,_=>0};return value;}";

    let formatted = format_source(source);

    assert_eq!(
        formatted,
        "\
fn main() {
    let point: Point = Point {
        x: 1,
        y: 2
    };
    let value: i32 = match key {
        1 => 10,
        2 => 20,
        _ => 0
    };
    return value;
}
"
    );
    assert_eq!(format_source(&formatted), formatted);
}
