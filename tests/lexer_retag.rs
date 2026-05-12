mod common;

use laniusc::lexer::{
    gpu::{GpuToken, driver::GpuLexer, util::read_tokens_from_mapped},
    tables::tokens::TokenKind,
    test_cpu::lex_on_test_cpu,
};

#[test]
fn test_cpu_lexer_oracle_retags_bool_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("let t = true; let f = false;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Let, LetIdent, LetAssign, True, Semicolon, Let, LetIdent, LetAssign, False, Semicolon,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_const_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("const LIMIT: i32 = 7;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Const, Ident, Colon, TypeIdent, Assign, Int, Semicolon]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_enum_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("enum Ordering { Less, Equal, Greater }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Enum, Ident, LBrace, Ident, Comma, Ident, Comma, Ident, RBrace
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_struct_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("struct VecHeader { len: i32 }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Struct, Ident, LBrace, Ident, Colon, TypeIdent, RBrace]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_impl_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("impl VecHeader { pub fn len() -> i32 { return 0; } }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Impl,
            Ident,
            LBrace,
            Pub,
            Fn,
            Ident,
            ParamLParen,
            ParamRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Int,
            Semicolon,
            RBrace,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_trait_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("trait Eq<T> { fn eq(left: T, right: T) -> bool; }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Trait,
            Ident,
            Lt,
            Ident,
            Gt,
            LBrace,
            Fn,
            Ident,
            ParamLParen,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamComma,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamRParen,
            Arrow,
            TypeIdent,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_splits_nested_generic_closers_in_type_contexts() {
    use TokenKind::*;

    let kinds =
        lex_on_test_cpu("fn same<T: Eq<T>>(left: T, right: T) -> bool { return left.eq(right); }")
            .expect("test CPU oracle lex")
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Fn,
            Ident,
            Lt,
            Ident,
            Colon,
            TypeIdent,
            Lt,
            Ident,
            Gt,
            Gt,
            GroupLParen,
            Ident,
            Colon,
            TypeIdent,
            Comma,
            Ident,
            Colon,
            TypeIdent,
            GroupRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Ident,
            Dot,
            Ident,
            CallLParen,
            Ident,
            CallRParen,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_splits_nested_generic_closers_after_multiple_bounds() {
    use TokenKind::*;

    let kinds =
        lex_on_test_cpu("fn key<T: Eq<T> + Hash<T>>(value: T) -> u32 { return value.hash(); }")
            .expect("test CPU oracle lex")
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Fn,
            Ident,
            Lt,
            Ident,
            Colon,
            TypeIdent,
            Lt,
            Ident,
            Gt,
            PrefixPlus,
            Ident,
            Lt,
            Ident,
            Gt,
            Gt,
            GroupLParen,
            Ident,
            Colon,
            TypeIdent,
            GroupRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Ident,
            Dot,
            Ident,
            CallLParen,
            CallRParen,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_for_in_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("for item in values { continue; }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![For, Ident, In, Ident, LBrace, Continue, Semicolon, RBrace]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_extern_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu(r#"pub extern "wasm" fn host_alloc(size: usize) -> u32;"#)
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Pub,
            Extern,
            String,
            Fn,
            Ident,
            ParamLParen,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamRParen,
            Arrow,
            TypeIdent,
            Semicolon,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_type_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("pub type Count = i32;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(kinds, vec![Pub, Type, Ident, Assign, Ident, Semicolon]);
}

#[test]
fn test_cpu_lexer_oracle_retags_where_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("fn keep<T>(value: T) -> T where T: Eq<T> { return value; }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert!(kinds.contains(&Where));
}

#[test]
fn test_cpu_lexer_oracle_retags_self_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("impl Range { fn start(self) -> i32 { return self.start; } }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Impl,
            Ident,
            LBrace,
            Fn,
            Ident,
            ParamLParen,
            SelfValue,
            ParamRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            SelfValue,
            Dot,
            Ident,
            Semicolon,
            RBrace,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_match_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("match (value) { _ -> value }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Match,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Ident,
            Arrow,
            TypeIdent,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_module_and_import_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("module core::i32; import core::bool; import \"stdlib/i32.lani\";")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Module, Ident, Colon, Colon, TypeIdent, Semicolon, Import, Ident, Colon, Colon,
            TypeIdent, Semicolon, Import, String, Semicolon,
        ]
    );
}

#[test]
fn gpu_lexer_emits_raw_local_syntax_tokens() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer local syntax tokens", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex("-a + +b - c f(a)[b] + [c] + (d)")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                Minus, Ident, Plus, Plus, Ident, Minus, Ident, Ident, LParen, Ident, RParen,
                LBracket, Ident, RBracket, Plus, LBracket, Ident, RBracket, Plus, LParen, Ident,
                RParen,
            ]
        );
    });
}

