---
tags: fixture
---

# Noise fixture

Expected: each line marked "flag" is reported by the rule named there, and nothing else is.

> [!Note]
> flag: no-alerts

A paragraph between the two quotes.

> A plain quote is fine.

A rocket 🚀 here. flag: no-emoji

Text symbols © ™ → ↔ are fine.

A shortcode :white_check_mark: here. flag: no-emoji

Not shortcodes: 10:30:00, std::vec::Vec, key:value:pair, Note: done, and :: alone.

---

flag: no-hr (the rule above)

One **bold** span is fine.

Two **bold** and **bold** spans. flag: bold-density (agent)

- **One** **two** **three** **four** in a list item. flag: bold-density (agent, hybrid)

See [[some-note]]. flag: no-wikilinks

Inline code is ignored: `[[not-a-link]]` and `🚀`.

```text
[[ignored]] 🚀
---
> [!Note]
```

A link [with text](builtins.md) is fine.
