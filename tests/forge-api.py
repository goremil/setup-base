"""A stand-in for GitHub's rulesets API, for the forge-ruleset test: rulesets in
memory per repository, `o/private` answering as a private repository on GitHub
Free, `o/drift` starting with a ruleset that differs from ruleset.json."""

import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer

store: dict[str, dict[int, dict]] = {
    "o/drift": {
        1: {
            "id": 1,
            "name": "signed commits",
            "target": "branch",
            "enforcement": "evaluate",
            "conditions": {},
            "rules": [],
            "bypass_actors": [],
        }
    }
}
PATH = re.compile(r"/repos/([^/]+/[^/]+)/rulesets(?:/(\d+))?$")


class Handler(BaseHTTPRequestHandler):
    def reply(self, code: int, body: object) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def target(self) -> tuple[str, int | None]:
        m = PATH.match(self.path)
        assert m
        return m[1], int(m[2]) if m[2] else None

    def body(self) -> dict:
        return json.loads(self.rfile.read(int(self.headers["Content-Length"])))

    def do_GET(self) -> None:
        repo, ident = self.target()
        if repo == "o/private":
            self.reply(403, {"message": "Upgrade to GitHub Pro"})
            return
        sets = store.setdefault(repo, {})
        if ident:
            self.reply(200, sets[ident])
        else:
            self.reply(200, [{"id": i, "name": r["name"]} for i, r in sets.items()])

    def do_POST(self) -> None:
        repo, _ = self.target()
        sets = store.setdefault(repo, {})
        ident = len(sets) + 1
        sets[ident] = dict(self.body(), id=ident)
        self.reply(201, sets[ident])

    def do_PUT(self) -> None:
        repo, ident = self.target()
        assert ident
        store[repo][ident] = dict(self.body(), id=ident)
        self.reply(200, {})


HTTPServer(("127.0.0.1", 8768), Handler).serve_forever()
