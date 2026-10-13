#!/usr/bin/env python3
"""Independent consumer checks against an actual executable, including optional compiler gates."""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('binary', type=pathlib.Path)
parser.add_argument('--evidence', type=pathlib.Path)
parser.add_argument('--swiftc', help='Enable independent stub typechecking with this compiler')
parser.add_argument('--sdk', help='Optional SDK for stub typechecking')
parser.add_argument('--native-uikit', action='store_true', help='Typecheck UIKit with the active Xcode simulator SDK')
args = parser.parse_args()
binary = args.binary.resolve()
records = []
checks = []
stubs = '''struct UITraitCollection { var displayScale: Double { 2 } }
class UIView { var traitCollection: UITraitCollection { UITraitCollection() } }
struct UIScreen { static var main: UIScreen { UIScreen() }; var scale: Double { 2 } }
'''

with tempfile.TemporaryDirectory(prefix='resizelint-consumer-') as temporary:
    root = pathlib.Path(temporary)
    source = root / 'Canvas.swift'
    baseline = root / 'baseline.json'

    def run(name, arguments, expected=None, compiler=False):
        command = list(arguments) if compiler else [str(binary), *arguments]
        result = subprocess.run(command, cwd=root, capture_output=True, text=True)
        records.append({'name': name, 'command': command, 'exit': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
        if expected is not None:
            assert result.returncode == expected, f'{name}: exit {result.returncode}, expected {expected}'
        return result

    def check(name, callback):
        try:
            callback()
            checks.append({'name': name, 'status': 'pass'})
        except (AssertionError, KeyError, ValueError, TypeError) as error:
            checks.append({'name': name, 'status': 'fail', 'reason': str(error)})
        print(name + ': ' + checks[-1]['status'], flush=True)

    def typecheck(name):
        command = [args.swiftc, '-typecheck']
        if args.sdk:
            command += ['-sdk', args.sdk]
        run(name, [*command, str(source)], expected=0, compiler=True)

    def unsafe_contexts():
        contexts = [
            'static func readScale() -> Double { return UIScreen.main.scale }',
            'class func readScale() -> Double { return UIScreen.main.scale }',
            'static var scale: Double { UIScreen.main.scale }',
            'static subscript(index: Int) -> Double { get { UIScreen.main.scale } }',
            'class subscript(index: Int) -> Double { get { UIScreen.main.scale } }',
            'func render() -> Double { func nested() -> Double { UIScreen.main.scale }; return nested() }',
            'func render() -> Double { let value = { UIScreen.main.scale }; return value() }',
            'struct Nested { func render() -> Double { UIScreen.main.scale } }',
        ]
        for index, context in enumerate(contexts):
            source.write_text(stubs + 'class Canvas: UIView { ' + context + ' }\n')
            before = source.read_bytes()
            if args.swiftc:
                typecheck(f'unsafe-{index}-before')
            result = run(f'unsafe-{index}-fix', ['fix', source.name, '--format', 'json'], 0)
            assert source.read_bytes() == before, f'Unexpected source edit in {context}'
            assert not json.loads(result.stdout)['fixes']
            if args.swiftc:
                typecheck(f'unsafe-{index}-after')

    def positive_fix():
        source.write_text(stubs + '''class Canvas: UIView {
    func readScale() -> Double {
        let traitCollection = 0
        _ = traitCollection
        return UIScreen.main.scale
    }
}
''')
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        if args.swiftc:
            typecheck('instance-before')
        result = run('dry-run', ['fix', source.name, '--dry-run'], 0)
        assert 'self.traitCollection.displayScale' in result.stdout
        assert hashlib.sha256(source.read_bytes()).hexdigest() == before
        run('instance-fix', ['fix', source.name, '--format', 'json'], 0)
        assert 'self.traitCollection.displayScale' in source.read_text()
        if args.swiftc:
            typecheck('instance-after')
        once = source.read_bytes()
        run('idempotent-fix', ['fix', source.name], 0)
        assert source.read_bytes() == once

    def baseline_occurrences():
        baseline.unlink(missing_ok=True)
        first = 'func first() { _ = UIScreen.main.bounds }\n'
        source.write_text(first)
        run('baseline-create', ['baseline', 'create', source.name, '--baseline', baseline.name], 0)
        run('baseline-original-lint', ['lint', source.name, '--baseline', baseline.name], 0)
        source.write_text('// moved\n\n' + first)
        run('baseline-moved-lint', ['lint', source.name, '--baseline', baseline.name], 0)
        source.write_text(first + 'func second() { _ = UIScreen.main.bounds }\n')
        added = run('baseline-added-lint', ['lint', source.name, '--baseline', baseline.name, '--format', 'json'], 1)
        assert sum(d['baselineState'] == 'new' for d in json.loads(added.stdout)['diagnostics']) == 1
        run('baseline-added-check', ['baseline', 'check', source.name, '--baseline', baseline.name], 1)
        run('baseline-update', ['baseline', 'update', source.name, '--baseline', baseline.name], 0)
        run('baseline-round-trip', ['baseline', 'check', source.name, '--baseline', baseline.name], 0)
        source.write_text(first)
        run('baseline-deleted-check', ['baseline', 'check', source.name, '--baseline', baseline.name], 1)
        source.write_text('func first() { _ = UIScreen.main.bounds; _ = UIScreen.main.bounds }\n')
        run('baseline-identical-update', ['baseline', 'update', source.name, '--baseline', baseline.name], 0)
        document = json.loads(baseline.read_text())
        assert document['schemaVersion'] == document['fingerprintVersion'] == 2
        assert len(document['findings']) == 1 and document['findings'][0]['occurrences'] == 2
        run('baseline-identical-check', ['baseline', 'check', source.name, '--baseline', baseline.name], 0)
        document['findings'].append(document['findings'][0])
        baseline.write_text(json.dumps(document))
        run('duplicate-check', ['baseline', 'check', source.name, '--baseline', baseline.name], 1)
        run('duplicate-lint', ['lint', source.name, '--baseline', baseline.name], 2)
        baseline.unlink()

    def migration():
        legacy_payload = '\x1f'.join(['RL001', source.name, 'memberAccess', 'UIScreen.main.bounds'])
        legacy = {'schemaVersion': 1, 'toolVersion': '1.0.0', 'findings': [{
            'ruleID': 'RL001', 'path': source.name,
            'fingerprint': 'sha256:' + hashlib.sha256(legacy_payload.encode()).hexdigest()}]}
        source.write_text('func first() { _ = UIScreen.main.bounds }\n')
        baseline.write_text(json.dumps(legacy))
        result = run('legacy-unique-lint', ['lint', source.name, '--baseline', baseline.name], 0)
        assert 'Baseline v1' in result.stderr
        run('legacy-migrate', ['baseline', 'migrate', source.name, '--baseline', baseline.name], 0)
        assert json.loads(baseline.read_text())['schemaVersion'] == 2
        source.write_text(source.read_text() + 'func second() { _ = UIScreen.main.bounds }\n')
        baseline.write_text(json.dumps(legacy))
        before = baseline.read_bytes()
        run('legacy-ambiguous-lint', ['lint', source.name, '--baseline', baseline.name], 1)
        run('legacy-ambiguous-migrate', ['baseline', 'migrate', source.name, '--baseline', baseline.name], 2)
        assert baseline.read_bytes() == before
        source.write_text('let value = 1\n')
        run('legacy-stale-migrate', ['baseline', 'migrate', source.name, '--baseline', baseline.name], 2)
        assert baseline.read_bytes() == before
        baseline.unlink()

    def invocation():
        baseline.unlink(missing_ok=True)
        source.write_text('let value = 1\n')
        invalid = [
            ['--fail-on', 'potato'], ['--jobs', '0'], ['--jobs', '-1'], ['--jobs', 'word'],
            ['--format', 'potato'], ['--bogus'], ['--bad\x1b[31m\noption'], ['--dry-run'],
            ['--fail-on', 'error\x1b\nforged'], ['--jobs'],
        ]
        for index, options in enumerate(invalid):
            result = run(f'invalid-option-{index}', ['lint', source.name, *options], 2)
            assert not result.stdout and result.stderr
            assert '\x1b' not in result.stderr and '\nforged' not in result.stderr and '\noption' not in result.stderr
        for threshold in ['error', 'warning', 'info']:
            run('valid-' + threshold, ['lint', source.name, '--fail-on', threshold, '--jobs', '1'], 0)
        for command in [['lint', 'missing.swift'], ['lint', source.name, '--config', 'missing.yml']]:
            result = run('missing-input', command, 2)
            assert not result.stdout
        run('help', ['lint', '--help'], 0)
        source.write_bytes(b'\xff\xfe')
        result = run('invalid-utf8', ['lint', source.name, '--format', 'json'], 3)
        assert not result.stdout
        source.write_text('let value = 1\n')
        clean = run('clean-json', ['lint', source.name, '--format', 'json'], 0)
        assert json.loads(clean.stdout)['diagnostics'] == []

    def unicode_reports():
        baseline.unlink(missing_ok=True)
        texts = ['let café = 1; let bounds = UIScreen.main.bounds\n',
                 'let город = 1; let bounds = UIScreen.main.bounds\n',
                 'let emoji = "🧑🏽‍💻"; let bounds = UIScreen.main.bounds\r\n',
                 'let café = 1\r\nlet bounds = UIScreen\r\n  .main.bounds\r\n']
        schema = json.loads((pathlib.Path(__file__).resolve().parents[2] / 'Schemas/sarif-2.1.0.schema.json').read_text())
        import jsonschema
        for index, text in enumerate(texts):
            source.write_bytes(text.encode())
            native = json.loads(run(f'unicode-{index}-json', ['lint', source.name, '--format', 'json'], 1).stdout)
            sarif = json.loads(run(f'unicode-{index}-sarif', ['lint', source.name, '--format', 'sarif'], 1).stdout)
            jsonschema.Draft7Validator(schema).validate(sarif)
            assert sarif['runs'][0]['columnKind'] == 'utf16CodeUnits'
            diagnostic = native['diagnostics'][0]
            region = sarif['runs'][0]['results'][0]['locations'][0]['physicalLocation']['region']
            start = diagnostic['range']['utf8Offset']
            end = start + diagnostic['range']['utf8Length']
            assert text.encode()[start:end].decode().replace('\r', '').replace('\n', '').replace(' ', '') == 'UIScreen.main.bounds'
            for endpoint, offset in [('start', start), ('end', end)]:
                prefix = text.encode()[:offset].decode()
                line_prefix = prefix.rsplit('\n', 1)[-1]
                assert region[endpoint + 'Line'] == prefix.count('\n') + 1
                assert region[endpoint + 'Column'] == len(line_prefix.encode('utf-16-le')) // 2 + 1
                assert diagnostic['range'][endpoint]['column'] == len(line_prefix.encode()) + 1

    def native_uikit():
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
        compiler = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--find', 'swiftc'], text=True).strip()
        for member, changes in [('static func readScale() -> CGFloat { UIScreen.main.scale }', False),
                                ('class func readScale() -> CGFloat { UIScreen.main.scale }', False),
                                ('static subscript(index: Int) -> CGFloat { get { UIScreen.main.scale } }', False),
                                ('class subscript(index: Int) -> CGFloat { get { UIScreen.main.scale } }', False),
                                ('func readScale() -> CGFloat { UIScreen.main.scale }', True)]:
            source.write_text('import UIKit\n@MainActor class Canvas: UIView { ' + member + ' }\n')
            command = [compiler, '-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator', '-typecheck', str(source)]
            run('native-before', command, 0, compiler=True)
            before = source.read_bytes()
            run('native-fix', ['fix', source.name], 0)
            assert (source.read_bytes() != before) == changes
            run('native-after', command, 0, compiler=True)

    check('safe static/class/nested/closure boundaries', unsafe_contexts)
    check('positive fix, shadowed local, dry-run and idempotence', positive_fix)
    check('baseline occurrence lifecycle and duplicates', baseline_occurrences)
    check('v1 migration and safe refusal', migration)
    check('production invocation and JSON success/error paths', invocation)
    check('SARIF schema and semantic Unicode/CRLF coordinates', unicode_reports)
    if args.native_uikit:
        check('native UIKit static/class/instance compilation', native_uikit)

result = {'binary': str(binary), 'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'checks': checks, 'invocations': records,
          'stubTypechecking': bool(args.swiftc), 'nativeUIKitRequested': args.native_uikit}
if args.evidence:
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(result, indent=2, ensure_ascii=True) + '\n')
raise SystemExit(0 if all(c['status'] == 'pass' for c in checks) else 1)
