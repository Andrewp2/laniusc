"""Python json oracle for the streaming jq-lite program (ext::json_stream).

The reference is Python's json module made strict in the ways this library's
documented policy requires: input must decode as strict UTF-8, NaN/Infinity
are rejected, and any decoded lone surrogate rejects the document. Numbers
keep their source spelling and objects keep ordered duplicate pairs.

usage: oracle.py GROUP EXECUTABLE   (GROUP: suite, generated, mutations, paths, chunks, errors,
                                     bytewise and writer take json_stream_contracts)
"""
import json
import random
import subprocess
import sys

MAX_DEPTH = 512


class Number(str):
    """An unrounded source number token."""


class Object(list):
    """Ordered (key, value) pairs, duplicates retained."""


def reject_constant(value):
    raise ValueError(value)


def has_surrogate(text):
    return any(0xD800 <= ord(c) <= 0xDFFF for c in text)


def check(value, depth=0):
    if isinstance(value, Object):
        if depth + 1 > MAX_DEPTH:
            raise ValueError('depth')
        for key, child in value:
            if has_surrogate(key):
                raise ValueError('surrogate')
            check(child, depth + 1)
    elif isinstance(value, list):
        if depth + 1 > MAX_DEPTH:
            raise ValueError('depth')
        for child in value:
            check(child, depth + 1)
    elif isinstance(value, str) and not isinstance(value, Number):
        if has_surrogate(value):
            raise ValueError('surrogate')


def reference(data):
    """Return the parsed value, or raise ValueError when the input is invalid."""
    text = data.decode('utf-8')  # strict: rejects overlongs, encoded surrogates
    value = json.loads(text, parse_int=Number, parse_float=Number,
                       parse_constant=reject_constant, object_pairs_hook=Object)
    check(value)
    return value


def quoted(value):
    parts = ['"']
    for c in value:
        if c in ('"', '\\'):
            parts.append('\\' + c)
        elif ord(c) < 32:
            parts.append('\\u%04x' % ord(c))
        else:
            parts.append(c)
    parts.append('"')
    return ''.join(parts)


def render(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, Number):
        return str(value)
    if isinstance(value, str):
        return quoted(value)
    if isinstance(value, Object):
        return '{' + ','.join(quoted(k) + ':' + render(v) for k, v in value) + '}'
    return '[' + ','.join(render(v) for v in value) + ']'


def select(value, segments):
    if not segments:
        return [value]
    head, rest = segments[0], segments[1:]
    found = []
    if isinstance(head, str):
        if isinstance(value, Object):
            for key, child in value:
                if key == head:
                    found.extend(select(child, rest))
    elif isinstance(value, list) and not isinstance(value, Object) and head < len(value):
        found.extend(select(value[head], rest))
    return found


def path_text(segments):
    if not segments:
        return '.'
    out = []
    for s in segments:
        out.append('.' + s if isinstance(s, str) else '[%d]' % s)
    text = ''.join(out)
    return text if text.startswith('.') else '.' + text


def expected(data, segments):
    try:
        value = reference(data)
    except (ValueError, RecursionError):
        return None
    hits = select(value, segments)
    if not hits:
        return b'null\n'
    return ('\n'.join(render(h) for h in hits) + '\n').encode('utf-8')


def run(exe, data, path='.'):
    proc = subprocess.run([exe, path], input=data, capture_output=True, timeout=20)
    return proc.returncode, proc.stdout, proc.stderr


class Tally:
    def __init__(self, group):
        self.group, self.cases, self.agree, self.accepted, self.rejected, self.failures = group, 0, 0, 0, 0, []

    def compare(self, exe, name, data, segments=()):
        want = expected(data, list(segments))
        code, out, err = run(exe, data, path_text(list(segments)))
        self.cases += 1
        if want is None:
            ok = code == 2 and out == b'' and err.startswith(b'jq-lite: ')
            self.rejected += 1
        else:
            ok = code == 0 and out == want and err == b''
            self.accepted += 1
        if ok:
            self.agree += 1
        else:
            self.failures.append((name, data[:120], want, code, out[:200], err[:200]))

    def finish(self):
        print('jq-lite-%s cases=%d agree=%d accepted=%d rejected=%d' % (
            self.group, self.cases, self.agree, self.accepted, self.rejected))
        for failure in self.failures[:20]:
            print('MISMATCH', failure, file=sys.stderr)
        return 0 if not self.failures else 1


