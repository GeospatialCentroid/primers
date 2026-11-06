# *(Adapted)* R Primers

A [Quarto](https://quarto.org) website of interactive introductory R tutorials, hosted on GitHub Pages at <https://geospatialcentroid.github.io/primers/>.

Lessons are adapted from the [RStudio Cloud Primers](https://github.com/rstudio-education/primers) under their [CC BY-SA 4.0 license](https://creativecommons.org/licenses/by-sa/4.0/). Some content is also derived from *R for Data Science* (O'Reilly Media, Inc., © 2017 Garrett Grolemund, Hadley Wickham), used with permission.

Code exercises run R directly in the learner's browser using [webR](https://docs.r-wasm.org/webr/latest/) through the [quarto-live](https://r-wasm.github.io/quarto-live/) extension, so no Shiny server is needed.

## Layout

```
_quarto.yml              site config, navbar, theme
index.qmd                home page (lesson cards)
assets/styles.scss       site styles
assets/quiz.html         multiple-choice quiz widget (replaces learnr::question)
lessons/_metadata.yml    shared options for every lesson page
lessons/_setup.qmd       shared setup, included at the top of each lesson
lessons/<section>/*.qmd  one file per lesson (images in <lesson>-files/)
tools/convert-learnr.R   converts a learnr .Rmd into a lesson .qmd
tools/patch-quarto-live.py  local patch to quarto-live (see below)
_extensions/r-wasm/live  quarto-live extension (patched)
.github/workflows/       builds and deploys to GitHub Pages on push to main
```

## Writing a lesson

New lessons can start from a learnr tutorial:

```bash
Rscript tools/convert-learnr.R path/to/lesson.Rmd lessons/<section>/<name>.qmd "Section · Lesson N"
```

Review the output by hand. The converter warns about questions with no correct answer, and doesn't fix code chunks indented inside lists, images (copy them into `<name>-files/` and update the paths), or lesson text that assumes a package is *not* loaded (every package under `webr: packages` is attached).

Each lesson starts with front matter like this:

````markdown
---
title: "Lesson title"
format: live-html
webr:
  packages: [ggplot2, dplyr]   # installed + attached in the browser
  cell-options:
    timelimit: 300             # keep: the 30 s default is too short for big data
---

{{< include ../_setup.qmd >}}
````

`cell-options` must be in each lesson. A lesson's `webr:` block replaces, rather than merges with, one in `lessons/_metadata.yml`.

| learnr | Quarto equivalent |
|---|---|
| ```` ```{r ex1, exercise = TRUE} ```` | ```` ```{webr} ```` + `#| exercise: ex1` |
| ```` ```{r ex1-setup} ```` / `exercise.setup` | ```` ```{webr} ```` + `#| exercise: ex1` + `#| setup: true` |
| ```` ```{r ex1-solution} ```` | ```` ```{webr} ```` + `#| exercise: ex1` + `#| solution: true` |
| ```` ```{r ex1-check} ```` (a message string) | ```` ```{webr} ```` + `#| exercise: ex1` + `#| check: true` |
| ```` ```{r ex1-hint} ```` / `<div id="ex1-hint">` | `::: {.hint exercise="ex1"}` |
| `question(...)` / `quiz(...)` | `::: {.quiz}` block (see `assets/quiz.html`) |
| `setup` chunk | hidden ```` ```{r} ```` (build time) + hidden ```` ```{webr} ```` (browser) |
| plain ```` ```{r} ```` chunks | unchanged (run at build time) |

## Things to know about R in the browser

- **No `autorun`.** Several exercises evaluating at page load can break the webR session ("cannot get ALTSTRING_ELT during GC"). Learners click **Run Code** instead; learnr's `exercise.eval = TRUE` isn't carried over.
- **Large data is slow.** For example, `separate()` on the 405k-row `who` table takes about 13 s in the browser.
- **quarto-live is patched.** By default, grading an exercise also runs its solution. Our checker never uses that result, and for heavy exercises the extra run crashed webR ("memory access out of bounds"). `tools/patch-quarto-live.py` turns it off. **Re-run it after updating the extension** (`quarto update r-wasm/quarto-live`).
- Checks behave like the original learnr checker: any attempt shows the lesson's feedback message.

## Building locally

Use the Quarto CLI (bundled with RStudio and Positron) and R with the packages listed in `.github/workflows/publish.yml` (tidyverse, babynames, nycflights13, gapminder, maps, mapproj, hexbin, ggrepel, ggthemes, RColorBrewer, viridis):

```bash
quarto preview
```

## Deployment

Every push to `main` runs `.github/workflows/publish.yml`, which renders the site and deploys it to GitHub Pages. In the repository settings, **Pages → Build and deployment → Source** must be set to **GitHub Actions**.
