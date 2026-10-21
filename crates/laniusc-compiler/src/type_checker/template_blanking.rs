//! Declarations-only instance templates. A copy replay checks the template
//! text with its instance copies appended, but codegen covers only the
//! copies, so the template's function bodies are dead weight in that run.
//! With `TemplateBlanking` the replay checks the template with every
//! eligible body's interior blanked: the bytes strictly between its braces
//! become spaces (newlines stay), so every byte offset, and with it every
//! diagnostic position, is unchanged.
//!
//! Blanking does shift token indices and HIR rows: a body keeps its `{`,
//! `}` and block row, and loses its interior tokens and rows. Checked
//! identities of the template unit name tokens (private callables,
//! source-local nominals and binders) and rows (methods, owners, calls), so
//! the replay runs in "copy space" and its results are converted back to
//! the template's "full space". Both maps are exact prefix sums over the
//! bodies' interiors. A full-space token or row inside a blanked interior
//! has no copy-space image, which is an error.
//!
//! The host role is mechanical: the body spans come from the GPU's own
//! check of the template (kernel 04_owner_spans), and the maps only shift
//! numbers by those spans.

use anyhow::{Result, anyhow, ensure};

use super::{
    CheckedBodySpan,
    checked_contracts::{CheckedCallOwner, CheckedUnitContracts},
    generic_calls::{
        CheckedBinderIdentity,
        CheckedGenericApplicationArgument,
        CheckedGenericCall,
        CheckedGenericConstantValue,
        CheckedGenericParameter,
        CheckedGenericTarget,
        CheckedGenericType,
        CheckedNominalIdentity,
    },
};

const INVALID: u32 = u32::MAX;

/// One blanked body in full space, with the interiors removed before it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct BlankedBody {
    open_token: u32,
    close_token: u32,
    block_hir: u32,
    subtree_end: u32,
    open_byte: u32,
    close_byte: u32,
    tokens_before: u32,
    rows_before: u32,
}

impl BlankedBody {
    fn copy_open_token(&self) -> u32 {
        self.open_token - self.tokens_before
    }
    fn copy_block_hir(&self) -> u32 {
        self.block_hir - self.rows_before
    }
    fn tokens_through(&self) -> u32 {
        self.tokens_before + (self.close_token - self.open_token - 1)
    }
    fn rows_through(&self) -> u32 {
        self.rows_before + (self.subtree_end - self.block_hir - 1)
    }
}

/// The bodies a declarations-only template leaves out, for one template
/// unit, and the token and row maps between its full and copy spaces.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct TemplateBlanking {
    unit: [u32; 2],
    bodies: Vec<BlankedBody>,
}

/// Which way a `TemplateIdentityMap` converts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum BlankingDirection {
    ToCopy,
    ToFull,
}

impl TemplateBlanking {
    /// Blank `bodies` (source order, disjoint; from the template's own
    /// check) of template `unit`, except bodies that hold a row the
    /// template's checked contracts name: a declaration nested in a body
    /// keeps its body. Bodies holding string literals are blanked too: a copy
    /// replay's rodata starts at the first copy string, so the template's own
    /// strings never reach it. None when nothing is left to blank.
    pub(crate) fn new(
        unit: [u32; 2],
        bodies: &[CheckedBodySpan],
        contracts: &CheckedUnitContracts,
    ) -> Result<Option<Self>> {
        ensure!(bodies.windows(2).all(|pair| pair[0].subtree_end <= pair[1].block_hir
            && pair[0].close_token < pair[1].open_token && pair[0].close_byte < pair[1].open_byte),
            "template bodies are not disjoint and in source order");
        let mut named = contract_rows(contracts);
        named.sort_unstable();
        named.dedup();
        let mut blanked = Vec::with_capacity(bodies.len());
        let (mut tokens, mut rows) = (0u32, 0u32);
        for body in bodies {
            ensure!(body.block_hir < body.subtree_end && body.open_token < body.close_token
                && body.open_byte < body.close_byte, "malformed template body span");
            let interior = named.partition_point(|&row| row <= body.block_hir);
            if named.get(interior).is_some_and(|&row| row < body.subtree_end) {
                continue;
            }
            let (interior_tokens, interior_rows) = (body.interior_tokens(), body.interior_rows());
            if interior_tokens == 0 && interior_rows == 0 {
                continue;
            }
            blanked.push(BlankedBody {
                open_token: body.open_token,
                close_token: body.close_token,
                block_hir: body.block_hir,
                subtree_end: body.subtree_end,
                open_byte: body.open_byte,
                close_byte: body.close_byte,
                tokens_before: tokens,
                rows_before: rows,
            });
            tokens = tokens.checked_add(interior_tokens).ok_or_else(|| anyhow!("blanked token count overflows"))?;
            rows = rows.checked_add(interior_rows).ok_or_else(|| anyhow!("blanked row count overflows"))?;
        }
        Ok((!blanked.is_empty()).then_some(Self { unit, bodies: blanked }))
    }

