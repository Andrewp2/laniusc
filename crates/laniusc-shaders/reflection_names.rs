//! Top-level binding names of a Slang reflection JSON file.
//!
//! The runtime binds every reflected parameter by name, so a kernel whose
//! reflection lists two bindings with one name cannot be bound: the
//! type-check graph refuses it, and every program then fails with LNC0047
//! before any dispatch. This happens when a kernel redeclares a global that a
//! module it imports also declares. The build checks every kernel with
//! `duplicate_binding_names`.
//!
//! The parser below reads only what reflection JSON needs (objects, arrays,
//! strings, numbers, true, false and null), so the build script has no JSON
//! dependency.

use anyhow::{Result, anyhow};

enum Json {
    Scalar,
    Str(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Object(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
            _ => None,
        }
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Parser<'_> {
    fn error(&self, what: &str) -> anyhow::Error {
        anyhow!("reflection JSON: {what} at byte {}", self.at)
    }

    fn skip_space(&mut self) {
        while self.at < self.bytes.len() && self.bytes[self.at].is_ascii_whitespace() {
            self.at += 1;
        }
    }

    fn expect(&mut self, byte: u8) -> Result<()> {
        self.skip_space();
        if self.bytes.get(self.at) != Some(&byte) {
            return Err(self.error(&format!("expected {:?}", byte as char)));
        }
        self.at += 1;
        Ok(())
    }

    fn value(&mut self) -> Result<Json> {
        self.skip_space();
        match self.bytes.get(self.at) {
            Some(b'{') => {
                self.at += 1;
                let mut fields = Vec::new();
                self.skip_space();
                if self.bytes.get(self.at) == Some(&b'}') {
                    self.at += 1;
                    return Ok(Json::Object(fields));
                }
                loop {
                    self.skip_space();
                    let key = self.string()?;
                    self.expect(b':')?;
                    fields.push((key, self.value()?));
                    self.skip_space();
                    match self.bytes.get(self.at) {
                        Some(b',') => self.at += 1,
                        Some(b'}') => {
                            self.at += 1;
                            return Ok(Json::Object(fields));
                        }
                        _ => return Err(self.error("expected ',' or '}'")),
                    }
                }
            }
            Some(b'[') => {
                self.at += 1;
                let mut items = Vec::new();
                self.skip_space();
                if self.bytes.get(self.at) == Some(&b']') {
                    self.at += 1;
                    return Ok(Json::Array(items));
                }
                loop {
                    items.push(self.value()?);
                    self.skip_space();
                    match self.bytes.get(self.at) {
                        Some(b',') => self.at += 1,
                        Some(b']') => {
                            self.at += 1;
                            return Ok(Json::Array(items));
                        }
                        _ => return Err(self.error("expected ',' or ']'")),
                    }
                }
            }
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(_) => {
                let start = self.at;
                while self.at < self.bytes.len()
                    && (self.bytes[self.at].is_ascii_alphanumeric()
                        || matches!(self.bytes[self.at], b'-' | b'+' | b'.'))
                {
                    self.at += 1;
                }
                let word = &self.bytes[start..self.at];
                let number = word
                    .first()
                    .is_some_and(|b| b.is_ascii_digit() || *b == b'-');
                if number || matches!(word, b"true" | b"false" | b"null") {
                    Ok(Json::Scalar)
                } else {
                    Err(self.error("expected a value"))
                }
            }
            None => Err(self.error("unexpected end")),
        }
    }

    fn string(&mut self) -> Result<String> {
        if self.bytes.get(self.at) != Some(&b'"') {
            return Err(self.error("expected a string"));
        }
        self.at += 1;
        let mut out = Vec::new();
        loop {
            match self.bytes.get(self.at) {
                Some(b'"') => {
                    self.at += 1;
                    return String::from_utf8(out).map_err(|_| self.error("invalid UTF-8"));
                }
                Some(b'\\') => {
                    let escaped = *self
                        .bytes
                        .get(self.at + 1)
                        .ok_or_else(|| self.error("unexpected end"))?;
                    self.at += 2;
                    match escaped {
                        b'u' => {
                            let hex = self
                                .bytes
                                .get(self.at..self.at + 4)
                                .and_then(|hex| std::str::from_utf8(hex).ok())
                                .and_then(|hex| u32::from_str_radix(hex, 16).ok())
                                .ok_or_else(|| self.error("bad \\u escape"))?;
                            self.at += 4;
                            let ch = char::from_u32(hex).unwrap_or('\u{fffd}');
                            out.extend_from_slice(ch.to_string().as_bytes());
                        }
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        other => out.push(other),
                    }
                }
                Some(&byte) => {
                    out.push(byte);
                    self.at += 1;
                }
                None => return Err(self.error("unterminated string")),
            }
        }
    }
}

/// Names that two or more top-level reflected parameters with a binding
/// share, sorted.
pub fn duplicate_binding_names(json: &str) -> Result<Vec<String>> {
    let mut parser = Parser {
        bytes: json.as_bytes(),
        at: 0,
    };
    let root = parser.value()?;
    parser.skip_space();
    if parser.at != parser.bytes.len() {
        return Err(parser.error("trailing data"));
    }
    let Some(Json::Array(parameters)) = root.get("parameters") else {
        return Ok(Vec::new());
    };
    let mut seen = std::collections::HashSet::new();
    let mut duplicates = std::collections::BTreeSet::new();
    for parameter in parameters {
        let bound = parameter.get("binding").is_some() || parameter.get("bindings").is_some();
        if let (true, Some(Json::Str(name))) = (bound, parameter.get("name")) {
            if !seen.insert(name.as_str()) {
                duplicates.insert(name.clone());
            }
        }
    }
    Ok(duplicates.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::duplicate_binding_names;

    #[test]
    fn a_name_bound_twice_is_reported_once() {
        let json = r#"{
            "parameters": [
                {"name": "gParams", "binding": {"kind": "descriptorTableSlot", "index": 0},
                 "type": {"kind": "constantBuffer", "elementType": {"kind": "struct", "fields": [
                    {"name": "n", "type": {"kind": "scalar", "scalarType": "uint32"},
                     "binding": {"kind": "uniform", "offset": 0, "size": 4}}]}}},
                {"name": "rows", "binding": {"kind": "descriptorTableSlot", "index": 1}},
                {"name": "total", "binding": {"kind": "descriptorTableSlot", "index": 2}},
                {"name": "rows", "binding": {"kind": "descriptorTableSlot", "index": 3}},
                {"name": "rows", "bindings": [{"kind": "descriptorTableSlot", "index": 4}]},
                {"name": "unbound", "type": {"kind": "scalar"}},
                {"name": "unbound", "type": {"kind": "scalar"}}
            ],
            "entryPoints": [{"name": "main", "stage": "compute", "threadGroupSize": [256, 1, 1],
                             "note": "escaped \"quote\" and \u0041 and -1.5e3"}]
        }"#;
        assert_eq!(
            duplicate_binding_names(json).unwrap(),
            vec!["rows".to_string()]
        );
    }

    #[test]
    fn distinct_names_and_nested_field_names_are_not_duplicates() {
        // Struct fields named like a top-level binding are not bindings.
        let json = r#"{"parameters": [
            {"name": "gParams", "binding": {"kind": "descriptorTableSlot", "index": 0},
             "type": {"kind": "constantBuffer", "elementType": {"kind": "struct", "fields": [
                {"name": "rows", "binding": {"kind": "uniform", "offset": 0, "size": 4}}]}}},
            {"name": "rows", "binding": {"kind": "descriptorTableSlot", "index": 1}}
        ]}"#;
        assert!(duplicate_binding_names(json).unwrap().is_empty());
        assert!(duplicate_binding_names("{}").unwrap().is_empty());
    }

    #[test]
    fn malformed_json_is_an_error() {
        assert!(duplicate_binding_names(r#"{"parameters": [}"#).is_err());
        assert!(duplicate_binding_names(r#"{"parameters": []} x"#).is_err());
    }
}