# JSONTestSuite-style cases written by hand: y_ must parse, n_ must not,
# i_ are implementation-defined and judged by the strict reference above.
SUITE = [
    ('y_array_empty', b'[]'), ('y_array_empty_string', b'[""]'), ('y_array_arraysWithSpaces', b'[[]   ]'),
    ('y_array_false', b'[false]'), ('y_array_heterogeneous', b'[null, 1, "1", {}]'), ('y_array_null', b'[null]'),
    ('y_array_with_1_and_newline', b'[1\n]'), ('y_array_with_leading_space', b' [1]'),
    ('y_array_with_several_null', b'[1,null,null,null,2]'), ('y_array_with_trailing_space', b'[2] '),
    ('y_number', b'[123e65]'), ('y_number_0e+1', b'[0e+1]'), ('y_number_0e1', b'[0e1]'),
    ('y_number_after_space', b'[ 4]'), ('y_number_double_close_to_zero', b'[-0.000000000000000000000000000000000000000000000000000000000000000000000000000001]'),
    ('y_number_int_with_exp', b'[20e1]'), ('y_number_minus_zero', b'[-0]'), ('y_number_negative_int', b'[-123]'),
    ('y_number_negative_one', b'[-1]'), ('y_number_negative_zero', b'[-0]'), ('y_number_real_capital_e', b'[1E22]'),
    ('y_number_real_capital_e_neg_exp', b'[1E-2]'), ('y_number_real_capital_e_pos_exp', b'[1E+2]'),
    ('y_number_real_exponent', b'[123e45]'), ('y_number_real_fraction_exponent', b'[123.456e78]'),
    ('y_number_real_neg_exp', b'[1e-2]'), ('y_number_real_pos_exponent', b'[1e+2]'), ('y_number_simple_int', b'[123]'),
    ('y_number_simple_real', b'[123.456789]'), ('y_number_bare', b'123'), ('y_number_huge_exp', b'[0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]'),
    ('y_number_very_big_negative_int', b'[-237462374673276894279832749832423479823246327846]'),
    ('y_object', b'{"asd":"sdf", "dfg":"fgh"}'), ('y_object_basic', b'{"asd":"sdf"}'),
    ('y_object_duplicated_key', b'{"a":"b","a":"c"}'), ('y_object_duplicated_key_and_value', b'{"a":"b","a":"b"}'),
    ('y_object_empty', b'{}'), ('y_object_empty_key', b'{"":0}'), ('y_object_escaped_null_in_key', b'{"foo\\u0000bar": 42}'),
    ('y_object_extreme_numbers', b'{ "min": -1.0e+28, "max": 1.0e+28 }'), ('y_object_long_strings', b'{"x":[{"id": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}], "id": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}'),
    ('y_object_simple', b'{"a":[]}'), ('y_object_string_unicode', b'{"title":"\\u041f\\u043e\\u043b\\u0442\\u043e\\u0440\\u0430 \\u0417\\u0435\\u043c\\u043b\\u0435\\u043a\\u043e\\u043f\\u0430" }'),
    ('y_object_with_newlines', b'{\n"a": "b"\n}'),
    ('y_string_1_2_3_bytes_UTF-8_sequences', b'["\\u0060\\u012a\\u12AB"]'), ('y_string_accepted_surrogate_pair', b'["\\uD801\\udc37"]'),
    ('y_string_accepted_surrogate_pairs', b'["\\ud83d\\ude39\\ud83d\\udc8d"]'), ('y_string_allowed_escapes', b'["\\"\\\\\\/\\b\\f\\n\\r\\t"]'),
    ('y_string_backslash_and_u_escaped_zero', b'["\\\\u0000"]'), ('y_string_backslash_doublequotes', b'["\\""]'),
    ('y_string_comments', b'["a/*b*/c/*d//e"]'), ('y_string_double_escape_a', b'["\\\\a"]'), ('y_string_double_escape_n', b'["\\\\n"]'),
    ('y_string_escaped_control_character', b'["\\u0012"]'), ('y_string_escaped_noncharacter', b'["\\uFFFF"]'),
    ('y_string_in_array', b'["asd"]'), ('y_string_in_array_with_leading_space', b'[ "asd"]'),
    ('y_string_last_surrogates_1_and_2', b'["\\uDBFF\\uDFFF"]'), ('y_string_nbsp_uescaped', b'["new\\u00A0line"]'),
    ('y_string_nonCharacterInUTF-8_U+10FFFF', b'["\xf4\x8f\xbf\xbf"]'), ('y_string_nonCharacterInUTF-8_U+FFFF', b'["\xef\xbf\xbf"]'),
    ('y_string_null_escape', b'["\\u0000"]'), ('y_string_one-byte-utf-8', b'["\\u002c"]'), ('y_string_pi', b'["\xcf\x80"]'),
    ('y_string_reservedCharacterInUTF-8_U+1BFFF', b'["\xf0\x9b\xbf\xbf"]'), ('y_string_simple_ascii', b'["asd "]'),
    ('y_string_space', b'" "'), ('y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF', b'["\\uD834\\uDd1e"]'),
    ('y_string_three-byte-utf-8', b'["\\u0821"]'), ('y_string_two-byte-utf-8', b'["\\u0123"]'),
    ('y_string_u+2028_line_sep', b'["\xe2\x80\xa8"]'), ('y_string_u+2029_par_sep', b'["\xe2\x80\xa9"]'),
    ('y_string_uEscape', b'["\\u0061\\u30af\\u30EA\\u30b9"]'), ('y_string_uescaped_newline', b'["new\\u000Aline"]'),
    ('y_string_unescaped_char_delete', b'["\x7f"]'), ('y_string_unicode', b'["\\uA66D"]'),
    ('y_string_unicodeEscapedBackslash', b'["\\u005C"]'), ('y_string_unicode_2', b'["\xe2\x8d\x82\xe3\x88\xb4\xe2\x8d\x82"]'),
    ('y_string_unicode_U+10FFFE_nonchar', b'["\\uDBFF\\uDFFE"]'), ('y_string_unicode_U+FDD0_nonchar', b'["\\uFDD0"]'),
    ('y_string_utf8', b'["\xe2\x82\xac\xf0\x9d\x84\x9e"]'), ('y_string_with_del_character', b'["a\x7fa"]'),
    ('y_structure_lonely_false', b'false'), ('y_structure_lonely_int', b'42'), ('y_structure_lonely_negative_real', b'-0.1'),
    ('y_structure_lonely_null', b'null'), ('y_structure_lonely_string', b'"asd"'), ('y_structure_lonely_true', b'true'),
    ('y_structure_string_empty', b'""'), ('y_structure_trailing_newline', b'["a"]\n'), ('y_structure_true_in_array', b'[true]'),
    ('y_structure_whitespace_array', b' [] '), ('y_structure_nested_256', b'[' * 256 + b']' * 256),
    ('y_structure_nested_objects', b'{"a":' * 100 + b'1' + b'}' * 100),
    ('n_array_1_true_without_comma', b'[1 true]'), ('n_array_colon_instead_of_comma', b'["": 1]'),
    ('n_array_comma_after_close', b'[""],'), ('n_array_comma_and_number', b'[,1]'), ('n_array_double_comma', b'[1,,2]'),
    ('n_array_double_extra_comma', b'["x",,]'), ('n_array_extra_close', b'["x"]]'), ('n_array_extra_comma', b'["",]'),
    ('n_array_incomplete', b'["x"'), ('n_array_incomplete_invalid_value', b'[x'), ('n_array_inner_array_no_comma', b'[3[4]]'),
    ('n_array_items_separated_by_semicolon', b'[1:2]'), ('n_array_just_comma', b'[,]'), ('n_array_just_minus', b'[-]'),
    ('n_array_missing_value', b'[   , ""]'), ('n_array_newlines_unclosed', b'["a",\n4\n,1,'), ('n_array_number_and_comma', b'[1,]'),
    ('n_array_number_and_several_commas', b'[1,,]'), ('n_array_star_inside', b'[*]'), ('n_array_unclosed', b'[""'),
    ('n_array_unclosed_trailing_comma', b'[1,'), ('n_array_unclosed_with_object_inside', b'[{}'),
    ('n_incomplete_false', b'[fals]'), ('n_incomplete_null', b'[nul]'), ('n_incomplete_true', b'[tru]'),
    ('n_number_++', b'[++1234]'), ('n_number_+1', b'[+1]'), ('n_number_+Inf', b'[+Inf]'), ('n_number_-01', b'[-01]'),
    ('n_number_-1.0.', b'[-1.0.]'), ('n_number_-2.', b'[-2.]'), ('n_number_-NaN', b'[-NaN]'), ('n_number_.-1', b'[.-1]'),
    ('n_number_.2e-3', b'[.2e-3]'), ('n_number_0.1.2', b'[0.1.2]'), ('n_number_0.3e+', b'[0.3e+]'), ('n_number_0.3e', b'[0.3e]'),
    ('n_number_0.e1', b'[0.e1]'), ('n_number_0_capital_E+', b'[0E+]'), ('n_number_0e', b'[0e]'), ('n_number_1.0e+', b'[1.0e+]'),
    ('n_number_1.0e-', b'[1.0e-]'), ('n_number_1_000', b'[1 000.0]'), ('n_number_1eE2', b'[1eE2]'), ('n_number_2.e+3', b'[2.e+3]'),
    ('n_number_9.e+', b'[9.e+]'), ('n_number_Inf', b'[Inf]'), ('n_number_NaN', b'[NaN]'), ('n_number_Infinity', b'[Infinity]'),
    ('n_number_minus_infinity', b'[-Infinity]'), ('n_number_bare_NaN', b'NaN'), ('n_number_expression', b'[1+2]'),
    ('n_number_hex_1_digit', b'[0x1]'), ('n_number_hex_2_digits', b'[0x42]'), ('n_number_minus_space_1', b'[- 1]'),
    ('n_number_neg_int_starting_with_zero', b'[-012]'), ('n_number_neg_real_without_int_part', b'[-.123]'),
    ('n_number_real_garbage_after_e', b'[1ea]'), ('n_number_real_without_fractional_part', b'[1.]'),
    ('n_number_starting_with_dot', b'[.123]'), ('n_number_with_leading_zero', b'[012]'), ('n_number_leading_zero_root', b'00'),
    ('n_number_trailing_minus', b'1-'), ('n_number_U+FF11_fullwidth_digit_one', b'[-\xef\xbc\x91]'),
    ('n_object_bad_value', b'["x", truth]'), ('n_object_bracket_key', b'{[: "x"}\n'), ('n_object_comma_instead_of_colon', b'{"x", null}'),
    ('n_object_double_colon', b'{"x"::"b"}'), ('n_object_garbage_at_end', b'{"a":"a" 123}'), ('n_object_key_with_single_quotes', b"{key: 'value'}"),
    ('n_object_missing_colon', b'{"a" b}'), ('n_object_missing_key', b'{:"b"}'), ('n_object_missing_semicolon', b'{"a" "b"}'),
    ('n_object_missing_value', b'{"a":'), ('n_object_no-colon', b'{"a"'), ('n_object_non_string_key', b'{1:1}'),
    ('n_object_repeated_null_null', b'{null:null,null:null}'), ('n_object_several_trailing_commas', b'{"id":0,,,,,}'),
    ('n_object_single_quote', b"{'a':0}"), ('n_object_trailing_comma', b'{"id":0,}'), ('n_object_trailing_comment', b'{"a":"b"}/**/'),
    ('n_object_two_commas_in_a_row', b'{"a":"b",,"c":"d"}'), ('n_object_unquoted_key', b'{a: "b"}'), ('n_object_unterminated-value', b'{"a":"a'),
    ('n_object_with_trailing_garbage', b'{"a":"b"}#'), ('n_object_lone_continuation_byte_in_key', b'{"\xb9":"0",}'),
    ('n_single_space', b' '), ('n_empty', b''), ('n_string_1_surrogate_then_escape', b'["\\uD800\\"]'),
    ('n_string_1_surrogate_then_escape_u', b'["\\uD800\\u"]'), ('n_string_1_surrogate_then_escape_u1', b'["\\uD800\\u1"]'),
    ('n_string_accentuated_char_no_quotes', b'[\xc3\xa9]'), ('n_string_backslash_00', b'["\\\x00"]'), ('n_string_escape_x', b'["\\x00"]'),
    ('n_string_escaped_backslash_bad', b'["\\\\\\"]'), ('n_string_escaped_ctrl_char_tab', b'["\\\t"]'), ('n_string_escaped_emoji', b'["\\\xf0\x9f\x8c\x80"]'),
    ('n_string_incomplete_escape', b'["\\"]'), ('n_string_incomplete_escaped_character', b'["\\u00A"]'),
    ('n_string_incomplete_surrogate', b'["\\uD834\\uDd"]'), ('n_string_invalid_backslash_esc', b'["\\a"]'),
    ('n_string_invalid_unicode_escape', b'["\\uqqqq"]'), ('n_string_invalid_utf8_after_escape', b'["\\\xe5"]'),
    ('n_string_leading_uescaped_thinspace', b'[\\u0020"asd"]'), ('n_string_no_quotes_with_bad_escape', b'[\\n]'),
    ('n_string_single_doublequote', b'"'), ('n_string_single_quote', b"['single quote']"), ('n_string_single_string_no_double_quotes', b'abc'),
    ('n_string_start_escape_unclosed', b'["\\'), ('n_string_unescaped_ctrl_char', b'["a\x00a"]'), ('n_string_unescaped_newline', b'["new\nline"]'),
    ('n_string_unescaped_tab', b'["\t"]'), ('n_string_unicode_CapitalU', b'"\\UA66D"'), ('n_string_with_trailing_garbage', b'""x'),
    ('n_structure_UTF8_BOM_no_data', b'\xef\xbb\xbf'), ('n_structure_angle_bracket_.', b'<.>'), ('n_structure_angle_bracket_null', b'[<null>]'),
    ('n_structure_array_trailing_garbage', b'[1]x'), ('n_structure_array_with_extra_array_close', b'[1]]'),
    ('n_structure_array_with_unclosed_string', b'["asd]'), ('n_structure_ascii-unicode-identifier', b'a\xc3\xa5'),
    ('n_structure_capitalized_True', b'[True]'), ('n_structure_close_unopened_array', b'1]'), ('n_structure_comma_instead_of_closing_brace', b'{"x": true,'),
    ('n_structure_double_array', b'[][]'), ('n_structure_end_array', b']'), ('n_structure_incomplete_UTF8_BOM', b'\xef\xbb{}'),
    ('n_structure_lone-invalid-utf-8', b'\xe5'), ('n_structure_lone-open-bracket', b'['), ('n_structure_no_data', b''),
    ('n_structure_null-byte-outside-string', b'[\x00]'), ('n_structure_number_with_trailing_garbage', b'2@'),
    ('n_structure_object_followed_by_closing_object', b'{}}'), ('n_structure_object_unclosed_no_value', b'{"":'),
    ('n_structure_object_with_comment', b'{"a":/*comment*/"b"}'), ('n_structure_object_with_trailing_garbage', b'{"a": true} "x"'),
    ('n_structure_open_array_apostrophe', b"['"), ('n_structure_open_array_comma', b'[,'), ('n_structure_open_object', b'{'),
    ('n_structure_open_object_close_array', b'{]'), ('n_structure_open_object_comma', b'{,'), ('n_structure_single_star', b'*'),
    ('n_structure_trailing_#', b'{"a":"b"}#{}'), ('n_structure_uescaped_LF_before_string', b'[\\u000A""]'),
    ('n_structure_unclosed_array_partial_null', b'[ false, nul'), ('n_structure_unicode-identifier', b'\xc3\xa5'),
    ('n_structure_whitespace_U+2060_word_joiner', b'[\xe2\x81\xa0]'), ('n_structure_whitespace_formfeed', b'[\x0c]'),
    ('n_structure_UTF8_BOM_array', b'\xef\xbb\xbf[]'), ('n_multidigit_after_zero_object', b'{"a":00}'),
    ('i_number_huge_exp', b'[1.5e999999999999999999999]'), ('i_number_neg_int_huge_exp', b'[-1e+9999]'),
    ('i_number_very_long', b'[' + b'9' * 5000 + b']'), ('i_object_key_lone_2nd_surrogate', b'{"\\uDFAA":0}'),
    ('i_string_1st_surrogate_but_2nd_missing', b'["\\uDADA"]'), ('i_string_1st_valid_surrogate_2nd_invalid', b'["\\uD888\\u1234"]'),
    ('i_string_UTF-16LE_with_BOM', b'\xff\xfe[\x00"\x00\xe9\x00"\x00]\x00'), ('i_string_UTF-8_invalid_sequence', b'["\xe6\x97\xa5\xd1\x88\xfa"]'),
    ('i_string_UTF8_surrogate_U+D800', b'["\xed\xa0\x80"]'), ('i_string_incomplete_surrogate_and_escape_valid', b'["\\uD800\\n"]'),
    ('i_string_incomplete_surrogate_pair', b'["\\uDd1ea"]'), ('i_string_incomplete_surrogates_escape_valid', b'["\\uD800\\uD800\\n"]'),
    ('i_string_invalid_lonely_surrogate', b'["\\ud800"]'), ('i_string_invalid_surrogate', b'["\\ud800abc"]'),
    ('i_string_inverted_surrogates_U+1D11E', b'["\\uDd1e\\uD834"]'), ('i_string_lone_second_surrogate', b'["\\uDFAA"]'),
    ('i_string_lone_utf8_continuation_byte', b'["\x81"]'), ('i_string_not_in_unicode_range', b'["\xf4\xbf\xbf\xbf"]'),
    ('i_string_overlong_sequence_2_bytes', b'["\xc0\xaf"]'), ('i_string_overlong_sequence_6_bytes', b'["\xfc\x83\xbf\xbf\xbf\xbf"]'),
    ('i_string_overlong_sequence_6_bytes_null', b'["\xfc\x80\x80\x80\x80\x80"]'), ('i_string_truncated-utf-8', b'["\xe0\xff"]'),
    ('i_string_utf16BE_no_BOM', b'\x00[\x00"\x00\xe9\x00"\x00]'), ('i_string_iso_latin_1', b'["\xe9"]'),
    ('i_string_overlong_3_bytes', b'["\xe0\x80\xaf"]'), ('i_string_truncated_at_eof', b'"\xe2\x82'),
    ('i_structure_500_nested_arrays', b'[' * 500 + b']' * 500), ('i_structure_UTF-8_BOM_empty_object', b'\xef\xbb\xbf{}'),
]