    pub(crate) fn unit(&self) -> [u32; 2] {
        self.unit
    }

    pub(crate) fn body_count(&self) -> usize {
        self.bodies.len()
    }

    /// Tokens and rows the blanked template leaves out.
    pub(crate) fn removed(&self) -> (u32, u32) {
        self.bodies.last().map_or((0, 0), |body| (body.tokens_through(), body.rows_through()))
    }

    /// The template sources with every blanked interior's bytes replaced by
    /// spaces, newlines kept: the same length and the same line breaks.
    /// Each body's braces must be where the template's check found them.
    pub(crate) fn blank_sources(&self, template: &[String]) -> Result<Vec<String>> {
        let mut bytes = template.iter().map(|source| source.as_bytes().to_vec()).collect::<Vec<_>>();
        let mut file_starts = Vec::with_capacity(template.len());
        let mut start = 0usize;
        for source in template {
            file_starts.push(start);
            start += source.len();
        }
        for body in &self.bodies {
            let (open, close) = (body.open_byte as usize, body.close_byte as usize);
            let file = file_starts.partition_point(|&file_start| file_start <= open)
                .checked_sub(1).ok_or_else(|| anyhow!("template body precedes the source"))?;
            let (local_open, local_close) = (open - file_starts[file], close.wrapping_sub(file_starts[file]));
            let source = &mut bytes[file];
            ensure!(local_close < source.len() && source[local_open] == b'{' && source[local_close] == b'}',
                "a template body's braces are not in one file where its check found them");
            for byte in &mut source[local_open + 1..local_close] {
                if *byte != b'\n' {
                    *byte = b' ';
                }
            }
        }
        // Every replaced byte is ASCII now and newlines are untouched, so a
        // multibyte character is either kept whole or blanked whole.
        bytes.into_iter()
            .map(|source| String::from_utf8(source).map_err(|_| anyhow!("blanked template is not UTF-8")))
            .collect()
    }

    pub(crate) fn map(&self, direction: BlankingDirection) -> TemplateIdentityMap<'_> {
        TemplateIdentityMap { blanking: self, direction }
    }

    fn token_to_copy(&self, token: u32) -> Result<u32> {
        // Bodies whose `}` is at or before the token are wholly before it.
        let index = self.bodies.partition_point(|body| body.close_token <= token);
        if let Some(body) = self.bodies.get(index) {
            ensure!(token <= body.open_token, "token {token} is inside a blanked template body");
        }
        Ok(token - index.checked_sub(1).map_or(0, |before| self.bodies[before].tokens_through()))
    }

    fn token_to_full(&self, token: u32) -> u32 {
        // Bodies whose copy-space `{` is before the token are before it.
        let index = self.bodies.partition_point(|body| body.copy_open_token() < token);
        token + index.checked_sub(1).map_or(0, |before| self.bodies[before].tokens_through())
    }

    fn row_to_copy(&self, row: u32) -> Result<u32> {
        let index = self.bodies.partition_point(|body| body.subtree_end <= row);
        if let Some(body) = self.bodies.get(index) {
            ensure!(row <= body.block_hir, "HIR row {row} is inside a blanked template body");
        }
        Ok(row - index.checked_sub(1).map_or(0, |before| self.bodies[before].rows_through()))
    }

    fn row_to_full(&self, row: u32) -> u32 {
        let index = self.bodies.partition_point(|body| body.copy_block_hir() < row);
        row + index.checked_sub(1).map_or(0, |before| self.bodies[before].rows_through())
    }
}

/// Rows of the template that its checked contracts name, which a blanked
/// body must not hold.
fn contract_rows(contracts: &CheckedUnitContracts) -> Vec<u32> {
    let mut rows = Vec::new();
    rows.extend(contracts.binders.iter().map(|owner| owner.source_hir));
    rows.extend(contracts.nominal_recipes.iter().map(|recipe| recipe.source_hir));
    rows.extend(contracts.predicates.iter().map(|predicate| predicate.bound_hir));
    for implementation in &contracts.implementations {
        rows.extend(implementation.method_bindings.iter().map(|binding| binding.method_hir));
    }
    rows.retain(|&row| row != INVALID);
    rows
}

