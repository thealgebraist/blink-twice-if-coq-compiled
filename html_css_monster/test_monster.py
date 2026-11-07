"""Run the OCaml executable; check reproducibility, coverage and HTML structure.

Only Python's standard library is used. This is not a browser conformance suite.
"""
from collections import Counter
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
EXE = ROOT / 'monster'
VOID = set('area base br col embed hr img input link meta source track wbr'.split())
PARENTS = {
    'head': {'html'}, 'body': {'html'}, 'title': {'head'}, 'base': {'head'},
    'link': {'head'}, 'meta': {'head'}, 'style': {'head'},
    'li': {'ul', 'ol', 'menu'}, 'dt': {'dl'}, 'dd': {'dl'},
    'caption': {'table'}, 'colgroup': {'table'}, 'col': {'colgroup'},
    'thead': {'table'}, 'tbody': {'table'}, 'tfoot': {'table'},
    'tr': {'thead', 'tbody', 'tfoot'}, 'td': {'tr'}, 'th': {'tr'},
    'legend': {'fieldset'}, 'summary': {'details'}, 'figcaption': {'figure'},
    'option': {'select', 'optgroup', 'datalist'}, 'optgroup': {'select'},
    'rt': {'ruby'}, 'rp': {'ruby'}, 'area': {'map'}, 'track': {'video'},
    'source': {'picture', 'audio', 'video'},
}


class Structure(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.tags = Counter()
        self.ids = set()
        self.references = []
        self.css = []
        self.boxes = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        parent = self.stack[-1] if self.stack else None
        if tag in PARENTS:
            assert parent in PARENTS[tag], (tag, parent)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, ('duplicate ID', attrs['id'])
            self.ids.add(attrs['id'])
        if 'href' in attrs:
            if attrs['href'].startswith('#'):
                self.references.append(attrs['href'][1:])
            else:
                assert attrs['href'].startswith('data:'), attrs['href']
        if tag == 'script':
            assert attrs.get('type') == 'application/json', 'executable script'
        for name, value in attrs.items():
            assert not name.startswith('on'), ('event handler', name)
            if name in ('src', 'srcset', 'data'):
                assert value.startswith('data:'), ('external resource', value)
        if tag == 'source' and parent == 'picture':
            assert 'srcset' in attrs and 'src' not in attrs
        if tag == 'article' and 'specimen' in attrs.get('class', '').split():
            self.boxes.append((attrs['id'], int(attrs['data-level']), int(attrs['data-feature-count'])))
        self.tags[tag] += 1
        if tag not in VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        assert tag not in VOID, ('closing void tag', tag)
        assert self.stack and self.stack[-1] == tag, ('unbalanced HTML', tag, self.stack[-5:])
        self.stack.pop()

    def handle_data(self, data):
        if self.stack and self.stack[-1] == 'style':
            self.css.append(data)


def run(*args):
    return subprocess.run([str(EXE), *map(str, args)], capture_output=True, text=True)


class GeneratorTests(unittest.TestCase):
    def generate(self, directory, name='page', **options):
        path = Path(directory) / (name + '.html')
        args = ['--out', path]
        for key, value in options.items():
            args.extend(['--' + key, value])
        result = run(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return path.read_text(), json.loads(Path(str(path) + '.json').read_text())

    def test_ocaml_internal_checks(self):
        result = run('--self-test')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_structure_context_and_complete_catalog_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            html, manifest = self.generate(directory, boxes=36, levels=9, seed=1234)
        document = Structure()
        document.feed(html)
        document.close()
        self.assertEqual(document.stack, [])
        self.assertEqual(dict(document.tags), manifest['html_tag_counts'])
        self.assertEqual(len(document.tags), manifest['html_tag_count'])
        self.assertGreaterEqual(manifest['html_tag_count'], 100)
        self.assertGreaterEqual(manifest['css_property_count'], 150)
        self.assertTrue(all(count > 0 for count in manifest['feature_usage'].values()))
        self.assertEqual(len(document.boxes), 36)
        self.assertEqual(document.tags['main'], 1)
        self.assertTrue(set(document.references) <= document.ids)
        css = ''.join(document.css)
        self.assertIn(' > *', css)
        self.assertNotIn('&gt;', css)
        rules = {}
        for index, declarations in re.findall(r'#surface-(\d+)\{([^{}]*)\}', css):
            rules.setdefault(int(index), declarations)
        for record, actual in zip(manifest['boxes'], document.boxes):
            self.assertEqual(actual, (f"box-{record['index']}", record['level'], record['feature_count']))
            self.assertEqual(len(record['feature_ids']), len(set(record['feature_ids'])))
            self.assertEqual(record['feature_count'], len(record['feature_ids']))
            self.assertEqual(record['declarations'], rules[record['index']])
            expected_properties = {feature.removeprefix('property:') for feature in record['feature_ids'] if feature.startswith('property:')}
            actual_properties = {item.split(':', 1)[0] for item in record['declarations'].split(';') if item}
            self.assertEqual(actual_properties, expected_properties)

    def test_seed_reproducibility_and_monotone_complexity(self):
        with tempfile.TemporaryDirectory() as directory:
            first, manifest = self.generate(directory, name='first', boxes=24, levels=8, seed=73)
            again, again_manifest = self.generate(directory, name='again', boxes=24, levels=8, seed=73)
            changed, changed_manifest = self.generate(directory, name='changed', boxes=24, levels=8, seed=74)
        self.assertEqual(first, again)
        self.assertEqual(manifest, again_manifest)
        self.assertNotEqual(first, changed)
        self.assertNotEqual(manifest['boxes'], changed_manifest['boxes'])
        counts = [record['feature_count'] for record in manifest['boxes']]
        self.assertEqual(counts, sorted(counts))
        self.assertEqual(counts[0], 1)
        self.assertEqual(counts[-1], manifest['feature_count'])
        self.assertLess(len(set(manifest['boxes'][0]['feature_ids']) & set(manifest['boxes'][1]['feature_ids'])), 1)

    def test_one_box_still_contains_every_feature_and_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            html, manifest = self.generate(directory, boxes=1, levels=24, seed=-1)
        self.assertEqual(manifest['level_count'], 1)
        self.assertEqual(manifest['boxes'][0]['feature_count'], manifest['feature_count'])
        document = Structure()
        document.feed(html)
        self.assertTrue(all(count > 0 for count in document.tags.values()))
        self.assertEqual(dict(document.tags), manifest['html_tag_counts'])

    def test_reject_bad_cli_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'bad.html'
            for args in [('--boxes', '0'), ('--boxes', '10001'), ('--levels', '0'), ('--levels', '257')]:
                with self.subTest(args=args):
                    result = run('--out', target, *args)
                    self.assertEqual(result.returncode, 2)
                    self.assertFalse(target.exists())
            result = run('--out', target, '--manifest', Path(directory) / '.' / 'bad.html')
            self.assertEqual(result.returncode, 2)
            self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