def rand_string(rng):
    pieces = []
    for _ in range(rng.randrange(0, 8)):
        kind = rng.randrange(10)
        if kind < 3:
            pieces.append(rng.choice(['a', 'Z', ' ', '/', 'key', '0', '\u00e9', '\u4e2d', '\U0001f600', '\u2028', '\x7f']))
        elif kind == 3:
            pieces.append(rng.choice(['\\"', '\\\\', '\\/', '\\b', '\\f', '\\n', '\\r', '\\t']))
        elif kind == 4:
            pieces.append('\\u%04x' % rng.choice([0, 1, 0x1f, 0x20, 0x41, 0xe9, 0x7ff, 0x800, 0xfffe, 0xffff]))
        elif kind == 5:
            pieces.append(rng.choice(['\\ud83d\\ude00', '\\uD834\\uDD1E', '\\udbff\\udfff']))
        else:
            pieces.append(''.join(rng.choice('abcxyz_-.[') for _ in range(rng.randrange(1, 4))))
    return '"' + ''.join(pieces) + '"'


def rand_number(rng):
    sign = rng.choice(['', '', '-'])
    whole = rng.choice(['0', str(rng.randrange(1, 10)), str(rng.randrange(10 ** 25)).lstrip('0') or '0'])
    frac = rng.choice(['', '', '.' + str(rng.randrange(10 ** rng.randrange(1, 12))).zfill(3)])
    exp = rng.choice(['', '', 'e5', 'E-12', 'e+400', 'e0'])
    return sign + whole + frac + exp


