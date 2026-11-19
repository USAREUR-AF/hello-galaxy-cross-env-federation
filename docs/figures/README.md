# Figures

`make-figures.py` draws the figure at the top of the README, `two-sovereigns`, from facts in
this repository: the README's table of stages, `STAGES.md`, `docs/what-you-will-learn.md` and `scenario/README.md`. It writes a light and a dark variant for a `<picture>`
element; the README's alt text is the figure's own `aria-label`. Standard
library only; text is measured with Helvetica's advance widths (Arial and
Liberation Sans share them), and the script refuses a label that runs into
another label or a box.

```sh
python3 -I docs/figures/make-figures.py           # write the SVG files
python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed file is out of date
```

The numbered badges are the repository's own stages. Regenerate after a change
to any of them.
