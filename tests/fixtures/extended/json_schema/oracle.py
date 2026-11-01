"""Model oracle: ext::json_schema against a Python model of JSON Schema 2020-12.

usage: python3 -I oracle.py BATCH_EXE [--seed N] [--cases N]

BATCH_EXE is tests/fixtures/extended/json_schema/batch.lani compiled. The
model implements the profile in docs/extended-json-schema.md with the
library's compile checks, evaluation order, and depth and work counting. The
official JSON-Schema-Test-Suite is not on this machine, so SPEC holds cases
written by hand from the 2020-12 core and validation specifications, each
with its expected result; the model must reproduce those first. Then every
case (spec, error and generated schema/instance pairs) runs through BATCH_EXE
and the outputs are compared. Prints `group agree/total` lines and exits 1 on
any disagreement.
"""

import decimal
import fractions
import json
import random
import re
import subprocess
import sys

sys.setrecursionlimit(20000)
decimal.getcontext().prec = 200
DIALECT = 'https://json-schema.org/draft/2020-12/schema'
COUNT_LIMIT = 2147483647


class Num:
    def __init__(self, spelling):
        self.spelling = spelling
        self.value = decimal.Decimal(spelling)

    def __repr__(self):
        return self.spelling


class Failure(Exception):
    def __init__(self, kind):
        super().__init__(kind)
        self.kind = kind


