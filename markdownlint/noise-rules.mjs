// Custom markdownlint rules for the Markdown profiles (profiles.nix and
// README.md in this folder): they catch the "noise" that costs an
// agent tokens and that no built-in rule covers. Every rule works on the
// micromark token tree, so code (fenced, indented, inline) and front matter
// are never inspected. Each profile turns a rule on, off, or to a warning.

// Every token in the tree, depth first.
function* walk(tokens) {
  for (const token of tokens) {
    yield token;
    yield* walk(token.children);
  }
}

function tokensOfType(params, types) {
  const wanted = new Set(types);
  return [...walk(params.parsers.micromark.tokens)].filter((t) => wanted.has(t.type));
}

// Text that is prose: "data" tokens outside code, HTML and link destinations.
const skipAncestors = new Set([
  "codeText",
  "codeFenced",
  "codeIndented",
  "htmlFlow",
  "htmlText",
  "resourceDestination",
  "autolink",
  "literalAutolink",
  "definitionDestination",
]);

function proseData(params) {
  return tokensOfType(params, ["data"]).filter((token) => {
    for (let p = token.parent; p; p = p.parent) {
      if (skipAncestors.has(p.type)) return false;
    }
    return true;
  });
}

// Prose as runs: micromark splits text at characters such as `_`, so
// adjacent data tokens on one line are joined before matching.
function proseRuns(params) {
  const runs = [];
  for (const token of proseData(params)) {
    if (token.startLine !== token.endLine) continue; // data tokens are single-line
    const last = runs.at(-1);
    if (last && last.line === token.startLine && last.endColumn === token.startColumn) {
      last.text += token.text;
      last.endColumn = token.endColumn;
    } else {
      runs.push({
        line: token.startLine,
        column: token.startColumn,
        endColumn: token.endColumn,
        text: token.text,
      });
    }
  }
  return runs;
}

// Reports each regex match inside prose text, with its column.
function reportMatches(params, onError, regex, detail) {
  for (const run of proseRuns(params)) {
    for (const match of run.text.matchAll(regex)) {
      onError({
        lineNumber: run.line,
        detail: detail(match[0]),
        context: match[0],
        range: [run.column + match.index, match[0].length],
      });
    }
  }
}

const noAlerts = {
  names: ["no-alerts"],
  description: "No alerts or callouts (> [!Note])",
  tags: ["noise"],
  parser: "micromark",
  function: (params, onError) => {
    for (const quote of tokensOfType(params, ["blockQuote"])) {
      const first = params.lines[quote.startLine - 1];
      if (/^\s*>\s*\[![A-Za-z-]+\][+-]?/.test(first)) {
        onError({ lineNumber: quote.startLine, context: first.trim() });
      }
    }
  },
};

const noEmoji = {
  names: ["no-emoji"],
  description: "No emoji",
  tags: ["noise"],
  parser: "micromark",
  // Emoji_Presentation, plus any pictograph forced to emoji style by U+FE0F.
  // Text-style symbols such as ©, ™, → and ↔ are not emoji and pass.
  // Also `:shortcode:` (forges render `:rocket:` as an emoji): at least one
  // letter between the colons and nothing word-like or another colon
  // touching them, so `10:30:00`, `std::vec` and `key:value:pair` pass.
  function: (params, onError) =>
    reportMatches(
      params,
      onError,
      /\p{Emoji_Presentation}|\p{Extended_Pictographic}️|(?<![\p{L}\p{N}_:]):(?=[a-z0-9_+-]*[a-z])[a-z0-9_+-]{1,40}:(?![\p{L}\p{N}_:])/gu,
      (m) => `Emoji: ${m}`,
    ),
};

const noHr = {
  names: ["no-hr"],
  description: "No horizontal rules",
  tags: ["noise"],
  parser: "micromark",
  function: (params, onError) => {
    for (const rule of tokensOfType(params, ["thematicBreak"])) {
      onError({ lineNumber: rule.startLine, context: rule.text });
    }
  },
};

const boldDensity = {
  names: ["bold-density"],
  description: "Too many bold spans in one paragraph or list item",
  tags: ["noise"],
  parser: "micromark",
  function: (params, onError) => {
    const max = Number.isInteger(params.config.max) ? params.config.max : 1;
    for (const paragraph of tokensOfType(params, ["paragraph"])) {
      const count = [...walk(paragraph.children)].filter((t) => t.type === "strong").length;
      if (count > max) {
        onError({
          lineNumber: paragraph.startLine,
          detail: `${count} bold spans, at most ${max}`,
        });
      }
    }
  },
};

const noWikilinks = {
  names: ["no-wikilinks"],
  description: "No wiki-links ([[name]]); use [text](relative/path.md)",
  tags: ["noise", "links"],
  parser: "micromark",
  // micromark splits "[[name]]" into label tokens, so search whole lines,
  // skipping lines that belong to code or HTML.
  function: (params, onError) => {
    const codeLines = new Set();
    for (const block of tokensOfType(params, ["codeFenced", "codeIndented", "htmlFlow"])) {
      for (let n = block.startLine; n <= block.endLine; n++) codeLines.add(n);
    }
    const inlineCode = tokensOfType(params, ["codeText"]);
    params.lines.forEach((line, index) => {
      const lineNumber = index + 1;
      if (codeLines.has(lineNumber)) return;
      for (const match of line.matchAll(/\[\[[^\]\n]+\]\]/g)) {
        const column = match.index + 1;
        const inCode = inlineCode.some(
          (c) => c.startLine === lineNumber && c.startColumn <= column && column < c.endColumn,
        );
        if (!inCode) {
          onError({ lineNumber, context: match[0], range: [column, match[0].length] });
        }
      }
    });
  },
};

export default [noAlerts, noEmoji, noHr, boldDensity, noWikilinks];
