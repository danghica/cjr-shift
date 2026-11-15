"""Elaborated-term fidelity, readable layout, and migration compatibility."""
from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.rocq_readable.ast import Declaration
from tools.rocq_readable.backend import Backend, BackendError
from tools.rocq_readable.cli import DEFAULT_DICTIONARY, generate, main, prepare
from tools.rocq_readable.dictionary import Dictionary
from tools.rocq_readable.elaboration import export
from tools.rocq_readable.explanations import Options
from tools.rocq_readable.layout import Doc, Token, anchor, leaf, render_html
from tools.rocq_readable.project import Glob, Source
from tools.rocq_readable.terms import Renderer, application, block
from test_rocq_readable import audit_links, backend_available

ROOT = Path(__file__).resolve().parents[1]


def nodes(term):
    if isinstance(term, dict):
        if 'tag' in term:
            yield term
        for child in term.values():
            yield from nodes(child)
    elif isinstance(term, list):
        for child in term:
            yield from nodes(child)


class LayoutMigration(unittest.TestCase):
    def test_match_patterns_distinguish_fields_from_returned_functions(self):
        ref = lambda identity: {'tag': 'ref', 'identity': identity}
        lam = lambda name, body: {'tag': 'lambda', 'name': name, 'type': ref('Test.T'), 'body': body}
        node = {'tag': 'match', 'scrutinee': ref('Test.input'),
                'return': lam('_', ref('Test.T')), 'indices': [],
                'branches': [{'constructor': 'Test.Box', 'binder_count': 1,
                              'body': lam('x', lam('x', {'tag': 'rel', 'index': 2}))}]}
        decl = Declaration('branch', 'Test.branch', 'definition', {}, '')
        renderer = Renderer(decl, Dictionary(DEFAULT_DICTIONARY))
        doc = renderer.term(node, [])
        self.assertIn('when Box(x):\n    function x2: T\n      x', doc.plain())
        self.assertNotIn('return:', doc.plain())
        details = '\n'.join(d.plain() for d in renderer.hidden)
        self.assertIn('pattern binding:', details)
        self.assertIn('match return type:', details)
        target = Path('/tmp/match.html')
        rendered = render_html(doc, target, {}) + ''.join(render_html(d, target, {}) for d in renderer.hidden)
        import re
        self.assertEqual(len(re.findall(r' id="', rendered)), len(set(re.findall(r' id="([^"]+)"', rendered))))
        for destination in re.findall(r'href="#([^"]+)"', rendered):
            self.assertIn('id="' + destination + '"', rendered)
        # Old exports with unknown constructors retain all lambda structure.
        del node['branches'][0]['binder_count']
        fallback = Renderer(decl, Dictionary(DEFAULT_DICTIONARY)).term(node, []).plain()
        self.assertIn('when Box:\n    function x: T', fallback)
        node['branches'] = [{'constructor': 'Coq.Init.Datatypes.true', 'binder_count': 0,
                             'body': lam('x', {'tag': 'rel', 'index': 1})}]
        nullary = Renderer(decl, Dictionary(DEFAULT_DICTIONARY)).term(node, []).plain()
        self.assertIn('when true:\n    function x: T\n      x', nullary)

    def test_dependent_match_return_types_remain_visible(self):
        ref = lambda identity: {'tag': 'ref', 'identity': identity}
        node = {'tag': 'match', 'scrutinee': ref('Test.input'), 'indices': [],
                'return': {'tag': 'lambda', 'name': 'value', 'type': ref('Test.T'),
                           'body': {'tag': 'rel', 'index': 1}},
                'branches': [{'constructor': 'Coq.Init.Datatypes.Some',
                              'body': {'tag': 'lambda', 'name': 'p', 'type': ref('Test.T'),
                                       'body': {'tag': 'rel', 'index': 1}}}]}
        decl = Declaration('branch', 'Test.branch', 'definition', {}, '')
        doc = Renderer(decl, Dictionary(DEFAULT_DICTIONARY)).term(node, [])
        self.assertIn('return:\n    function value: T\n      value', doc.plain())
        self.assertIn('when Some(p):\n    p', doc.plain())
        narrow = '\n'.join(''.join(t.text for t in ts) for _, ts in doc.lines(width=14))
        self.assertIn('when:\npattern:\nSome(p)\nbody:\np', narrow)

    def test_nested_program_conditions_keep_scope_and_links(self):
        def ref(identity):
            return {'tag': 'ref', 'identity': identity}
        def app(identity, *arguments):
            return {'tag': 'app', 'head': ref(identity),
                    'arguments': [{'implicit': False, 'term': a} for a in arguments]}
        comparison = app('cjr.lang.BinOp', ref('cjr.lang.LeOp'), ref('Test.minute'), ref('Test.limit'))
        inner = app('cjr.lang.If', comparison, ref('Coq.Init.Datatypes.false'), ref('Coq.Init.Datatypes.true'))
        term = app('cjr.lang.If', inner, ref('Test.reject'), ref('Test.accept'))
        declaration = Declaration('branch', 'Test.branch', 'definition', {}, '')
        outer = Renderer(declaration, Dictionary(DEFAULT_DICTIONARY)).term(term, [])
        self.assertEqual(outer.plain(),
                         'if:\n  condition:\n    if (minute ≤ limit):\n      false\n'
                         '    else:\n      true\n  then:\n    reject\n  else:\n    accept')
        target = Path('/tmp/conditional.html')
        rendered = render_html(outer, target, {'cjr.lang.If': (target, 'if-constructor')})
        self.assertIn('href="#if-constructor" title="cjr.lang.If">condition:', rendered)
        self.assertIn('│ │ <a href="#if-constructor" title="cjr.lang.If">if ', rendered)
        self.assertNotIn('\n│ :', rendered)

    def test_program_condition_uses_available_header_width(self):
        from tools.rocq_readable.program_syntax import Conditional
        doc = Conditional(Token(''), [leaf('ready'), leaf('yes'), leaf('no')],
                          template='if {0}:\n  {1}\nelse:\n  {2}',
                          template_indent=2, plain_indent=2)
        self.assertEqual(''.join(t.text for t in doc.lines(width=9)[0][1]), 'if ready:')
        for indent, width in [(0, 8), (1, 10)]:
            lines = doc.lines(indent=indent, width=width)
            self.assertEqual(''.join(t.text for t in lines[0][1]), 'if:')
            self.assertEqual(''.join(t.text for t in lines[1][1]), 'condition:')
            self.assertFalse(any(''.join(t.text for t in tokens) == ':' for _, tokens in lines))

    def test_html_has_scope_guides_while_legacy_cache_input_is_unchanged(self):
        doc = Doc(Token('a'), [Doc(Token('b'), [leaf('c')], block=True)], block=True)
        self.assertEqual(doc.plain(), 'a:\n    b:\n        c')
        self.assertEqual(doc.plain(indent_size=2), 'a:\n  b:\n    c')
        self.assertEqual(render_html(doc, Path('/tmp/a.html'), {}), 'a:\n│ b:\n│ │ c')

    def test_old_and_new_templates_display_with_scope_guides(self):
        dictionary = Dictionary(DEFAULT_DICTIONARY)
        for spaces in (2, 4):
            rule = {'kind': 'application', 'key': 'Test.f', 'arity': 1,
                    'label': 'f', 'template': 'f:\n' + ' ' * spaces + '{0}'}
            dictionary.replace(rule)
            doc = dictionary.apply(dictionary.match('application', 'Test.f', 1), Token('f'), [leaf('value')])
            self.assertEqual(render_html(doc, Path('/tmp/a.html'), {}), 'f:\n│ value')

    def test_export_failure_keeps_a_reason_and_no_stale_term(self):
        source = Source(Path('/tmp/S.v'), Path('/tmp'), '', 'S', Glob())
        source.declarations = [Declaration('f', 'S.f', 'definition', {}, '', body={})]
        class Failing:
            def request(self, *args):
                raise BackendError('query timeout')
        export(Failing(), source)
        self.assertEqual(source.elaborated['S.f']['status'], 'unavailable')
        self.assertIn('query timeout', source.elaborated['S.f']['reason'])