def _pairs(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise Failure('DuplicateKey')
        seen[key] = value
    return seen


def _constant(name):
    raise ValueError(name)


def parse(text):
    try:
        return json.loads(text, parse_int=Num, parse_float=Num, parse_constant=_constant, object_pairs_hook=_pairs)
    except Failure:
        raise
    except ValueError:
        raise Failure('Parse')


def equal(a, b):
    if a is None or isinstance(a, bool):
        return a is b
    if isinstance(a, Num):
        return isinstance(b, Num) and a.value == b.value
    if isinstance(a, str):
        return isinstance(b, str) and a == b
    if isinstance(a, list):
        return isinstance(b, list) and len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return isinstance(b, dict) and len(a) == len(b) and all(k in b and equal(v, b[k]) for k, v in a.items())


def is_integer(number):
    return number.value == number.value.to_integral_value()


def significant_digits(spelling):
    mantissa = re.split('[eE]', spelling.lstrip('-'))[0].replace('.', '')
    return len(mantissa.strip('0'))


# Regular expressions: patterns are written in the dialect ext::regex and
# Python share; `$` is end of text, so it maps to \Z.
UNSUPPORTED_REGEX = ('(?=', '(?!', '\\1', '(?i)')


def regex(pattern):
    if any(part in pattern for part in UNSUPPORTED_REGEX):
        raise Failure('InvalidPattern')
    try:
        return re.compile(re.sub(r'(?<!\\)\$', r'\\Z', pattern), re.ASCII)
    except re.error:
        raise Failure('InvalidPattern')


# Compiling ------------------------------------------------------------------

TYPES = ('null', 'boolean', 'object', 'array', 'number', 'string', 'integer')
COUNTS = ('maxLength', 'minLength', 'maxItems', 'minItems', 'maxContains', 'minContains', 'maxProperties', 'minProperties')
UNSUPPORTED = ('$anchor', '$dynamicRef', '$dynamicAnchor', '$vocabulary', 'unevaluatedItems', 'unevaluatedProperties')
LISTS = ('allOf', 'anyOf', 'oneOf', 'prefixItems')
SINGLE = ('not', 'if', 'then', 'else', 'items', 'contains', 'additionalProperties', 'propertyNames')
MAPS = ('properties', 'patternProperties', 'dependentSchemas', '$defs')
NUMERIC = ('multipleOf', 'maximum', 'exclusiveMaximum', 'minimum', 'exclusiveMinimum')


class Compiled:
    def __init__(self, root):
        self.root = root
        self.records = {}
        self.targets = {}
        self.patterns = {}

    def compile_at(self, node, root=False):
        if isinstance(node, bool):
            return
        if not isinstance(node, dict):
            raise Failure('InvalidSchema')
        if id(node) in self.records:
            return
        record = {}
        self.records[id(node)] = record
        for name, value in node.items():
            self.keyword(record, name, value, root)

    def names(self, value):
        if not isinstance(value, list):
            raise Failure('InvalidSchema')
        seen = []
        for item in value:
            if not isinstance(item, str) or item in seen:
                raise Failure('InvalidSchema')
            seen.append(item)

    def keyword(self, record, name, value, root):
        if name in UNSUPPORTED:
            raise Failure('Unsupported')
        if name == '$schema':
            if not isinstance(value, str):
                raise Failure('InvalidSchema')
            if value != DIALECT:
                raise Failure('UnsupportedDialect')
        elif name == '$id':
            if not isinstance(value, str):
                raise Failure('InvalidSchema')
            if not root:
                raise Failure('Unsupported')
        elif name == 'type':
            if isinstance(value, str):
                if value not in TYPES:
                    raise Failure('InvalidSchema')
                record['type'] = {value}
            elif isinstance(value, list) and value:
                seen = set()
                for item in value:
                    if not isinstance(item, str) or item not in TYPES or item in seen:
                        raise Failure('InvalidSchema')
                    seen.add(item)
                record['type'] = seen
            else:
                raise Failure('InvalidSchema')
        elif name == 'enum':
            if not isinstance(value, list):
                raise Failure('InvalidSchema')
            record['enum'] = value
        elif name == 'const':
            record['const'] = value
        elif name in NUMERIC:
            if not isinstance(value, Num):
                raise Failure('InvalidSchema')
            if name == 'multipleOf':
                if value.value <= 0:
                    raise Failure('InvalidSchema')
                if significant_digits(value.spelling) > 18:
                    raise Failure('Unsupported')
            record[name] = value
        elif name in COUNTS:
            if not isinstance(value, Num) or not is_integer(value) or value.value < 0:
                raise Failure('InvalidSchema')
            record[name] = min(int(value.value), COUNT_LIMIT)
        elif name == 'pattern':
            if not isinstance(value, str):
                raise Failure('InvalidSchema')
            record['pattern'] = regex(value)
        elif name == 'uniqueItems':
            if not isinstance(value, bool):
                raise Failure('InvalidSchema')
            if value:
                record['uniqueItems'] = True
        elif name == 'required':
            self.names(value)
            record['required'] = value
        elif name == 'dependentRequired':
            if not isinstance(value, dict):
                raise Failure('InvalidSchema')
            for item in value.values():
                self.names(item)
            record['dependentRequired'] = value
        elif name in LISTS:
            if not isinstance(value, list) or not value:
                raise Failure('InvalidSchema')
            for item in value:
                self.compile_at(item)
            record[name] = value
        elif name in SINGLE:
            self.compile_at(value)
            record[name] = value
        elif name in MAPS:
            if not isinstance(value, dict):
                raise Failure('InvalidSchema')
            for key, item in value.items():
                if name == 'patternProperties':
                    self.patterns[key] = regex(key)
                self.compile_at(item)
            record[name] = value
        elif name == '$ref':
            if not isinstance(value, str):
                raise Failure('InvalidSchema')
            target = self.resolve(value)
            record['$ref'] = target
            self.compile_at(target)

    def resolve(self, text):
        if not text.startswith('#'):
            raise Failure('InvalidReference')
        raw, out, index = text.encode('utf-8'), bytearray(), 1
        while index < len(raw):
            byte = raw[index]
            if byte == 0x25:
                digits = raw[index + 1:index + 3]
                if len(digits) < 2 or not all(chr(d) in '0123456789abcdefABCDEF' for d in digits):
                    raise Failure('InvalidReference')
                byte = int(digits.decode(), 16)
                index += 2
            out.append(byte)
            index += 1
        node = self.root
        for token in pointer_tokens(bytes(out)):
            if isinstance(node, dict):
                match = [v for k, v in node.items() if k.encode('utf-8') == token]
                if not match:
                    raise Failure('InvalidReference')
                node = match[0]
            elif isinstance(node, list):
                if re.fullmatch(rb'0|[1-9][0-9]*', token) is None or int(token) >= len(node):
                    raise Failure('InvalidReference')
                node = node[int(token)]
            else:
                raise Failure('InvalidReference')
        if not (isinstance(node, (bool, dict))):
            raise Failure('InvalidReference')
        return node


def pointer_tokens(raw):
    if raw == b'':
        return []
    if raw[0] != 0x2f:
        raise Failure('InvalidReference')
    tokens = []
    for part in raw[1:].split(b'/'):
        token, index = bytearray(), 0
        while index < len(part):
            if part[index] == 0x7e:
                following = part[index + 1] if index + 1 < len(part) else None
                if following == 0x30:
                    token.append(0x7e)
                elif following == 0x31:
                    token.append(0x2f)
                else:
                    raise Failure('InvalidReference')
                index += 2
                continue
            token.append(part[index])
            index += 1
        tokens.append(bytes(token))
    return tokens


# Validating -----------------------------------------------------------------

class Validator:
    def __init__(self, compiled, max_depth, max_work):
        self.c, self.max_depth, self.max_work = compiled, max_depth, max_work
        self.depth = self.work = 0

    def check(self, schema, instance):
        self.work += 1
        if self.work > self.max_work:
            raise Failure('WorkLimit')
        if self.depth >= self.max_depth:
            raise Failure('DepthLimit')
        self.depth += 1
        result = self.evaluate(schema, instance)
        self.depth -= 1
        return result

    def evaluate(self, schema, x):
        if isinstance(schema, bool):
            return schema
        r = self.c.records[id(schema)]
        if '$ref' in r and not self.check(r['$ref'], x):
            return False
        if 'type' in r:
            if x is None:
                kinds = {'null'}
            elif isinstance(x, bool):
                kinds = {'boolean'}
            elif isinstance(x, Num):
                kinds = {'number', 'integer'} if is_integer(x) else {'number'}
            elif isinstance(x, str):
                kinds = {'string'}
            elif isinstance(x, list):
                kinds = {'array'}
            else:
                kinds = {'object'}
            if not kinds & r['type']:
                return False
        if 'enum' in r and not any(equal(item, x) for item in r['enum']):
            return False
        if 'const' in r and not equal(r['const'], x):
            return False
        if isinstance(x, Num):
            v = x.value
            if 'multipleOf' in r and fractions.Fraction(v) % fractions.Fraction(r['multipleOf'].value) != 0:
                return False
            if 'maximum' in r and v > r['maximum'].value:
                return False
            if 'exclusiveMaximum' in r and v >= r['exclusiveMaximum'].value:
                return False
            if 'minimum' in r and v < r['minimum'].value:
                return False
            if 'exclusiveMinimum' in r and v <= r['exclusiveMinimum'].value:
                return False
        if isinstance(x, str):
            if 'maxLength' in r and len(x) > r['maxLength']:
                return False
            if 'minLength' in r and len(x) < r['minLength']:
                return False
            if 'pattern' in r and not r['pattern'].search(x):
                return False
        if isinstance(x, list) and not self.array(r, x):
            return False
        if isinstance(x, dict) and not self.object(r, x):
            return False
        for item in r.get('allOf', []):
            if not self.check(item, x):
                return False
        if 'anyOf' in r:
            if not any(self.check(item, x) for item in r['anyOf']):
                return False
        if 'oneOf' in r:
            passed = 0
            for item in r['oneOf']:
                passed += self.check(item, x)
                if passed > 1:
                    return False
            if passed != 1:
                return False
        if 'not' in r and self.check(r['not'], x):
            return False
        if 'if' in r:
            branch = r.get('then') if self.check(r['if'], x) else r.get('else')
            if branch is not None and not self.check(branch, x):
                return False
        return True

    def array(self, r, x):
        if 'maxItems' in r and len(x) > r['maxItems']:
            return False
        if 'minItems' in r and len(x) < r['minItems']:
            return False
        if r.get('uniqueItems'):
            for i in range(len(x)):
                for j in range(i + 1, len(x)):
                    if equal(x[i], x[j]):
                        return False
        prefix = r.get('prefixItems', [])
        for rule, item in zip(prefix, x):
            if not self.check(rule, item):
                return False
        if 'items' in r:
            for item in x[len(prefix):]:
                if not self.check(r['items'], item):
                    return False
        if 'contains' in r:
            matched = sum(self.check(r['contains'], item) for item in x)
            if matched < r.get('minContains', 1) or ('maxContains' in r and matched > r['maxContains']):
                return False
        return True

    def object(self, r, x):
        if 'maxProperties' in r and len(x) > r['maxProperties']:
            return False
        if 'minProperties' in r and len(x) < r['minProperties']:
            return False
        if 'required' in r and not all(name in x for name in r['required']):
            return False
        for name, names in r.get('dependentRequired', {}).items():
            if name in x and not all(other in x for other in names):
                return False
        properties = r.get('properties')
        for name, rule in (properties or {}).items():
            if name in x and not self.check(rule, x[name]):
                return False
        patterns = r.get('patternProperties')
        if patterns is not None or 'additionalProperties' in r:
            for name, value in x.items():
                covered = properties is not None and name in properties
                for pattern, rule in (patterns or {}).items():
                    if self.c.patterns[pattern].search(name):
                        covered = True
                        if not self.check(rule, value):
                            return False
                if not covered and 'additionalProperties' in r and not self.check(r['additionalProperties'], value):
                    return False
        if 'propertyNames' in r:
            for name in x:
                if not self.check(r['propertyNames'], name):
                    return False
        for name, rule in r.get('dependentSchemas', {}).items():
            if name in x and not self.check(rule, x):
                return False
        return True


def outcome(depth, work, schema_text, instance_text):
    try:
        schema = parse(schema_text)
        instance = parse(instance_text)
        compiled = Compiled(schema)
        compiled.compile_at(schema, True)
        valid = Validator(compiled, depth or 256, work or 10000000).check(schema, instance)
        return 'valid' if valid else 'invalid'
    except Failure as failure:
        return 'err ' + failure.kind


# Hand-written cases ---------------------------------------------------------
# (schema, [(instance, expected)]) from the 2020-12 core and validation
# specifications; True is valid and False invalid.

SPEC = [
    ('true', [('1', True), ('null', True), ('{"a":[]}', True)]),
    ('false', [('1', False), ('null', False)]),
    ('{}', [('1', True), ('"x"', True), ('[1,{}]', True)]),
    ('{"type":"integer"}', [('1', True), ('1.0', True), ('1.5', False), ('1e2', True), ('-0', True), ('"1"', False), ('true', False)]),
    ('{"type":"number"}', [('1', True), ('1.5', True), ('-1e-7', True), ('"1"', False), ('null', False)]),
    ('{"type":"string"}', [('""', True), ('"x"', True), ('1', False)]),
    ('{"type":"boolean"}', [('true', True), ('false', True), ('0', False), ('null', False)]),
    ('{"type":"null"}', [('null', True), ('false', False), ('0', False), ('""', False)]),
    ('{"type":"array"}', [('[]', True), ('{}', False)]),
    ('{"type":"object"}', [('{}', True), ('[]', False)]),
    ('{"type":["integer","string"]}', [('1', True), ('"a"', True), ('1.1', False), ('null', False)]),
    ('{"enum":[1,"a",null,[1],{"k":true}]}', [('1', True), ('1.0', True), ('"a"', True), ('null', True), ('[1]', True),
                                              ('{"k":true}', True), ('true', False), ('[1,1]', False), ('{"k":1}', False)]),
    ('{"enum":[]}', [('1', False)]),
    ('{"enum":[false]}', [('false', True), ('0', False)]),
    ('{"enum":[0]}', [('false', False), ('0.0', True), ('-0', True)]),
    ('{"const":{"a":[1,2],"b":null}}', [('{"b":null,"a":[1,2.0]}', True), ('{"a":[2,1],"b":null}', False), ('{"a":[1,2]}', False)]),
    ('{"const":null}', [('null', True), ('0', False)]),
    ('{"multipleOf":2}', [('10', True), ('7', False), ('0', True), ('-4', True), ('"x"', True)]),
    ('{"multipleOf":0.01}', [('0.07', True), ('19.99', True), ('0.075', False), ('1e-2', True)]),
    ('{"multipleOf":1.5}', [('4.5', True), ('35', False), ('3e1', True)]),
    ('{"multipleOf":1e-5}', [('1e300', True), ('1.000001', False)]),
    ('{"maximum":3}', [('3', True), ('3.0', True), ('3.0001', False), ('-1e9', True), ('"9"', True)]),
    ('{"exclusiveMaximum":3}', [('2.999', True), ('3', False)]),
    ('{"minimum":-2.5}', [('-2.5', True), ('-2.6', False), ('100', True)]),
    ('{"exclusiveMinimum":0}', [('0', False), ('-0', False), ('1e-30', True)]),
    ('{"minimum":123456789012345678901234567890.00001}', [('123456789012345678901234567890.000009', False),
                                                          ('123456789012345678901234567890.00001', True)]),
    ('{"maxLength":2}', [('"ab"', True), ('"abc"', False), ('"\\u00e9\\u00e9"', True), ('"\\ud83d\\ude00\\ud83d\\ude00"', True), ('5', True)]),
    ('{"minLength":2}', [('"a"', False), ('"\\u00e9"', False), ('"ab"', True), ('[]', True)]),
    ('{"minLength":2.0}', [('"a"', False), ('"ab"', True)]),
    ('{"maxLength":0}', [('""', True), ('"\\u0000"', False)]),
    ('{"pattern":"^a*$"}', [('"aaa"', True), ('"abc"', False), ('""', True), ('1', True)]),
    ('{"pattern":"b"}', [('"abc"', True), ('"xyz"', False)]),
    ('{"pattern":"^(ab)+$"}', [('"abab"', True), ('"aba"', False)]),
    ('{"patternProperties":{"^(a|b)c$":{"type":"null"}}}', [('{"ac":null}', True), ('{"bc":1}', False), ('{"cc":1}', True)]),
    ('{"pattern":"^[0-9]{3}-[0-9]{4}$"}', [('"555-1212"', True), ('"5551212"', False)]),
    ('{"pattern":"\\\\d+"}', [('"x1"', True), ('"x"', False)]),
    ('{"maxItems":2}', [('[1,2]', True), ('[1,2,3]', False), ('"abc"', True)]),
    ('{"minItems":1}', [('[]', False), ('[0]', True)]),
    ('{"uniqueItems":true}', [('[1,2]', True), ('[1,1]', False), ('[1,1.0]', False), ('[0,false]', True), ('[{"a":1,"b":2},{"b":2,"a":1}]', False),
                              ('[[1],[true]]', True), ('[]', True), ('["a","b","a"]', False)]),
    ('{"uniqueItems":false}', [('[1,1]', True)]),
    ('{"prefixItems":[{"type":"integer"},{"type":"string"}]}', [('[1,"a"]', True), ('["a",1]', False), ('[1]', True), ('[1,"a",null]', True), ('[]', True)]),
    ('{"prefixItems":[{"type":"integer"}],"items":false}', [('[1]', True), ('[1,2]', False), ('[]', True)]),
    ('{"items":{"type":"integer"}}', [('[1,2,3]', True), ('[1,"x"]', False), ('{"a":"x"}', True)]),
    ('{"items":true}', [('[1,"x"]', True)]),
    ('{"contains":{"type":"integer"}}', [('["a",1]', True), ('["a"]', False), ('[]', False), ('{}', True)]),
    ('{"contains":{"const":1},"minContains":2}', [('[1,1]', True), ('[1,2]', False)]),
    ('{"contains":{"const":1},"maxContains":1}', [('[1,2]', True), ('[1,1]', False), ('[2]', False)]),
    ('{"contains":{"const":1},"minContains":0}', [('[]', True), ('[2]', True)]),
    ('{"contains":{"const":1},"minContains":0,"maxContains":0}', [('[2]', True), ('[1]', False)]),
    ('{"minContains":2}', [('[]', True)]),
    ('{"maxProperties":1}', [('{"a":1}', True), ('{"a":1,"b":2}', False), ('[1,2]', True)]),
    ('{"minProperties":1}', [('{}', False), ('{"a":null}', True)]),
    ('{"required":["a","b"]}', [('{"a":1,"b":2}', True), ('{"a":1}', False), ('[]', True), ('"a"', True)]),
    ('{"required":[]}', [('{}', True)]),
    ('{"dependentRequired":{"card":["billing"]}}', [('{"card":1,"billing":2}', True), ('{"card":1}', False), ('{"billing":2}', True), ('{}', True)]),
    ('{"properties":{"a":{"type":"integer"},"b":{"type":"string"}}}', [('{"a":1,"b":"x"}', True), ('{"a":"x"}', False), ('{}', True), ('{"c":[]}', True), ('[1]', True)]),
    ('{"patternProperties":{"^x":{"type":"integer"}}}', [('{"xa":1}', True), ('{"xa":"s"}', False), ('{"ax":"s"}', True)]),
    ('{"properties":{"a":true},"patternProperties":{"^b":true},"additionalProperties":false}',
     [('{"a":1,"bc":2}', True), ('{"c":1}', False), ('{}', True)]),
    ('{"additionalProperties":{"type":"boolean"}}', [('{"a":true}', True), ('{"a":1}', False)]),
    ('{"properties":{"a":{"maximum":3}},"patternProperties":{"a":{"minimum":2}}}', [('{"a":2}', True), ('{"a":1}', False), ('{"a":4}', False)]),
    ('{"propertyNames":{"maxLength":2}}', [('{"ab":1}', True), ('{"abc":1}', False), ('{}', True), ('"abc"', True)]),
    ('{"propertyNames":{"pattern":"^[a-z]+$"}}', [('{"abc":1}', True), ('{"aB":1}', False)]),
    ('{"propertyNames":{"enum":["a","b"]}}', [('{"a":1,"b":2}', True), ('{"c":1}', False)]),
    ('{"propertyNames":false}', [('{}', True), ('{"a":1}', False)]),
    ('{"dependentSchemas":{"a":{"required":["b"]}}}', [('{"a":1,"b":1}', True), ('{"a":1}', False), ('{"b":1}', True)]),
    ('{"allOf":[{"minimum":1},{"maximum":3}]}', [('2', True), ('0', False), ('4', False)]),
    ('{"anyOf":[{"type":"string"},{"minimum":3}]}', [('"a"', True), ('5', True), ('1', False)]),
    ('{"oneOf":[{"type":"integer"},{"minimum":2}]}', [('1', True), ('2.5', True), ('3', False), ('1.5', False)]),
    ('{"not":{"type":"integer"}}', [('"a"', True), ('1', False)]),
    ('{"not":true}', [('1', False)]),
    ('{"if":{"exclusiveMaximum":0},"then":{"minimum":-10},"else":{"multipleOf":2}}', [('-1', True), ('-100', False), ('4', True), ('3', False)]),
    ('{"if":{"const":1},"then":false}', [('1', False), ('2', True)]),
    ('{"if":{"const":1},"else":false}', [('1', True), ('2', False)]),
    ('{"then":false,"else":false}', [('1', True)]),
    ('{"$defs":{"pos":{"exclusiveMinimum":0}},"items":{"$ref":"#/$defs/pos"}}', [('[1,2]', True), ('[1,0]', False)]),
    ('{"$ref":"#/$defs/a","$defs":{"a":{"type":"integer"}},"minimum":5}', [('6', True), ('4', False), ('"x"', False)]),
    ('{"properties":{"next":{"$ref":"#"}},"required":["v"]}', [('{"v":1,"next":{"v":2}}', True), ('{"v":1,"next":{}}', False)]),
    ('{"$defs":{"tree":{"type":"object","properties":{"kids":{"type":"array","items":{"$ref":"#/$defs/tree"}}},"required":["v"]}},"$ref":"#/$defs/tree"}',
     [('{"v":1,"kids":[{"v":2,"kids":[]},{"v":3}]}', True), ('{"v":1,"kids":[{"kids":[]}]}', False)]),
    ('{"$defs":{"a~b":{"type":"null"},"c/d":{"type":"string"},"e%f":{"type":"array"}},"anyOf":[{"$ref":"#/$defs/a~0b"},{"$ref":"#/$defs/c~1d"},{"$ref":"#/$defs/e%25f"}]}',
     [('null', True), ('"s"', True), ('[]', True), ('1', False)]),
    ('{"$defs":{"\\u00e9":{"type":"null"}},"$ref":"#/$defs/%C3%A9"}', [('null', True), ('1', False)]),
    ('{"prefixItems":[{"type":"string"},{"$ref":"#/prefixItems/0"}]}', [('["a","b"]', True), ('["a",1]', False)]),
    ('{"$ref":"#/$defs/t","$defs":{"t":true}}', [('1', True)]),
    ('{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://example.com/s","type":"integer"}', [('1', True), ('"1"', False)]),
    ('{"title":"t","description":"d","default":1,"examples":[1],"deprecated":true,"readOnly":false,"$comment":"c","format":"email","x-unknown":{"type":7}}',
     [('"not an email"', True)]),
    ('{"definitions":{"a":{"type":"string"}},"$ref":"#/definitions/a"}', [('"x"', True), ('1', False)]),
    ('{"additionalItems":false,"dependencies":{"a":["b"]}}', [('[1,2]', True), ('{"a":1}', True)]),
]

# (schema, instance, expected output): every error kind and the checks
# around it.
ERRORS = [
    ('{"type":"integer"', '1', 'err Parse'), ('{}', '[1,]', 'err Parse'), ('{"a":1,"a":2}', '1', 'err DuplicateKey'),
    ('{}', '{"a":1,"a":1}', 'err DuplicateKey'), ('1', '1', 'err InvalidSchema'), ('"x"', '1', 'err InvalidSchema'),
    ('null', '1', 'err InvalidSchema'), ('[]', '1', 'err InvalidSchema'),
    ('{"type":"int"}', '1', 'err InvalidSchema'), ('{"type":[]}', '1', 'err InvalidSchema'),
    ('{"type":["string","string"]}', '1', 'err InvalidSchema'), ('{"type":[1]}', '1', 'err InvalidSchema'), ('{"type":3}', '1', 'err InvalidSchema'),
    ('{"enum":1}', '1', 'err InvalidSchema'), ('{"multipleOf":0}', '1', 'err InvalidSchema'), ('{"multipleOf":-1}', '1', 'err InvalidSchema'),
    ('{"multipleOf":"1"}', '1', 'err InvalidSchema'), ('{"multipleOf":1234567890123456789}', '1', 'err Unsupported'),
    ('{"multipleOf":123456789012345678}', '246913578024691356', 'valid'), ('{"multipleOf":1.23456789012345678e-300}', '0', 'valid'),
    ('{"maximum":"3"}', '1', 'err InvalidSchema'), ('{"exclusiveMinimum":true}', '1', 'err InvalidSchema'),
    ('{"maxLength":-1}', '1', 'err InvalidSchema'), ('{"maxLength":1.5}', '1', 'err InvalidSchema'), ('{"minItems":"1"}', '1', 'err InvalidSchema'),
    ('{"maxLength":-0}', '""', 'valid'), ('{"maxItems":1e40}', '[1]', 'valid'), ('{"minItems":1e40}', '[1]', 'invalid'),
    ('{"pattern":1}', '1', 'err InvalidSchema'), ('{"pattern":"("}', '1', 'err InvalidPattern'), ('{"pattern":"[a"}', '1', 'err InvalidPattern'),
    ('{"pattern":"a(?=b)"}', '1', 'err InvalidPattern'), ('{"patternProperties":{"(":true}}', '{}', 'err InvalidPattern'),
    ('{"patternProperties":{"a":1}}', '{}', 'err InvalidSchema'), ('{"uniqueItems":1}', '1', 'err InvalidSchema'),
    ('{"required":"a"}', '1', 'err InvalidSchema'), ('{"required":["a","a"]}', '1', 'err InvalidSchema'), ('{"required":[1]}', '1', 'err InvalidSchema'),
    ('{"dependentRequired":[]}', '1', 'err InvalidSchema'), ('{"dependentRequired":{"a":"b"}}', '1', 'err InvalidSchema'),
    ('{"allOf":[]}', '1', 'err InvalidSchema'), ('{"anyOf":{}}', '1', 'err InvalidSchema'), ('{"oneOf":[1]}', '1', 'err InvalidSchema'),
    ('{"prefixItems":[]}', '1', 'err InvalidSchema'), ('{"not":1}', '1', 'err InvalidSchema'), ('{"items":[{}]}', '1', 'err InvalidSchema'),
    ('{"then":{"type":"x"}}', '1', 'err InvalidSchema'), ('{"properties":[]}', '1', 'err InvalidSchema'), ('{"$defs":{"a":2}}', '1', 'err InvalidSchema'),
    ('{"$defs":{"unused":{"minimum":"x"}}}', '1', 'err InvalidSchema'), ('{"anyOf":[true,{"type":"x"}]}', '1', 'err InvalidSchema'),
    ('{"$ref":1}', '1', 'err InvalidSchema'), ('{"$ref":"other.json"}', '1', 'err InvalidReference'), ('{"$ref":"#foo"}', '1', 'err InvalidReference'),
    ('{"$ref":"#/$defs/missing"}', '1', 'err InvalidReference'), ('{"$ref":"#/$defs/a~2"}', '1', 'err InvalidReference'),
    ('{"$ref":"#/$defs/%zz"}', '1', 'err InvalidReference'), ('{"$ref":"#/$defs/%4"}', '1', 'err InvalidReference'),
    ('{"$ref":"#/minimum","minimum":1}', '1', 'err InvalidReference'), ('{"$ref":"#/allOf/1","allOf":[true]}', '1', 'err InvalidReference'),
    ('{"$ref":"#/allOf/01","allOf":[true,true]}', '1', 'err InvalidReference'), ('{"$ref":"#/const","const":{"type":"bogus"}}', '1', 'err InvalidSchema'),
    ('{"$ref":"#/const","const":{"type":"string"}}', '"x"', 'invalid'), ('{"$ref":""}', '1', 'err InvalidReference'),
    ('{"$ref":"#"}', '1', 'err DepthLimit'), ('{"$defs":{"a":{"$ref":"#/$defs/b"},"b":{"$ref":"#/$defs/a"}},"$ref":"#/$defs/a"}', '1', 'err DepthLimit'),
    ('{"anyOf":[{"type":"string"},{"$ref":"#"}]}', '1', 'err DepthLimit'), ('{"anyOf":[{"type":"integer"},{"$ref":"#"}]}', '1', 'valid'),
    ('{"$schema":"http://json-schema.org/draft-07/schema#"}', '1', 'err UnsupportedDialect'), ('{"$schema":7}', '1', 'err InvalidSchema'),
    ('{"items":{"$schema":"https://json-schema.org/draft/2019-09/schema"}}', '1', 'err UnsupportedDialect'),
    ('{"$id":7}', '1', 'err InvalidSchema'), ('{"items":{"$id":"x"}}', '1', 'err Unsupported'), ('{"$anchor":"a"}', '1', 'err Unsupported'),
    ('{"$dynamicRef":"#a"}', '1', 'err Unsupported'), ('{"$dynamicAnchor":"a"}', '1', 'err Unsupported'), ('{"$vocabulary":{}}', '1', 'err Unsupported'),
    ('{"unevaluatedItems":false}', '1', 'err Unsupported'), ('{"unevaluatedProperties":false}', '1', 'err Unsupported'),
    ('{"x":{"$anchor":"a"}}', '1', 'valid'),
]
LIMITS = [
    (3, 0, '{"items":{"items":{"items":true}}}', '[[[1]]]', 'err DepthLimit'),
    (4, 0, '{"items":{"items":{"items":true}}}', '[[[1]]]', 'valid'),
    (2, 0, '{"properties":{"a":{"propertyNames":{"maxLength":1}}}}', '{"a":{"bb":1}}', 'err DepthLimit'),
    (3, 0, '{"properties":{"a":{"propertyNames":{"maxLength":1}}}}', '{"a":{"bb":1}}', 'invalid'),
    (0, 3, '{"allOf":[true,true,true]}', '1', 'err WorkLimit'), (0, 4, '{"allOf":[true,true,true]}', '1', 'valid'),
    (0, 2, '{"anyOf":[true,true,true]}', '1', 'valid'), (0, 3, '{"oneOf":[true,true,false]}', '1', 'invalid'),
    (0, 4, '{"contains":{"const":1}}', '[1,1,1,1]', 'err WorkLimit'), (0, 5, '{"contains":{"const":1}}', '[1,1,1,1]', 'valid'),
    (0, 4, '{"contains":{"const":1},"maxItems":3}', '[1,1,1,1]', 'invalid'),
    (0, 1000, '{"$defs":{"d":{"anyOf":[{"$ref":"#/$defs/d"},true]}},"items":{"$ref":"#/$defs/d"}}', '[1]', 'err DepthLimit'),
]


# Generated cases ------------------------------------------------------------

KEYS = ['a', 'b', 'c', 'ab', 'x1', '']
STRINGS = ['', 'a', 'b', 'ab', 'ba', 'aab', 'abc', 'x1', 'é', '🙂', 'A_9', 'a b']
NUMBERS = ['0', '-0', '1', '2', '3', '-1', '1.5', '2.0', '0.5', '10', '1e1', '-2.5', '7', '0.25', '4', '6']
PATTERNS = ['^a', 'b$', 'a+', '^a*$', '^[ab]+$', '[0-9]', '^.$', 'ab|ba', '^(ab)+$', '\\w\\d', '^.{2,3}$', 'x', '[^a]', '\\s', '^$']


def num(rng):
    return Num(rng.choice(NUMBERS))


def gen_instance(rng, depth=3):
    roll = rng.random()
    if depth <= 0 or roll < 0.5:
        pick = rng.randrange(5)
        if pick == 0:
            return None
        if pick == 1:
            return rng.random() < 0.5
        if pick == 2:
            return num(rng)
        return rng.choice(STRINGS)
    if roll < 0.75:
        return [gen_instance(rng, depth - 1) for _ in range(rng.randrange(4))]
    return {rng.choice(KEYS): gen_instance(rng, depth - 1) for _ in range(rng.randrange(4))}


def gen_schema(rng, depth, defs):
    if rng.random() < 0.08:
        return rng.random() < 0.7
    out = {}
    for _ in range(rng.randrange(1, 4)):
        gen_keyword(rng, out, depth, defs)
    return out


def sub(rng, depth, defs):
    if depth <= 0:
        return rng.choice([True, False, {'type': rng.choice(TYPES)}, {'minimum': num(rng)}])
    return gen_schema(rng, depth - 1, defs)


def gen_keyword(rng, out, depth, defs):
    name = rng.choice(['type', 'type', 'enum', 'const', 'multipleOf', 'maximum', 'exclusiveMaximum', 'minimum', 'exclusiveMinimum',
                       'maxLength', 'minLength', 'pattern', 'maxItems', 'minItems', 'uniqueItems', 'contains', 'maxContains', 'minContains',
                       'maxProperties', 'minProperties', 'required', 'dependentRequired', 'allOf', 'anyOf', 'oneOf', 'not', 'if', 'then', 'else',
                       'dependentSchemas', 'prefixItems', 'items', 'items', 'properties', 'properties', 'patternProperties',
                       'additionalProperties', 'propertyNames', '$ref', '$ref'])
    if name == 'type':
        out[name] = rng.choice(TYPES) if rng.random() < 0.6 else rng.sample(TYPES, rng.randrange(1, 4))
    elif name == 'enum':
        out[name] = [gen_instance(rng, 1) for _ in range(rng.randrange(1, 4))]
    elif name == 'const':
        out[name] = gen_instance(rng, 2)
    elif name == 'multipleOf':
        out[name] = Num(rng.choice(['1', '2', '0.5', '1.5', '3', '0.25', '1e-1']))
    elif name in NUMERIC:
        out[name] = num(rng)
    elif name in COUNTS:
        out[name] = Num(rng.choice(['0', '1', '2', '3', '2.0', '1e0']))
    elif name == 'pattern':
        out[name] = rng.choice(PATTERNS)
    elif name == 'uniqueItems':
        out[name] = rng.random() < 0.7
    elif name == 'required':
        out[name] = rng.sample(KEYS, rng.randrange(0, 3))
    elif name == 'dependentRequired':
        out[name] = {rng.choice(KEYS): rng.sample(KEYS, rng.randrange(0, 3)) for _ in range(rng.randrange(1, 3))}
    elif name in ('allOf', 'anyOf', 'oneOf', 'prefixItems'):
        out[name] = [sub(rng, depth, defs) for _ in range(rng.randrange(1, 4))]
    elif name in SINGLE:
        out[name] = sub(rng, depth, defs)
    elif name in ('properties', 'dependentSchemas'):
        out[name] = {rng.choice(KEYS): sub(rng, depth, defs) for _ in range(rng.randrange(1, 4))}
    elif name == 'patternProperties':
        out[name] = {rng.choice(PATTERNS): sub(rng, depth, defs) for _ in range(rng.randrange(1, 3))}
    elif name == '$ref' and defs:
        out[name] = '#/$defs/' + rng.choice(defs)


def gen_root(rng):
    names = rng.sample(['p', 'q', 'r~s', 't/u', 'v'], rng.randrange(0, 4))
    defs = {name: None for name in names}
    escaped = [n.replace('~', '~0').replace('/', '~1') for n in names]
    root = gen_schema(rng, 3, escaped)
    if names and isinstance(root, dict):
        root['$defs'] = {name: gen_schema(rng, 2, escaped) for name in defs}
    return root


def encode(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, Num):
        return value.spelling
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '[' + ','.join(encode(item) for item in value) + ']'
    return '{' + ','.join(json.dumps(k, ensure_ascii=False) + ':' + encode(v) for k, v in value.items()) + '}'


def check_model():
    problems = 0
    for schema, cases in SPEC:
        for instance, expected in cases:
            got = outcome(0, 0, schema, instance)
            if got != ('valid' if expected else 'invalid'):
                print('model spec', schema, instance, got)
                problems += 1
    for schema, instance, expected in ERRORS:
        if outcome(0, 0, schema, instance) != expected:
            print('model errors', schema, instance, outcome(0, 0, schema, instance), expected)
            problems += 1
    for depth, work, schema, instance, expected in LIMITS:
        if outcome(depth, work, schema, instance) != expected:
            print('model limits', depth, work, schema, instance, outcome(depth, work, schema, instance), expected)
            problems += 1
    return problems


def main():
    args = sys.argv[1:]
    seed, count = 2020, 2000
    if '--seed' in args:
        seed = int(args[args.index('--seed') + 1])
    if '--cases' in args:
        count = int(args[args.index('--cases') + 1])
    if check_model():
        print('model disagrees with the hand-written expectations')
        return 1
    groups = [
        ('spec', [(0, 0, schema, instance) for schema, cases in SPEC for instance, _ in cases]),
        ('errors', [(0, 0, schema, instance) for schema, instance, _ in ERRORS]),
        ('limits', [(depth, work, schema, instance) for depth, work, schema, instance, _ in LIMITS]),
    ]
    rng = random.Random(seed)
    generated = []
    for _ in range(count):
        schema = encode(gen_root(rng))
        for _ in range(5):
            generated.append((0, 200000, schema, encode(gen_instance(rng))))
    groups.append(('generated', generated))
    cases = [case for _, group in groups for case in group]
    for case in cases:
        assert '\n' not in case[2] + case[3] and '\t' not in case[2] + case[3]
    stdin = ''.join('%d\t%d\t%s\t%s\n' % case for case in cases).encode('utf-8')
    result = subprocess.run([args[0]], input=stdin, capture_output=True, timeout=240)
    if result.returncode != 0:
        print('batch exited', result.returncode, result.stderr[:400])
        return 1
    lines = result.stdout.decode('utf-8').split('\n')
    at, failed, outcomes = 0, 0, {}
    for name, group in groups:
        agree = 0
        for case in group:
            want, got = outcome(*case), lines[at]
            at += 1
            outcomes[want] = outcomes.get(want, 0) + 1
            if got == want:
                agree += 1
            elif failed < 10:
                print('DIFF', name, case, '\n  lanius', got, '\n  model ', want)
            failed += got != want
        print('%s %d/%d' % (name, agree, len(group)))
    print('outcomes', ' '.join('%s=%d' % item for item in sorted(outcomes.items())))
    print('disagreements', failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
