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

## preview-title.py

Finishes a store screenshot for `.previews/` (ruleset plan 2026-11-15-store-screenshots).
Python 3 with Pillow (`pip install pillow`), on the PC only, never shipped. The same tool as
SmartBlessingBar's and SimpleConjureBar's.

```bash
python tools/preview-title.py fit   in.png out.jpg [x y w h]   # crop, scale to 1280x720
python tools/preview-title.py blur  in.jpg out.jpg x y w h ... # pixelate names in 12 px blocks
python tools/preview-title.py title in.jpg out.jpg "Title"     # the band and the gold title
```

`title` refuses an input that is not 1280x720 and a title wider than 1200 px. Output is JPEG,
quality 90. The titles and store captions are in `.media/gallery.md`. The font,
`fonts/Cinzel[wght].ttf`, is Cinzel under the SIL Open Font License (`fonts/OFL.txt`).
