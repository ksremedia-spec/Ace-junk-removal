"""Compares the app's system prompt and JSON schema with docs/assistant-actions.md."""
import json, pathlib, re, sys, difflib

repo = sys.argv[1] if len(sys.argv) > 1 else str(pathlib.Path(__file__).resolve().parents[2])
spec = open(f"{repo}/docs/assistant-actions.md").read()
swift = open(f"{repo}/Ace/Assistant/AssistantPlan.swift").read()

# --- Prompt ---
spec_prompt = re.search(r"```text\n(You help.*?)\n```", spec, re.S).group(1)
body = re.search(r'return """\n(.*?)\n\s*"""', swift, re.S).group(1)
lines = body.split("\n")
indent = 8
app_lines = []
for line in lines:
    if line.strip() == "":
        app_lines.append("")
    else:
        assert line.startswith(" " * indent), repr(line)
        app_lines.append(line[indent:])
app_prompt = "\n".join(app_lines)
app_prompt = app_prompt.replace(r"\(today)", "{today}").replace(r"\(zone)", "{zone}").replace(r"\(time)", "{now}")
assert "\\(" not in app_prompt, "unreplaced interpolation"
assert '\\"' not in app_prompt, "escaped quote in Swift text"
if app_prompt == spec_prompt:
    print(f"PROMPT: identical ({len(app_prompt)} characters)")
else:
    print("PROMPT: DIFFERENT")
    for d in difflib.unified_diff(spec_prompt.split("\n"), app_prompt.split("\n"), "spec", "app", lineterm=""):
        print(d)

# --- Schema ---
spec_schema = json.loads(re.search(r"```json\n(\{.*?\})\n```", spec, re.S).group(1))

def props(block_name):
    block = re.search(rf"static let {block_name}: \[String: Any\] = \[\n(.*?)\n    \]", swift, re.S).group(1)
    out = {}
    for m in re.finditer(r'^\s*"(\w+)": (string|oneOf|integer)\((.*)\),\s*$', block, re.M):
        name, kind, args = m.groups()
        if kind == "string":
            d = json.loads(args) if args else ""
            p = {"type": "string"}
            if d: p["description"] = d
        elif kind == "integer":
            p = {"type": "integer", "description": json.loads(args)}
        else:
            am = re.match(r'(\[.*?\])(?:, (".*"))?$', args)
            p = {"type": "string", "enum": json.loads(am.group(1))}
            if am.group(2): p["description"] = json.loads(am.group(2))
        out[name] = p
    return out

def strlist(name):
    block = re.search(rf"static let {name}: \[String\] = \[(.*?)\]", swift, re.S).group(1)
    return re.findall(r'"(\w+)"', block)

ok = True
spec_action = spec_schema["properties"]["actions"]["items"]
spec_issue = spec_schema["properties"]["issues"]["items"]
for label, app, want in [
    ("action properties", props("actionProperties"), spec_action["properties"]),
    ("issue properties", props("issueProperties"), spec_issue["properties"]),
]:
    if app != want:
        ok = False
        print(f"SCHEMA {label}: DIFFERENT")
        for k in sorted(set(app) | set(want)):
            if app.get(k) != want.get(k):
                print("  ", k, "\n     app :", app.get(k), "\n     spec:", want.get(k))
for label, app, want in [
    ("action required", strlist("actionRequired"), spec_action["required"]),
    ("issue required", strlist("issueRequired"), spec_issue["required"]),
]:
    if app != want:
        ok = False
        print(f"SCHEMA {label}: DIFFERENT\n   app : {app}\n   spec: {want}")
reply = re.search(r'replyDescription = (".*")', swift).group(1)
if json.loads(reply) != spec_schema["properties"]["reply"]["description"]:
    ok = False
    print("SCHEMA reply description: DIFFERENT")
print("SCHEMA: identical" if ok else "SCHEMA: see differences above")
print("action properties counted:", len(props("actionProperties")), "spec:", len(spec_action["properties"]))