def ws(rng):
    return rng.choice(['', '', '', ' ', '\n', '\t', '\r\n  '])


def rand_value(rng, depth):
    kind = rng.randrange(9 if depth < 6 else 6)
    if kind == 0:
        return rng.choice(['true', 'false', 'null'])
    if kind in (1, 2):
        return rand_number(rng)
    if kind in (3, 4, 5):
        return rand_string(rng)
    if kind in (6, 7):
        items = [ws(rng) + rand_value(rng, depth + 1) + ws(rng) for _ in range(rng.randrange(0, 6))]
        return '[' + ','.join(items) + ws(rng) + ']'
    members = []
    keys = ['"a"', '"b"', '"items"', '"name"', '"\\u0061"', rand_string(rng)]
    for _ in range(rng.randrange(0, 6)):
        members.append(ws(rng) + rng.choice(keys) + ws(rng) + ':' + ws(rng) + rand_value(rng, depth + 1) + ws(rng))
    return '{' + ','.join(members) + ws(rng) + '}'


def rand_doc(rng):
    return (ws(rng) + rand_value(rng, 0) + ws(rng)).encode('utf-8')


def rand_path(rng, value):
    segments = []
    while rng.random() < 0.8:
        if isinstance(value, Object) and value and rng.random() < 0.85:
            key, value = rng.choice(value)
            segments.append(key)
        elif isinstance(value, list) and not isinstance(value, Object) and value and rng.random() < 0.85:
            index = rng.randrange(len(value))
            segments.append(index)
            value = value[index]
        else:
            segments.append(rng.choice(['a', 'missing', 0, 3]))
            break
    return [s for s in segments if not (isinstance(s, str) and (s == '' or '.' in s or '[' in s or '\x00' in s))]