#[test]
fn gpu_lexer_retags_keywords() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex("module core::i32; import core::bool; import \"stdlib/i32.lani\"; extern \"wasm\" fn host_alloc(size: usize) -> u32; type Count = i32; struct VecHeader { len: i32 } impl VecHeader { fn len() -> i32 { return 0; } } trait Eq { fn eq(left: i32, right: i32) -> bool; } enum Ordering { Less, Equal, Greater } const LIMIT: i32 = 7; pub fn f() -> i32 { let x = 1; let t = true; let f = false; let m = match (x) { _ -> x }; for item in values { continue; } if (x) { return x; } else { while (x) { break; continue; } } }")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                Module, Ident, Colon, Colon, Ident, Semicolon, Import, Ident, Colon, Colon, Ident,
                Semicolon, Import, String, Semicolon, Extern, String, Fn, Ident, LParen, Ident,
                Colon, Ident, RParen, Arrow, Ident, Semicolon, Type, Ident, Assign, Ident,
                Semicolon, Struct, Ident, LBrace, Ident, Colon, Ident, RBrace, Impl, Ident, LBrace,
                Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Return, Int, Semicolon, RBrace,
                RBrace, Trait, Ident, LBrace, Fn, Ident, LParen, Ident, Colon, Ident, Comma, Ident,
                Colon, Ident, RParen, Arrow, Ident, Semicolon, RBrace, Enum, Ident, LBrace, Ident,
                Comma, Ident, Comma, Ident, RBrace, Const, Ident, Colon, Ident, Assign, Int,
                Semicolon, Pub, Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Let, Ident,
                Assign, Int, Semicolon, Let, Ident, Assign, True, Semicolon, Let, Ident, Assign,
                False, Semicolon, Let, Ident, Assign, Match, LParen, Ident, RParen, LBrace, Ident,
                Arrow, Ident, RBrace, Semicolon, For, Ident, In, Ident, LBrace, Continue,
                Semicolon, RBrace, If, LParen, Ident, RParen, LBrace, Return, Ident, Semicolon,
                RBrace, Else, LBrace, While, LParen, Ident, RParen, LBrace, Break, Semicolon,
                Continue, Semicolon, RBrace, RBrace, RBrace,
            ]
        );
    });
}

#[test]
fn gpu_lexer_records_single_source_token_file_ids_on_gpu() {
    common::block_on_gpu_with_timeout("GPU lexer single source token file ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let src = "module app::main; fn main() { return 0; }";
        let file_ids = lexer
            .with_resident_tokens(src, |device, queue, bufs| {
                let ids_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.token_file_id"),
                    size: bufs.token_file_id.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let count_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.token_count"),
                    size: 4,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });

                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("test.lexer.token_file_id.readback"),
                });
                encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
                encoder.copy_buffer_to_buffer(
                    &bufs.token_file_id,
                    0,
                    &ids_readback,
                    0,
                    bufs.token_file_id.byte_size as u64,
                );
                queue.submit(Some(encoder.finish()));

                let count_slice = count_readback.slice(..);
                count_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::Wait);
                let count_bytes = count_slice.get_mapped_range();
                let count = u32::from_le_bytes(count_bytes[0..4].try_into().unwrap()) as usize;
                drop(count_bytes);
                count_readback.unmap();

                let ids_slice = ids_readback.slice(0..(count * 4) as u64);
                ids_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::Wait);
                let ids_bytes = ids_slice.get_mapped_range();
                let ids = ids_bytes
                    .chunks_exact(4)
                    .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
                    .collect::<Vec<_>>();
                drop(ids_bytes);
                ids_readback.unmap();
                ids
            })
            .await
            .expect("resident lex");

        assert!(!file_ids.is_empty(), "fixture should produce tokens");
        assert!(
            file_ids.iter().all(|file_id| *file_id == 0),
            "single-source tokens should all be assigned to file 0: {file_ids:?}"
        );
    });
}

