// src/main.rs
mod lexer;
mod reflection;

use lexer::gpu::lex_on_gpu;

fn main() {
    pollster::block_on(async {
        // A tiny sample covering identifiers, ints, comments, and symbols.
        let src = r#"
            foo = 12 + bar/* cmt */(7) // hello
            baz=3/*multi
            line*/+qux
        "#;

        match lex_on_gpu(src).await {
            Ok(tokens) => {
                println!("TOKENS:");
                for t in tokens {
                    let lexeme = &src.as_bytes()[t.start..t.start + t.len];
                    println!("{:?}  {:?}", t.kind, String::from_utf8_lossy(lexeme));
                }
            }
            Err(e) => eprintln!("lex error: {e:?}"),
        }
    });
}