def mutate(rng, data):
    data = bytearray(data)
    for _ in range(rng.randrange(1, 3)):
        op = rng.randrange(3)
        pos = rng.randrange(len(data) + 1)
        byte = rng.choice(b'{}[],:"\\ 0123456789-+.eEtrufalsn\x00\x1f\x7f\x80\xbf\xc3\xed\xf0\xff')
        if op == 0:
            data.insert(pos, byte)
        elif op == 1 and pos < len(data):
            del data[pos]
        elif pos < len(data):
            data[pos] = byte
    return bytes(data)


# Exact typed errors and byte offsets from this library's own contract.
ERRORS = [
    (b'', 'UnexpectedEnd', 0), (b'   ', 'UnexpectedEnd', 3), (b'[1,]', 'UnexpectedByte', 3),
    (b'[1 2]', 'UnexpectedByte', 3), (b'{"a" 1}', 'UnexpectedByte', 5), (b'{"a":1,}', 'UnexpectedByte', 7),
    (b'01', 'InvalidNumber', 0), (b'[ -x]', 'InvalidNumber', 2), (b'1.', 'InvalidNumber', 0), (b'[1.e3]', 'InvalidNumber', 1),
    (b'tru', 'UnexpectedEnd', 3), (b'nulL', 'UnexpectedByte', 3), (b'1 2', 'TrailingInput', 2), (b'{}x', 'TrailingInput', 2),
    (b'"a\x01"', 'ControlCharacter', 2), (b'"\\q"', 'InvalidEscape', 2), (b'"\\u12g4"', 'InvalidEscape', 5),
    (b'"ab\\ud800"', 'InvalidSurrogate', 3), (b'"\\udc00"', 'InvalidSurrogate', 1), (b'["x\\ud800\\u0041"]', 'InvalidSurrogate', 3),
    (b'"\\ud83dx"', 'InvalidSurrogate', 1), (b'"\xff"', 'InvalidUtf8', 1), (b'"ab\xc3("', 'InvalidUtf8', 3),
    (b'"\xed\xa0\x80"', 'InvalidUtf8', 1), (b'"\xe2\x82', 'InvalidUtf8', 1), (b'\xef\xbb\xbf[]', 'UnexpectedByte', 0),
    (b'[' * 513 + b']' * 513, 'DepthLimit', 512), (b'["abc"', 'UnexpectedEnd', 6), (b'{"a":', 'UnexpectedEnd', 5),
    (b'"unterminated', 'UnexpectedEnd', 13),
]