/// Converts the template unit's checked identities between full and copy
/// space. Identities of other units are left alone. A unit of
/// [INVALID; 2] is this unit before scoping.
#[derive(Clone, Copy)]
pub(crate) struct TemplateIdentityMap<'a> {
    blanking: &'a TemplateBlanking,
    direction: BlankingDirection,
}

impl TemplateIdentityMap<'_> {
    pub(crate) fn local(&self, unit: [u32; 2]) -> bool {
        unit == self.blanking.unit || unit == [INVALID; 2]
    }

    pub(crate) fn token(&self, token: u32) -> Result<u32> {
        if token == INVALID {
            return Ok(token);
        }
        match self.direction {
            BlankingDirection::ToCopy => self.blanking.token_to_copy(token),
            BlankingDirection::ToFull => Ok(self.blanking.token_to_full(token)),
        }
    }

    pub(crate) fn row(&self, row: u32) -> Result<u32> {
        if row == INVALID {
            return Ok(row);
        }
        match self.direction {
            BlankingDirection::ToCopy => self.blanking.row_to_copy(row),
            BlankingDirection::ToFull => Ok(self.blanking.row_to_full(row)),
        }
    }

    /// A unit-local callable symbol (callable_identity.slang): a public
    /// declaration index is stable, `0x80000000 | method HIR` names a row
    /// and `0x40000000 | token` a private callable's first token.
    pub(crate) fn symbol(&self, symbol: u32) -> Result<u32> {
        if symbol == INVALID {
            Ok(symbol)
        } else if symbol & 0x8000_0000 != 0 {
            let row = self.row(symbol & 0x7fff_ffff)?;
            ensure!(row < 0x8000_0000, "remapped method symbol overflows");
            Ok(0x8000_0000 | row)
        } else if symbol & 0x4000_0000 != 0 {
            let token = self.token(symbol & 0x3fff_ffff)?;
            ensure!(token < 0x4000_0000, "remapped private callable symbol overflows");
            Ok(0x4000_0000 | token)
        } else {
            Ok(symbol)
        }
    }

    /// A unit-qualified native symbol (library, unit, symbol).
    pub(crate) fn qualified_symbol(&self, identity: &mut [u32; 3]) -> Result<()> {
        if self.local([identity[0], identity[1]]) {
            identity[2] = self.symbol(identity[2])?;
        }
        Ok(())
    }

    pub(crate) fn nominal(&self, identity: &mut CheckedNominalIdentity) -> Result<()> {
        if let CheckedNominalIdentity::SourceLocal { unit, declaration_token } = identity
            && self.local(*unit)
        {
            *declaration_token = self.token(*declaration_token)?;
        }
        Ok(())
    }

    /// A binder of this unit.
    pub(crate) fn binder(&self, binder: &mut CheckedBinderIdentity) -> Result<()> {
        match binder {
            CheckedBinderIdentity::Public { scope, .. } => {
                // 0, or `0x80000000 | fn HIR` / `0xc0000000 | HIR` of an
                // exported owner's lexical scope.
                let class = *scope & 0xc000_0000;
                if class & 0x8000_0000 != 0 {
                    let row = self.row(*scope & 0x3fff_ffff)?;
                    ensure!(row < 0x4000_0000, "remapped binder scope overflows");
                    *scope = class | row;
                }
            }
            CheckedBinderIdentity::SourceLocal { declaration_start_token, .. } => {
                *declaration_start_token = self.token(*declaration_start_token)?;
            }
        }
        Ok(())
    }

    pub(crate) fn parameter(&self, parameter: &mut CheckedGenericParameter) -> Result<()> {
        if self.local(parameter.identity.unit) {
            self.binder(&mut parameter.identity.binder)?;
        }
        Ok(())
    }

    pub(crate) fn ty(&self, ty: &mut CheckedGenericType) -> Result<()> {
        match ty {
            CheckedGenericType::Scalar(_) | CheckedGenericType::Unresolved { .. } => Ok(()),
            CheckedGenericType::Parameter(parameter) => self.parameter(parameter),
            CheckedGenericType::Slice(element) | CheckedGenericType::Reference(element) => self.ty(element),
            CheckedGenericType::Array { element, length, .. } => {
                self.ty(element)?;
                self.constant(length)
            }
            CheckedGenericType::Nominal { identity, arguments, local_replay, .. } => {
                // A `0x20000000 | token` replay anchor names a declaration
                // token of the identity's own unit; a `0x40000000 | code`
                // anchor is a type code, not a position.
                if let Some(anchor) = local_replay
                    && *anchor & 0xe000_0000 == 0x2000_0000
                    && self.local(identity.unit())
                {
                    let token = self.token(*anchor & 0x1fff_ffff)?;
                    ensure!(token < 0x2000_0000, "remapped nominal replay anchor overflows");
                    *anchor = 0x2000_0000 | token;
                }
                self.nominal(identity)?;
                arguments.iter_mut().try_for_each(|argument| self.argument(argument))
            }
        }
    }

    pub(crate) fn argument(&self, argument: &mut CheckedGenericApplicationArgument) -> Result<()> {
        match argument {
            CheckedGenericApplicationArgument::Type(ty) => self.ty(ty),
            CheckedGenericApplicationArgument::Constant(value) => self.constant(value),
        }
    }

    pub(crate) fn constant(&self, value: &mut CheckedGenericConstantValue) -> Result<()> {
        match value {
            CheckedGenericConstantValue::Parameter(parameter) => self.parameter(parameter),
            CheckedGenericConstantValue::CountProjection { source, .. } => self.constant(source),
            CheckedGenericConstantValue::Literal(_) | CheckedGenericConstantValue::Unresolved { .. } => Ok(()),
        }
    }

    pub(crate) fn target(&self, target: &mut CheckedGenericTarget) -> Result<()> {
        match target {
            CheckedGenericTarget::Local { function_start_token, native_symbol, specialization_symbol, .. } => {
                *function_start_token = self.token(*function_start_token)?;
                *native_symbol = self.symbol(*native_symbol)?;
                *specialization_symbol = self.symbol(*specialization_symbol)?;
            }
            // A bound member routed through an impl binding to another module
            // of this unit (methods/09) names it by this unit's symbol.
            CheckedGenericTarget::Dependency { library_id, unit_id, declaration_index }
                if self.local([*library_id, *unit_id]) =>
            {
                *declaration_index = self.symbol(*declaration_index)?;
            }
            CheckedGenericTarget::DependencyMethod { library_id, unit_id, method_symbol }
                if self.local([*library_id, *unit_id]) =>
            {
                *method_symbol = self.symbol(*method_symbol)?;
            }
            _ => {}
        }
        Ok(())
    }

    /// A call this unit checked.
    pub(crate) fn call(&self, call: &mut CheckedGenericCall) -> Result<()> {
        call.call_hir = self.row(call.call_hir)?;
        self.target(&mut call.target)?;
        for argument in &mut call.arguments {
            self.ty(&mut argument.ty)?;
        }
        for constant in &mut call.constants {
            self.constant(&mut constant.value)?;
        }
        Ok(())
    }

    pub(crate) fn call_owner(&self, owner: &mut CheckedCallOwner) -> Result<()> {
        owner.call_hir = self.row(owner.call_hir)?;
        owner.function_hir = self.row(owner.function_hir)?;
        Ok(())
    }

    /// This unit's own definition contracts. Table indices (owners,
    /// predicate and implementation rows) do not move: no contract row is
    /// inside a blanked body.
    pub(crate) fn contracts(&self, contracts: &mut CheckedUnitContracts) -> Result<()> {
        for owner in &mut contracts.binders {
            owner.source_hir = self.row(owner.source_hir)?;
            self.binder(&mut owner.binder)?;
            if let Some(callable) = &mut owner.callable {
                callable.native_symbol = self.symbol(callable.native_symbol)?;
            }
            for parameter in &mut owner.parameters {
                self.parameter(parameter)?;
            }
        }
        for predicate in &mut contracts.predicates {
            predicate.bound_hir = self.row(predicate.bound_hir)?;
            self.nominal(&mut predicate.trait_identity)?;
            self.ty(&mut predicate.subject)?;
            predicate.arguments.iter_mut().try_for_each(|argument| self.argument(argument))?;
        }
        for implementation in &mut contracts.implementations {
            let local_trait = self.local(implementation.trait_identity.unit());
            self.nominal(&mut implementation.trait_identity)?;
            self.ty(&mut implementation.subject)?;
            implementation.arguments.iter_mut().try_for_each(|argument| self.argument(argument))?;
            for binding in &mut implementation.method_bindings {
                binding.method_hir = self.row(binding.method_hir)?;
                if local_trait {
                    binding.required_symbol = self.symbol(binding.required_symbol)?;
                }
                self.qualified_symbol(&mut binding.target)?;
            }
        }
        for recipe in &mut contracts.nominal_recipes {
            recipe.source_hir = self.row(recipe.source_hir)?;
            self.nominal(&mut recipe.identity)?;
            for group in &mut recipe.groups {
                group.iter_mut().try_for_each(|ty| self.ty(ty))?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body(block_hir: u32, subtree_end: u32, open_token: u32, close_token: u32, open_byte: u32, close_byte: u32) -> CheckedBodySpan {
        CheckedBodySpan { function_hir: block_hir - 1, block_hir, subtree_end, open_token, close_token, open_byte, close_byte }
    }

    fn blanking() -> TemplateBlanking {
        // Two bodies: tokens 10..20 (9 inside), rows 5..12 (6 inside);
        // tokens 30..33 (2 inside), rows 20..24 (3 inside).
        TemplateBlanking::new([0, 1], &[body(5, 12, 10, 20, 100, 200), body(20, 24, 30, 33, 300, 340)],
            &CheckedUnitContracts::default()).unwrap().unwrap()
    }

    #[test]
    fn token_and_row_maps_are_inverse_prefix_sums() {
        let blanking = blanking();
        assert_eq!(blanking.removed(), (11, 9));
        let (to_copy, to_full) = (blanking.map(BlankingDirection::ToCopy), blanking.map(BlankingDirection::ToFull));
        for token in (0..=10).chain(20..=30).chain(33..60) {
            let copy = to_copy.token(token).unwrap();
            assert_eq!(to_full.token(copy).unwrap(), token, "token {token}");
        }
        assert_eq!(to_copy.token(20).unwrap(), 11);
        assert_eq!(to_copy.token(33).unwrap(), 22);
        for token in (11..20).chain(31..33) {
            assert!(to_copy.token(token).is_err(), "token {token}");
        }
        for row in (0..=5).chain(12..=20).chain(24..40) {
            let copy = to_copy.row(row).unwrap();
            assert_eq!(to_full.row(copy).unwrap(), row, "row {row}");
        }
        assert_eq!(to_copy.row(12).unwrap(), 6);
        assert!(to_copy.row(6).is_err());
        assert_eq!(to_copy.symbol(0x4000_0000 | 33).unwrap(), 0x4000_0000 | 22);
        assert_eq!(to_copy.symbol(0x8000_0000 | 24).unwrap(), 0x8000_0000 | 15);
        assert_eq!(to_copy.symbol(7).unwrap(), 7);
        assert_eq!(to_copy.row(INVALID).unwrap(), INVALID);
    }

    #[test]
    fn blanking_keeps_bytes_lines_and_braces() {
        // A body holding a string literal is blanked like any other.
        let source = "fn a() -> u32 {\n    let s: str = \"é\";\n    return 1;\n}\nfn b() {}\n".to_string();
        let open = source.find('{').unwrap() as u32;
        let close = source.find("}\n").unwrap() as u32;
        let blanking = TemplateBlanking::new([0, 0], &[body(3, 9, 6, 11, open, close)],
            &CheckedUnitContracts::default()).unwrap().unwrap();
        let blanked = blanking.blank_sources(&[source.clone()]).unwrap();
        assert_eq!(blanked[0].len(), source.len());
        assert_eq!(blanked[0].matches('\n').count(), source.matches('\n').count());
        assert!(blanked[0].starts_with("fn a() -> u32 {\n"));
        assert!(blanked[0][open as usize + 1..close as usize].bytes().all(|byte| byte == b' ' || byte == b'\n'));
        assert!(blanked[0].ends_with("}\nfn b() {}\n"));
    }

    #[test]
    fn a_body_holding_a_contract_row_is_kept() {
        let mut contracts = CheckedUnitContracts::default();
        contracts.binders.push(super::super::checked_contracts::CheckedContractOwner {
            source_hir: 8,
            binder: CheckedBinderIdentity::SourceLocal { owner_kind: 3, declaration_start_token: 14 },
            callable: None,
            enclosing_owner: None,
            parameters: Vec::new(),
        });
        let blanking = TemplateBlanking::new([0, 1], &[body(5, 12, 10, 20, 100, 200), body(20, 24, 30, 33, 300, 340)],
            &contracts).unwrap().unwrap();
        assert_eq!(blanking.body_count(), 1);
        assert_eq!(blanking.removed(), (2, 3));
    }
}
