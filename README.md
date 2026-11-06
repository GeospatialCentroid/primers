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
lessons/<section>/*.qmd  one file per lesson
_extensions/r-wasm/live  quarto-live extension
.github/workflows/       builds and deploys to GitHub Pages on push to main
```

## Writing a lesson

Start the lesson with this front matter and include the shared setup:

````markdown
---
title: "Lesson title"
format: live-html
webr:
  packages: [ggplot2, dplyr]   # installed + loaded in the browser
---

{{< include ../_setup.qmd >}}
````

| learnr | Quarto equivalent |
|---|---|
| ```` ```{r ex1, exercise = TRUE} ```` | ```` ```{webr} ```` + `#| exercise: ex1` |
| ```` ```{r ex1-solution} ```` | ```` ```{webr} ```` + `#| exercise: ex1` + `#| solution: true` |
| ```` ```{r ex1-check} ```` (a message string) | ```` ```{webr} ```` + `#| exercise: ex1` + `#| check: true` |
| ```` ```{r ex1-hint} ```` / `<div id="ex1-hint">` | `::: {.hint exercise="ex1"}` |
| `question(...)` | `::: {.quiz}` block (see `assets/quiz.html`) |
| plain ```` ```{r} ```` chunks | unchanged (run at build time) |

## Building locally

Use the Quarto CLI (bundled with RStudio and Positron) and R with `knitr`, `rmarkdown`, `ggplot2` and `dplyr`:

```bash
quarto preview
```

## Deployment

Every push to `main` runs `.github/workflows/publish.yml`, which renders the site and deploys it to GitHub Pages. In the repository settings, **Pages → Build and deployment → Source** must be set to **GitHub Actions**.