@unittest.skipUnless(backend_available(), 'requires pinned coq-lsp')
class ElaboratedIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temporary.name).resolve()
        (cls.root / '_CoqProject').write_text('-Q . Skin\n' +
            '\n'.join(line for line in (ROOT / '_CoqProject').read_text().splitlines() if line.startswith(('-Q ', '-R '))))
        cls.path = cls.root / 'Skin.v'
        cls.path.write_text(r'''From Coq Require Import List String.
From iris.proofmode Require Import proofmode.
From iris.bi Require Import weakestpre.
From cjr Require Import primitive_laws notation adequacy.
Definition raw_ownership `{!cjrGS Σ} l v : iProp Σ := cjr.primitive_laws.raw_mapsto l v.
Definition slot_ownership `{!cjrGS Σ} l v : iProp Σ := cjr.primitive_laws.stack_mapsto l v.
Definition field_ownership `{!cjrGS Σ} o i v : iProp Σ := cjr.primitive_laws.obj_mapsto o i v.
Definition block_ownership `{!cjrGS Σ} l n : iProp Σ := cjr.primitive_laws.block_mapsto l n.
Definition pointer_call (p : Z) : expr :=
  Let (Some "f") (Rec None (Some "x") (Store (Var "x") (Val (LitV (LitInt 9)))))
    (App (Var "f") (Val (LitV (LitPtr p)))).
Definition recursive_program : expr := Rec (Some "again") (Some "x") (App (Var "again") (Var "x")).
Definition same_name_program : expr := Rec (Some "f") (Some "f") (Var "f").
Definition shadow_program : expr := Let (Some "x") (Val (LitV (LitInt 1)))
  (Let (Some "x") (Var "x") (Var "x")).
Definition unusual_program : expr := Rec None (Some "x-y") (Var "x-y").
Definition anonymous_program : expr := Let None (Val (LitV LitUnit)) (Rec None None (Val (LitV LitUnit))).
Definition aggregate_program : expr := VarBind "s" (Struct [LitV (LitInt 1)] [Val (LitV (LitInt 2))])
  (Let (Some "o") (New [] [Val (LitV (LitInt 3))])
    (Seq (StructStore "s" 1 (Val (LitV (LitInt 4))))
      (Seq (FieldStore (Var "o") 0 (Val (LitV (LitInt 5))))
        (App (StructLoad (Var "s") 1) (FieldLoad (Var "o") 0))))).
Definition empty_struct : expr := Struct [] [].
Definition empty_struct_value : val := StructV [].
Definition empty_struct_reference (struct : expr) : expr := struct.
Definition option_match (p : option nat) := match p with Some x => x | None => O end.
Inductive carrier := Carry : nat -> carrier.
Definition carrier_function (c : carrier) := match c with Carry n => fun x : nat => n + x end.
Definition dependent_match (b : bool) : if b then nat else bool :=
  match b as value return (if value then nat else bool) with true => O | false => false end.
Definition symbolic_aggregate (vs : list val) (es : list expr) : expr := Struct vs es.
Definition symbolic_program (name : string) : expr := Var name.
Definition value_type := iris.program_logic.language.val cjr_lang.
Definition state_type := iris.program_logic.language.state cjr_lang.
Definition adequacy_post (e : expr) := adequate NotStuck e state_init (fun (v : val) (s : state) => v = LitV LitUnit /\ s = state_init).
Definition adequacy_unused (e : expr) := adequate NotStuck e state_init (fun (v : val) (_ : state) => v = LitV LitUnit).
Lemma reflexive (n : nat) : n = n. Proof. reflexivity. Qed.
Definition inferred {A : Type} (x : A) := x.
Definition implies (P Q : Prop) : Prop := P -> Q.
Definition function_type := nat -> nat.
Definition dependent (A : Type) (x : A) : {y : A | y = x} := exist _ x eq_refl.
Definition shadow (x : nat) := fun x : nat => x.
Fixpoint size (xs : list nat) : nat := match xs with nil => 0 | cons _ rest => S (size rest) end.
Inductive color := Red | Blue.
Record box := Box { item : nat; flag : bool }.
CoInductive stream := Next : nat -> stream -> stream.
CoFixpoint zeros : stream := Next 0 zeros.
Definition use_constructor := Red.
Definition use_field (b : box) := item b.
Definition logic {PROP : bi} (P Q : PROP) : PROP := ((P -∗ Q) ∧ (P ∗ Q) ∧ <pers> P ∧ ▷ Q ∧ ⌜True⌝)%I.
Definition quantified {PROP : bi} (Ψ : nat -> PROP) : PROP := (∀ n : nat, ∃ m : nat, Ψ (n + m)%nat)%I.
Definition update {PROP : bi} `{!BiFUpd PROP} (P : PROP) : PROP := (|={⊤, ∅}=> P)%I.
Definition entail {PROP : bi} (P Q : PROP) : Prop := P ⊢ Q.
Definition wp_default {PROP : bi} `{!Wp PROP nat nat stuckness} (e : nat) (Φ : nat -> PROP) : PROP := (WP e {{ n, Φ n }})%I.
Definition wp_explicit {PROP : bi} `{!Wp PROP nat nat stuckness} (e : nat) (Φ : nat -> PROP) : PROP := (WP e @ MaybeStuck; ∅ {{ n, Φ n }})%I.
Definition twp_explicit {PROP : bi} `{!Twp PROP nat nat stuckness} (e : nat) (Φ : nat -> PROP) : PROP := (WP e @ MaybeStuck; ∅ [{ n, Φ n }])%I.
Module Foreign.
Definition bi_wand (P Q : Prop) := P /\ Q.
End Foreign.
Definition unrelated (P Q : Prop) := Foreign.bi_wand P Q.
Definition literal := "text"%string.
Section Local.
Context (A : Type) (x : A).
Definition in_section := x.
End Local.
''')
        import subprocess, shlex
        from tools.rocq_readable.backend import executable
        flags = shlex.split((cls.root / '_CoqProject').read_text())
        subprocess.run([str(Path(executable()).with_name('coqc')), *flags, str(cls.path)],
                       cwd=cls.root, check=True, capture_output=True, timeout=60)
        with redirect_stderr(io.StringIO()):
            cls.sources, cls.resolutions = prepare([cls.path], cls.root, 30)
        if cls.sources[0].errors:
            raise AssertionError(cls.sources[0].errors)
        cls.dictionary = Dictionary(DEFAULT_DICTIONARY)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def render(self, name):
        source = self.sources[0]
        decl = next(d for d in source.declarations if d.name == name)
        record = source.elaborated[decl.identity]
        self.assertEqual(record['status'], 'available', record.get('reason'))
        renderer = Renderer(decl, self.dictionary)
        doc = renderer.document(record)
        self.assertEqual(renderer.unsupported, [])
        self.assertEqual(doc.plain(), doc.plain(indent_size=2))
        return doc.plain(), record, renderer

    def test_contextual_program_syntax_and_scoped_names(self):
        text, _, _ = self.render('pointer_call')
        self.assertIn('let f = function(x):\n      store 9 at x', text)
        self.assertIn('f(pointer(p))', text)
        for internal in ('Some(', 'None', 'unsafe', 'requires runtime or layout metadata', '"f"', '"x"'):
            self.assertNotIn(internal, text)
        self.assertIn('recursive function again(x):', self.render('recursive_program')[0])
        self.assertIn('again(x)', self.render('recursive_program')[0])
        self.assertIn('recursive function f(f2):\n      f', self.render('same_name_program')[0])
        self.assertIn('let x2 = x', self.render('shadow_program')[0])
        self.assertIn('function(`x-y`):', self.render('unusual_program')[0])
        self.assertIn('function(_):', self.render('anonymous_program')[0])
        self.assertNotIn('let ', self.render('anonymous_program')[0])
        self.assertIn('"text"', self.render('literal')[0])

    def test_object_and_struct_syntax_preserves_fields_and_order(self):
        text, _, _ = self.render('aggregate_program')
        for expected in ('var s = struct(1, 2)', 'let o = new object(3)',
                         'store 4 in item(s, 1)', 'store 5 in field(o, 0)', 'item(s, 1)(field(o, 0))'):
            self.assertIn(expected, text)
        self.assertLess(text.index('store 4'), text.index('store 5'))
        symbolic = self.render('symbolic_aggregate')[0]
        self.assertIn('values:', symbolic)
        self.assertIn('pending expressions:', symbolic)
        source = self.sources[0]
        decl = next(d for d in source.declarations if d.name == 'symbolic_program')
        renderer = Renderer(decl, self.dictionary)
        text = renderer.document(source.elaborated[decl.identity]).plain()
        self.assertIn('symbolic variable name', text)
        self.assertIn('name', text)
        self.assertTrue(renderer.unsupported)

    def test_empty_structs_remain_constructor_calls_in_both_views(self):
        from html import unescape
        import re
        self.assertIn('struct()', self.render('empty_struct')[0])
        self.assertIn('struct()', self.render('empty_struct_value')[0])
        reference = self.render('empty_struct_reference')[0]
        self.assertIn('definition:\n    struct', reference)
        self.assertNotIn('struct()', reference)
        output = self.root / 'empty-struct-source-html'
        generate(self.sources, self.resolutions, self.dictionary, output, term_view='source')
        page = (output / 'Skin.html').read_text()
        for name in ('empty_struct', 'empty_struct_value', 'empty_struct_reference'):
            declaration = next(d for d in self.sources[0].declarations if d.name == name)
            article = page.split('<article id="' + anchor(declaration.identity) + '">', 1)[1].split('</article>', 1)[0]
            pre = re.search(r'<pre class="pseudocode">(.*?)</pre>', article, re.S)[1]
            text = unescape(re.sub('<[^>]*>', '', pre))
            if name == 'empty_struct_reference':
                self.assertNotIn('struct()', text)
            else:
                self.assertIn('struct()', text)
        audit_links(output)

    def test_lemma_headings_and_postconditions(self):
        source = self.sources[0]
        from dataclasses import replace
        decl = next(d for d in source.declarations if d.name == 'reflexive')
        statement = source.elaborated[decl.identity].copy()
        statement['term'] = {**statement['term'], 'body': None}
        for kind in ('lemma', 'theorem', 'corollary', 'proposition', 'fact', 'remark'):
            text = Renderer(replace(decl, kind=kind), self.dictionary).document(statement).plain()
            self.assertNotIn('\n  type:', text)
            self.assertLess(text.index('parameters:'), text.index('n = n'))
        _, record, renderer = self.render('shadow')
        self.assertIn('function', renderer.term(record['term']['body'], []).plain())
        self.assertIn('on return n:', self.render('wp_default')[0])
        text, _, renderer = self.render('adequacy_post')
        self.assertIn('on return v, in state s:', text)
        self.assertIn('CJR state', '\n'.join(d.plain() for d in renderer.hidden))
        text, _, _ = self.render('adequacy_unused')
        self.assertIn('on return v:', text)
        self.assertNotIn('in state', text)

    def test_explicit_custom_dictionary_rules_precede_program_skin(self):
        source = self.sources[0]
        decl = next(d for d in source.declarations if d.name == 'pointer_call')
        dictionary = Dictionary(self.root / 'custom-program.json')
        dictionary.replace({'kind': 'application', 'key': 'cjr.lang.Store', 'arity': 2,
                            'label': 'write_custom', 'slots': [0, 1]})
        renderer = Renderer(decl, dictionary)
        text = renderer.document(source.elaborated[decl.identity]).plain()
        self.assertIn('write_custom(x, 9)', text)
        self.assertNotIn('store 9 at x', text)
        from tools.rocq_readable.display import DisplayAdapter
        adapter = DisplayAdapter(source, dictionary, {d.identity for d in source.declarations})
        self.assertIn('write_custom', adapter.declaration(decl).plain())

    def test_type_aliases_and_source_display(self):
        self.assertIn('CJR value', self.render('value_type')[0])
        self.assertIn('CJR state', self.render('state_type')[0])
        from tools.rocq_readable.program_syntax import type_alias
        self.assertIsNone(type_alias('Other.val', [], lambda x: (x, [])))
        self.assertIsNone(type_alias('iris.program_logic.language.val', ['Other.language'], lambda x: (x, [])))
        output = self.root / 'program-source-html'
        generate(self.sources, self.resolutions, self.dictionary, output, term_view='source')
        audit_links(output)
        page = (output / 'Skin.html').read_text()
        self.assertNotIn('requires runtime or layout metadata', page)
        report = json.loads((output / 'report.json').read_text())
        self.assertNotIn('requires runtime or layout metadata', json.dumps(report['files']))
        self.assertIn('pointer', page)
        self.assertIn('on return', page)

    def test_ownership_wording_keeps_field_contents_in_details(self):
        for name, expected in [('raw_ownership', 'owns l ↦ v'),
                               ('slot_ownership', 'owns slot l ↦ v'),
                               ('field_ownership', 'owns field i of o'),
                               ('block_ownership', 'owns block l of length n')]:
            text, _, renderer = self.render(name)
            self.assertIn(expected, text)
            self.assertNotIn('owns_', text)
            if name == 'field_ownership':
                self.assertIn('field i of o stores v', '\n'.join(d.plain() for d in renderer.hidden))
        output = self.root / 'ownership-source-html'
        generate(self.sources, self.resolutions, self.dictionary, output, term_view='source')
        page = (output / 'Skin.html').read_text()
        self.assertIn('Stored field values', page)
        self.assertNotIn('owns_raw', page)
        audit_links(output)

    def test_inferred_dependent_and_implicit_types(self):
        text, record, renderer = self.render('inferred')
        self.assertIn('x: A', text)
        self.assertNotIn('A: Type', text)
        self.assertTrue(renderer.hidden)
        self.assertTrue(record['term']['type']['implicit'])
        self.assertIn('sig', self.render('dependent')[0])
        self.assertIn('context:', self.render('in_section')[0])

    def test_typed_implication_and_function_types_remain_distinct(self):
        self.assertIn('if:', self.render('implies')[0])
        self.assertIn('then:', self.render('implies')[0])
        self.assertIn('function type', self.render('function_type')[0])

    def test_iris_connectives_updates_and_identity_matching(self):
        text, record, _ = self.render('logic')
        for label in ('resource promise', 'separately', 'both', 'persistent', 'later', 'pure'):
            self.assertIn(label, text)
        text, _, _ = self.render('quantified')
        self.assertIn('every', text)
        self.assertIn('exists', text)
        self.assertNotIn('forall', text)
        self.assertIn('from mask:', self.render('update')[0])
        self.assertIn('to mask:', self.render('update')[0])
        self.assertNotIn('resource promise', self.render('unrelated')[0])
        self.assertIn('entails:', self.render('entail')[0])
        # Projection instance arguments are retained in exported data.
        self.assertTrue(any(n['tag'] == 'projection' and n.get('identity', '').endswith('.bi_wand')
                            and 'value' in n for n in nodes(record)))

    def test_recursion_patterns_shadowing_literals_and_links(self):
        self.assertIn('match:', self.render('size')[0])
        self.assertIn('recursive function', self.render('size')[0])
        self.assertIn('corecursive function', self.render('zeros')[0])
        self.assertIn('x2', self.render('shadow')[0])
        self.assertIn('"text"', self.render('literal')[0])
        output = self.root / 'elaborated-html'
        generate(self.sources, self.resolutions, self.dictionary, output)
        audit_links(output)
        page = (output / 'Skin.html').read_text()
        self.assertIn('Complete resolved term data', page)
        self.assertIn('Parsed source structure', page)
        self.assertNotIn('Source-view fallback', page)

    def test_constructor_patterns_and_dependent_motives(self):
        text, record, renderer = self.render('option_match')
        self.assertIn('when Some(x):', text)
        self.assertNotIn('return:', text)
        self.assertIn('match return type:', '\n'.join(d.plain() for d in renderer.hidden))
        matches = [n for n in nodes(record) if n['tag'] == 'match']
        self.assertEqual([b['binder_count'] for b in matches[0]['branches']], [1, 0])
        text = self.render('carrier_function')[0]
        self.assertIn('when Carry(n):\n', text)
        self.assertIn('function x: nat', text)
        self.assertNotIn('when Carry(n, x)', text)
        self.assertIn('return:', self.render('dependent_match')[0])

    def test_explanation_cache_survives_migration_byte_for_byte(self):
        output = self.root / 'cache-html'
        cache = self.root / 'existing-explanations.json'
        with patch('tools.rocq_readable.explanations.shutil.which', return_value='/codex'), \
             patch('tools.rocq_readable.explanations.query', return_value='Existing explanation.'):
            generate(self.sources, self.resolutions, self.dictionary, output,
                     explanation_options=Options('auto', cache=cache), term_view='source')
        original = cache.read_bytes()
        with patch('tools.rocq_readable.explanations.shutil.which', return_value='/codex'), \
             patch('tools.rocq_readable.explanations.query') as query:
            generate(self.sources, self.resolutions, self.dictionary, output,
                     explanation_options=Options('auto', cache=cache))
            query.assert_not_called()
        self.assertEqual(cache.read_bytes(), original)
        generate(self.sources, self.resolutions, self.dictionary, output,
                 explanation_options=Options('offline', cache=cache))
        self.assertEqual(cache.read_bytes(), original)
        report = json.loads((output / 'report.json').read_text())
        self.assertTrue(all(r['status'] == 'available' for r in report['explanations']['declarations'].values()))
        before = {p.name: p.read_bytes() for p in output.glob('*') if p.is_file()}
        generate(self.sources, self.resolutions, self.dictionary, output,
                 explanation_options=Options('offline', cache=cache))
        self.assertEqual(before, {p.name: p.read_bytes() for p in output.glob('*') if p.is_file()})

    def test_standalone_stops_before_unfinished_proof_and_uses_live_edits(self):
        path = self.root / 'Unfinished.v'
        path.write_text('Lemma law (x : nat) : x = x.\nProof. unknown_tactic.\n')
        with redirect_stderr(io.StringIO()):
            sources, _ = prepare([path], self.root, 30, selected='law')
        self.assertEqual(sources[0].errors, [])
        self.assertEqual(sources[0].elaborated['Skin.Unfinished.law']['status'], 'available')
        path.write_text('Definition law : bool := true.\n')
        with redirect_stderr(io.StringIO()):
            sources, _ = prepare([path], self.root, 30, selected='law')
        self.assertEqual(sources[0].elaborated['Skin.Unfinished.law']['term']['type']['identity'], 'Coq.Init.Datatypes.bool')

    def test_plugin_unavailable_falls_back_and_strict_returns_failure(self):
        output = self.root / 'fallback-html'
        with patch('tools.rocq_readable.plugin.build.build', side_effect=RuntimeError('plugin missing')), \
             patch('pathlib.Path.cwd', return_value=self.root), redirect_stderr(io.StringIO()):
            result = main(['build', '--sources', str(self.path), '--output', str(output), '--strict', '--explanations', 'offline'])
        self.assertEqual(result, 1)
        self.assertIn('Source-view fallback', (output / 'Skin.html').read_text())
        audit_links(output)

    def test_default_wp_mask_and_safety_use_plain_language(self):
        text, record, _ = self.render('wp_default')
        self.assertIn('invariant access: unrestricted', text)
        self.assertIn('safety: cannot get stuck', text)
        self.assertNotIn('stuckness:', text)
        self.assertNotIn('mask:', text)
        self.assertIn('iris.bi.weakestpre.NotStuck', json.dumps(record))
        self.assertIn('stdpp.coPset.coPset_top', json.dumps(record))

    def test_explicit_wp_and_twp_masks_stuckness_and_binders(self):
        for name, correctness in [('wp_explicit', 'partial correctness'), ('twp_explicit', 'total correctness')]:
            text, record, _ = self.render(name)
            self.assertIn(correctness + ':', text)
            self.assertIn('MaybeStuck', text)
            self.assertIn('empty', text)
            self.assertIn('on return n:', text)
            self.assertIn('Φ(n)', text)
            self.assertNotIn('top', text)

    def test_wp_masks_and_postcondition_binders(self):
        path = ROOT / 'example/misc/rocq/swap.v'
        with redirect_stderr(io.StringIO()):
            sources, _ = prepare([path], ROOT, 30, selected='swap_wp')
        source = sources[0]
        decl = next(d for d in source.declarations if d.name == 'swap_wp')
        record = source.elaborated[decl.identity]
        self.assertEqual(record['status'], 'available')
        renderer = Renderer(decl, self.dictionary)
        text = renderer.document(record).plain(indent_size=2)
        for label in ('partial correctness:', 'requires (resource promises):', 'invariant access: unrestricted', 'safety: cannot get stuck', 'execute:', 'ensures:', 'on return result:', 'separately:'):
            self.assertIn(label, text)
        self.assertNotIn('total correctness', text)
        self.assertIn('v1: CJR value', text)
        self.assertIn('v2: CJR value', text)
