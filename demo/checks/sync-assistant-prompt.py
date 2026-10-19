"""Copies the Assistant's instructions and answer shape from
docs/assistant-actions.md into the demo (PLAN_PROMPT and PLAN_SCHEMA in
demo/app-demo/index.html), so the demo and the app send Claude the same text.
Run it after changing the spec, then run check-contract.py for the app."""
import json, pathlib, re

repo = pathlib.Path(__file__).resolve().parents[2]
spec = (repo / 'docs/assistant-actions.md').read_text()
schema = json.loads(re.search(r"```json\n(.*?)\n```", spec, re.S).group(1))
prompt = re.search(r"## The instructions sent to Claude \(system prompt\).*?```text\n(.*?)\n```", spec, re.S).group(1)

page = repo / 'demo/app-demo/index.html'
lines = page.read_text(encoding='utf-8').split('\n')
for prefix, value in (('  const PLAN_SCHEMA = ', schema), ('  const PLAN_PROMPT = ', prompt)):
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        raise SystemExit(f'{prefix.strip()}: expected one line, found {len(hits)}')
    lines[hits[0]] = prefix + json.dumps(value) + ';'
page.write_text('\n'.join(lines), encoding='utf-8')
print('Demo instructions and answer shape now match docs/assistant-actions.md.')