#[test]
fn gpu_lexer_records_source_pack_token_file_ids_on_gpu() {
    common::block_on_gpu_with_timeout("GPU lexer source pack token file ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let sources = [
            "module first; // comment without newline",
            "module second; import first; fn second() { return; }",
        ];
        let boundary = sources[0].len();
        let (tokens, file_ids) = lexer
            .with_resident_source_pack_tokens(&sources, |device, queue, bufs| {
                let tokens_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.tokens"),
                    size: bufs.tokens_out.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let ids_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.token_file_id"),
                    size: bufs.token_file_id.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let count_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.token_count"),
                    size: 4,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });

                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("test.lexer.source_pack.readback"),
                });
                encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
                encoder.copy_buffer_to_buffer(
                    &bufs.tokens_out,
                    0,
                    &tokens_readback,
                    0,
                    bufs.tokens_out.byte_size as u64,
                );
                encoder.copy_buffer_to_buffer(
                    &bufs.token_file_id,
                    0,
                    &ids_readback,
                    0,
                    bufs.token_file_id.byte_size as u64,
                );
                queue.submit(Some(encoder.finish()));

                let count_slice = count_readback.slice(..);
                count_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::Wait);
                let count_bytes = count_slice.get_mapped_range();
                let count = u32::from_le_bytes(count_bytes[0..4].try_into().unwrap()) as usize;
                drop(count_bytes);
                count_readback.unmap();

                let token_bytes_len = (count * std::mem::size_of::<GpuToken>()) as u64;
                let tokens_slice = tokens_readback.slice(0..token_bytes_len);
                tokens_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::Wait);
                let token_bytes = tokens_slice.get_mapped_range();
                let tokens =
                    read_tokens_from_mapped(&token_bytes, count).expect("source pack tokens");
                drop(token_bytes);
                tokens_readback.unmap();

                let ids_slice = ids_readback.slice(0..(count * 4) as u64);
                ids_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::Wait);
                let ids_bytes = ids_slice.get_mapped_range();
                let ids = ids_bytes
                    .chunks_exact(4)
                    .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
                    .collect::<Vec<_>>();
                drop(ids_bytes);
                ids_readback.unmap();
                (tokens, ids)
            })
            .await
            .expect("resident source pack lex");

        assert!(!tokens.is_empty(), "fixture should produce tokens");
        assert_eq!(tokens.len(), file_ids.len());
        assert!(
            file_ids.iter().any(|file_id| *file_id == 0)
                && file_ids.iter().any(|file_id| *file_id == 1),
            "source pack should produce token ids for both files: {file_ids:?}"
        );
        for (token, file_id) in tokens.iter().zip(file_ids.iter()) {
            let expected = if token.start < boundary { 0 } else { 1 };
            assert_eq!(
                *file_id, expected,
                "token at byte {} should belong to file {expected}",
                token.start
            );
            if *file_id == 0 {
                assert!(
                    token.start + token.len <= boundary,
                    "file 0 token should not span into file 1: start={} len={}",
                    token.start,
                    token.len
                );
            }
        }
    });
}

#[test]
fn gpu_lexer_retags_where_keyword() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer where keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex("where elsewhere").await.expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(kinds, vec![Where, Ident]);
    });
}

#[test]
fn gpu_lexer_retags_self_keyword() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer self keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex("self selfish").await.expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(kinds, vec![SelfValue, Ident]);
    });
}
