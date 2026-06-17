// src/bin/parse_gen_tables/grammar.rs

use super::*;

pub(super) fn parse_grammar(src: &str) -> Result<GrammarSpec> {
    let mut prods = Vec::new();
    let mut tag_counts: HashMap<String, usize> = HashMap::new();
    let mut start: Option<String> = None;

    for (line_number, raw_line) in src.lines().enumerate() {
        let line_number = line_number + 1;
        let line = strip_comment(raw_line).trim();
        if line.is_empty() {
            continue;
        }

        if let Some(rest) = line.strip_prefix("%start") {
            if start.is_some() {
                bail!("line {line_number}: duplicate %start directive");
            }
            let rest = rest.trim();
            if !rest.ends_with(';') {
                bail!("line {line_number}: %start directive must end with ';'");
            }
            let name = rest.trim_end_matches(';').trim();
            if !is_ident(name) {
                bail!("line {line_number}: invalid start nonterminal '{name}'");
            }
            start = Some(name.to_string());
            continue;
        }

        if !line.ends_with(';') {
            bail!("line {line_number}: production must end with ';'");
        }

        let Some((lhs_part, rhs_part0)) = line.split_once("->") else {
            bail!("line {line_number}: expected production with '->'");
        };
        let rhs_part = rhs_part0.trim_end_matches(';').trim();

        let lhs_part = lhs_part.trim();
        let (lhs_name, tag_base) = parse_lhs(lhs_part, line_number)?;

        let next_count = tag_counts.entry(tag_base.clone()).or_default();
        *next_count += 1;
        let tag = if *next_count == 1 {
            tag_base
        } else {
            format!("{tag_base}#{}", *next_count)
        };

        let mut rhs_syms = Vec::new();
        for tok in rhs_part.split_whitespace() {
            if tok.starts_with('\'') && tok.ends_with('\'') && tok.len() >= 2 {
                let terminal_name = tok.trim_matches('\'');
                let token = TokenKind::from_name(terminal_name).ok_or_else(|| {
                    anyhow!("line {line_number}: unknown terminal token kind '{terminal_name}'")
                })?;
                rhs_syms.push(Sym::Terminal(token as u32));
            } else if is_ident(tok) {
                rhs_syms.push(Sym::NonTerminal(tok.to_string()));
            } else {
                bail!("line {line_number}: invalid grammar symbol '{tok}'");
            }
        }

        prods.push(Production {
            line: line_number,
            lhs: lhs_name,
            tag,
            rhs_syms,
        });
    }

    let start = start
        .or_else(|| prods.first().map(|prod| prod.lhs.clone()))
        .ok_or_else(|| anyhow!("grammar contains no productions"))?;

    Ok(GrammarSpec {
        start,
        productions: prods,
    })
}

pub(super) fn strip_comment(line: &str) -> &str {
    line.split_once('#').map_or(line, |(before, _)| before)
}

pub(super) fn parse_lhs(lhs_part: &str, line_number: usize) -> Result<(String, String)> {
    let (lhs_name, tag_base) = if let Some((lhs, tag_part0)) = lhs_part.split_once('[') {
        let tag_part = tag_part0.trim();
        let Some(tag) = tag_part.strip_suffix(']') else {
            bail!("line {line_number}: production tag must end with ']'");
        };
        (lhs.trim(), tag.trim())
    } else {
        (lhs_part, lhs_part)
    };

    if !is_ident(lhs_name) {
        bail!("line {line_number}: invalid production lhs '{lhs_name}'");
    }
    if !is_ident(tag_base) {
        bail!("line {line_number}: invalid production tag '{tag_base}'");
    }

    Ok((lhs_name.to_string(), tag_base.to_string()))
}

pub(super) fn is_ident(s: &str) -> bool {
    let mut chars = s.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first == '_' || first.is_ascii_alphabetic())
        && chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
}