def main():
    sys.setrecursionlimit(20000)
    group, exe = sys.argv[1], sys.argv[2]
    tally = Tally(group)
    rng = random.Random(4180 + sum(map(ord, group)))
    if group == 'suite':
        for name, data in SUITE:
            tally.compare(exe, name, data)
    elif group == 'generated':
        for index in range(400):
            tally.compare(exe, 'gen%d' % index, rand_doc(rng))
    elif group == 'mutations':
        for index in range(600):
            tally.compare(exe, 'mut%d' % index, mutate(rng, rand_doc(rng)))
    elif group == 'paths':
        produced = 0
        while produced < 300:
            data = rand_doc(rng)
            value = reference(data)
            tally.compare(exe, 'path%d' % produced, data, rand_path(rng, value))
            produced += 1
    elif group == 'chunks':
        # Documents far above the 1 KiB read size, so tokens cross reads.
        for index in range(30):
            items = [rand_value(rng, 2) for _ in range(rng.randrange(50, 400))]
            data = ('[' + ',\n'.join(items) + ']').encode('utf-8')
            tally.compare(exe, 'chunk%d' % index, data)
        long_string = '"' + ('\\u00e9x\U0001f600' * 3000) + '"'
        tally.compare(exe, 'long_string', long_string.encode('utf-8'))
        tally.compare(exe, 'long_number', b'-' + b'7' * 4000 + b'.5e-3')
    elif group == 'errors':
        for data, kind, offset in ERRORS:
            code, out, err = run(exe, data)
            tally.cases += 1
            tally.rejected += 1
            want = ('jq-lite: %s at %d\n' % (kind, offset)).encode()
            if code == 2 and out == b'' and err == want:
                tally.agree += 1
            else:
                tally.failures.append((data[:40], want, code, out, err))
    elif group == 'bytewise':
        # EXECUTABLE is tests/fixtures/extended/json_stream_contracts.lani:
        # one byte per feed, every token copied through the writer.
        inputs = [(n, d) for n, d in SUITE] + [('gen%d' % i, rand_doc(rng)) for i in range(150)]
        inputs += [('mut%d' % i, mutate(rng, rand_doc(rng))) for i in range(150)]
        for name, data in inputs:
            try:
                want = (render(reference(data)) + '\n').encode('utf-8')
            except (ValueError, RecursionError):
                want = None
            proc = subprocess.run([exe], input=data, capture_output=True, timeout=20)
            tally.cases += 1
            if want is None:
                tally.rejected += 1
                ok = proc.returncode == 2 and proc.stdout.startswith(b'error ')
            else:
                tally.accepted += 1
                ok = proc.returncode == 0 and proc.stdout == want
            if ok:
                tally.agree += 1
            else:
                tally.failures.append((name, data[:80], want, proc.returncode, proc.stdout[:120]))
        for data, kind, offset in ERRORS:
            proc = subprocess.run([exe], input=data, capture_output=True, timeout=20)
            tally.cases += 1
            tally.rejected += 1
            if proc.returncode == 2 and proc.stdout == ('error %s %d\n' % (kind, offset)).encode():
                tally.agree += 1
            else:
                tally.failures.append((data[:40], kind, offset, proc.returncode, proc.stdout))
    elif group == 'writer':
        proc = subprocess.run([exe, 'writer'], capture_output=True, timeout=20)
        want = b'{"a\\"b":[-0.5e+3,true,null]}\n"\\u0001\\u000a\x7f"\nwriter ok\n'
        tally.cases += 1
        if proc.returncode == 0 and proc.stdout == want:
            tally.agree += 1
        else:
            tally.failures.append(('writer', want, proc.returncode, proc.stdout))
    else:
        raise SystemExit('unknown group ' + group)
    return tally.finish()


if __name__ == '__main__':
    sys.exit(main())
