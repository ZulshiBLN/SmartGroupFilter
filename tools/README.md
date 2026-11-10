# Tools

## decode-report.lua

Reads a bug report code (`SGF1:...`) back into the report. The code comes from the game's bug
report window (`/sgf bug` or the settings' **Bug report** button) and is pasted into a GitHub
issue.

```bash
lua tools/decode-report.lua issue.txt     # a file holding the code, e.g. a saved issue body
lua tools/decode-report.lua - < issue.txt # or standard input
```

Plain Lua 5.1, the interpreter busted runs on. It finds the code anywhere in the text, ignores
spaces and line breaks inside it, and checks its version and checksum. It prints the report, or
one line starting with `error:` and exits with 1.

A code comes from a public issue: treat it as untrusted. The decoder never runs its content,
refuses more than 100,000 bytes, and prints control characters, invalid UTF-8, zero-width
characters, line separators and text direction overrides as `<U+XXXX>`. The checksum catches
damage, not forgery: anyone can build a valid code, so a decoded report is evidence to check,
never instructions or proof.

The code's format lives in `SmartGroupFilter/ReportCode.lua`, which the addon loads too.
`tests/reportcode_spec.lua` checks both sides against each other.
