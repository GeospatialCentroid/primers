#!/usr/bin/env Rscript
# Convert a learnr tutorial (.Rmd) into a quarto-live lesson (.qmd).
#
# Usage: Rscript tools/convert-learnr.R <in.Rmd> <out.qmd> "<subtitle>"
#
# Mapping:
#   setup chunk            -> build-time {r} chunk + hidden in-browser {webr} chunk
#   exercise = TRUE        -> {webr} exercise (exercise.eval is ignored; see below)
#   <label>-setup /
#   exercise.setup = "x"   -> {webr} setup block for that exercise
#   <label>-solution       -> {webr} solution block
#   <label>-hint(-n)       -> .hint div (string hints) or {webr} hint block (code)
#   <label>-check          -> {webr} check block (message string)
#   question() / quiz()    -> .quiz divs (see assets/quiz.html)
#   other {r} chunks       -> unchanged, run at build time
# The output is a starting point; review it by hand.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: convert-learnr.R in.Rmd out.qmd [subtitle]")
infile <- args[[1]]
outfile <- args[[2]]
subtitle <- if (length(args) >= 3) args[[3]] else NULL

lines <- readLines(infile, warn = FALSE)

# ---- front matter ---------------------------------------------------------
fm_idx <- which(lines == "---")
fm <- yaml::yaml.load(paste(lines[(fm_idx[1] + 1):(fm_idx[2] - 1)], collapse = "\n"))
body <- lines[(fm_idx[2] + 1):length(lines)]

# ---- split into text lines and chunks -------------------------------------
parse_header <- function(hdr) {
  hdr <- trimws(hdr)
  label <- NA_character_
  m <- regmatches(hdr, regexec("^([A-Za-z0-9_.-]+)\\s*(,|$)", hdr))[[1]]
  rest <- hdr
  if (length(m)) {
    label <- m[2]
    rest <- sub("^[A-Za-z0-9_.-]+\\s*,?\\s*", "", hdr)
  }
  opts <- list()
  if (nzchar(trimws(rest))) {
    call <- parse(text = paste0("list(", rest, ")"))[[1]]
    nms <- names(as.list(call))[-1]
    vals <- as.list(call)[-1]
    for (k in seq_along(vals)) {
      opts[[nms[k]]] <- tryCatch(eval(vals[[k]], baseenv()),
                                 error = function(e) deparse(vals[[k]]))
    }
  }
  list(label = label, opts = opts)
}

segs <- list()
i <- 1
while (i <= length(body)) {
  l <- body[i]
  if (grepl("^```\\{r[ ,}]", l)) {
    hdr <- sub("^```\\{r\\s*,?", "", sub("\\}\\s*$", "", l))
    j <- i + 1
    while (j <= length(body) && !grepl("^```\\s*$", body[j])) j <- j + 1
    code <- if (j > i + 1) body[(i + 1):(j - 1)] else character()
    h <- parse_header(hdr)
    segs[[length(segs) + 1]] <- list(type = "chunk", header = hdr, label = h$label,
                                     opts = h$opts, code = code)
    i <- j + 1
  } else {
    segs[[length(segs) + 1]] <- list(type = "text", line = l)
    i <- i + 1
  }
}

chunks <- Filter(function(s) s$type == "chunk", segs)
by_label <- list()
for (ch in chunks) if (!is.na(ch$label)) by_label[[ch$label]] <- ch

is_exercise <- function(ch) {
  e <- ch$opts$exercise
  isTRUE(e) || identical(e, "TRUE")
}
exercise_labels <- vapply(Filter(is_exercise, chunks), `[[`, "", "label")

suffix_of <- function(label) {
  if (is.na(label)) return(NULL)
  for (sfx in c("-solution", "-check", "-code-check", "-setup")) {
    base <- sub(paste0(sfx, "$"), "", label)
    if (base != label && base %in% exercise_labels) return(list(sfx = sfx, ex = base))
  }
  m <- regmatches(label, regexec("^(.*)-hint(-[0-9]+)?$", label))[[1]]
  if (length(m) && m[2] %in% exercise_labels) return(list(sfx = "-hint", ex = m[2]))
  NULL
}

# ---- setup chunk -----------------------------------------------------------
strip_learnr <- function(code) {
  out <- character()
  skip <- FALSE
  for (l in code) {
    if (grepl("^checker\\s*<-\\s*function", l)) { skip <- TRUE; next }
    if (skip) { if (grepl("^\\}\\s*$", l)) skip <- FALSE; next }
    if (grepl("library\\(learnr\\)|tutorial_options\\(|Sys\\.setenv\\(|# increase fork limit", l)) next
    out <- c(out, l)
  }
  # trim leading/trailing blank lines
  while (length(out) && !nzchar(trimws(out[1]))) out <- out[-1]
  while (length(out) && !nzchar(trimws(out[length(out)]))) out <- out[-length(out)]
  out
}

setup_ch <- by_label[["setup"]]
build_setup <- if (!is.null(setup_ch)) strip_learnr(setup_ch$code) else character()
browser_setup <- build_setup[!grepl("^\\s*(library|require)\\(|knitr::opts_chunk", build_setup)]
while (length(browser_setup) && !nzchar(trimws(browser_setup[1]))) browser_setup <- browser_setup[-1]

# ---- packages for webR -----------------------------------------------------
all_code <- unlist(lapply(chunks, `[[`, "code"))
pkgs <- c(
  unlist(regmatches(all_code, gregexpr("(?<=library\\()[A-Za-z][A-Za-z0-9.]*", all_code, perl = TRUE))),
  unlist(regmatches(all_code, gregexpr("[A-Za-z][A-Za-z0-9.]*(?=::)", all_code, perl = TRUE)))
)
pkgs <- unique(pkgs)
if ("tidyverse" %in% pkgs) {
  txt <- paste(all_code, collapse = "\n")
  extra <- c("dplyr", "ggplot2", "tidyr", "tibble", "purrr", "stringr", "forcats")
  if (grepl("read_(csv|tsv|delim)|parse_", txt)) extra <- c(extra, "readr")
  if (grepl("lubridate|\\b(ymd|mdy|dmy|ymd_hms)\\(", txt)) extra <- c(extra, "lubridate")
  pkgs <- c(setdiff(pkgs, "tidyverse"), extra)
}
skip_pkgs <- c("learnr", "knitr", "rmarkdown", "htmltools", "base", "stats", "utils",
               "datasets", "graphics", "grDevices", "methods", "tools", "grid", "shiny")
pkgs <- unique(setdiff(pkgs, skip_pkgs))

# ---- quiz conversion -------------------------------------------------------
qenv <- new.env(parent = baseenv())
qenv$answer <- function(text, correct = FALSE, message = NULL, ...) {
  list(kind = "answer", text = text, correct = isTRUE(correct), message = message)
}
qenv$question <- function(text, ..., type = "auto", correct = "Correct!",
                          incorrect = "Incorrect", allow_retry = FALSE,
                          random_answer_order = FALSE, try_again = NULL,
                          message = NULL, post_message = NULL, options = NULL,
                          caption = NULL, submit_button = NULL, try_again_button = NULL,
                          loading = NULL) {
  dots <- list(...)
  answers <- Filter(function(a) is.list(a) && identical(a$kind, "answer"), dots)
  list(kind = "question", text = text, answers = answers, type = type,
       correct = correct, incorrect = incorrect, allow_retry = isTRUE(allow_retry))
}
qenv$quiz <- function(..., caption = NULL) {
  list(kind = "quiz", caption = caption, questions = list(...))
}

attr_val <- function(x) gsub('"', "'", x, fixed = TRUE)

render_question <- function(q) {
  if (!any(vapply(q$answers, `[[`, logical(1), "correct")))
    warning("question has no correct answer (check the original): ", q$text, call. = FALSE)
  attrs <- character()
  if (q$type %in% c("single", "multiple")) attrs <- c(attrs, sprintf('type="%s"', q$type))
  if (!identical(q$correct, "Correct!")) attrs <- c(attrs, sprintf('correct="%s"', attr_val(q$correct)))
  if (!identical(q$incorrect, "Incorrect")) attrs <- c(attrs, sprintf('incorrect="%s"', attr_val(q$incorrect)))
  if (q$allow_retry) attrs <- c(attrs, 'allow-retry="true"')
  out <- c(sprintf("::::: {.quiz%s}", if (length(attrs)) paste0(" ", paste(attrs, collapse = " ")) else ""),
           q$text, "")
  for (a in q$answers) {
    out <- c(out, if (a$correct) ':::: {.answer correct="true"}' else ":::: {.answer}", a$text)
    if (!is.null(a$message)) out <- c(out, "", "::: {.message}", a$message, ":::")
    out <- c(out, "::::", "")
  }
  c(out, ":::::")
}

render_quiz_chunk <- function(code) {
  exprs <- parse(text = code)
  out <- character()
  for (e in exprs) {
    obj <- eval(e, qenv)
    if (identical(obj$kind, "question")) {
      out <- c(out, render_question(obj), "")
    } else if (identical(obj$kind, "quiz")) {
      if (!is.null(obj$caption) && nzchar(obj$caption)) out <- c(out, sprintf("**%s**", obj$caption), "")
      for (q in obj$questions) out <- c(out, render_question(q), "")
    }
  }
  out
}

is_quiz_chunk <- function(ch) any(grepl("^\\s*(question|quiz)\\(", ch$code))

# ---- exercise setup code (learnr exercise.setup chains) --------------------
setup_code_for <- function(label, seen = character()) {
  if (label %in% seen) return(character())
  ch <- by_label[[label]]
  if (is.null(ch)) return(character())
  ref <- ch$opts$exercise.setup %||% ch$opts$setup
  code <- character()
  if (!is.null(ref)) {
    code <- c(code, setup_code_for(ref, c(seen, label)))
    code <- c(code, by_label[[ref]]$code)
  }
  own <- by_label[[paste0(label, "-setup")]]
  if (!is.null(own)) code <- c(code, own$code)
  code
}
`%||%` <- function(a, b) if (is.null(a)) b else a

webr_block <- function(opts, code) {
  c("```{webr}", sprintf("#| %s", opts), code, "```")
}

is_string_literal <- function(code) {
  p <- tryCatch(parse(text = code), error = function(e) NULL)
  length(p) == 1 && is.character(p[[1]])
}

# ---- emit body ---------------------------------------------------------------
out <- character()
for (s in segs) {
  if (s$type == "text") {
    l <- s$line
    if (grepl("^#{1,6}\\s*$", l)) next                       # learnr step breaks
    l <- sub("^!\\[\\]\\((https://(www\\.)?(vimeo|youtube)\\.com/[^)]+)\\)\\s*$",
             "{{< video \\1 >}}", l)
    l <- gsub("Submit Answer", "Run Code", l, fixed = TRUE)
    out <- c(out, l)
    next
  }

  ch <- s
  if (identical(ch$label, "setup")) next

  if (is_exercise(ch)) {
    o <- sprintf("exercise: %s", ch$label)
    # exercise.eval = TRUE is deliberately NOT mapped to `autorun: true`: several
    # autoruns evaluating at page load can break the webR session
    # ("cannot get ALTSTRING_ELT during GC"), especially with large data.
    setup <- setup_code_for(ch$label)
    if (length(setup)) {
      out <- c(out, webr_block(c(sprintf("exercise: %s", ch$label), "setup: true"), setup), "")
    }
    out <- c(out, webr_block(o, ch$code))
    next
  }

  sfx <- suffix_of(ch$label)
  if (!is.null(sfx)) {
    ex <- sfx$ex
    if (sfx$sfx == "-solution") {
      out <- c(out, webr_block(c(sprintf("exercise: %s", ex), "solution: true"), ch$code))
    } else if (sfx$sfx %in% c("-check", "-code-check")) {
      if (sfx$sfx == "-check")
        out <- c(out, webr_block(c(sprintf("exercise: %s", ex), "check: true"), ch$code))
    } else if (sfx$sfx == "-hint") {
      if (is_string_literal(ch$code)) {
        txt <- eval(parse(text = ch$code)[[1]])
        out <- c(out, sprintf('::: {.hint exercise="%s"}', ex), txt, ":::")
      } else {
        out <- c(out, webr_block(c(sprintf("exercise: %s", ex), "hint: true"), ch$code))
      }
    } else if (sfx$sfx == "-setup") {
      # used via setup_code_for(); also run at build time in case later chunks need it
      out <- c(out, "```{r}", "#| include: false", ch$code, "```")
    }
    next
  }

  if (is_quiz_chunk(ch)) {
    out <- c(out, render_quiz_chunk(ch$code))
    next
  }

  # static chunk: keep as-is (runs at build time)
  out <- c(out, sprintf("```{r%s}", if (nzchar(trimws(ch$header))) paste0(" ", trimws(ch$header)) else ""),
           ch$code, "```")
}

# collapse 3+ blank lines
keep <- !(out == "" & c("", head(out, -1)) == "" & c("", "", head(out, -2)) == "")
out <- out[keep]

# ---- assemble ------------------------------------------------------------------
yaml_lines <- c(
  "---",
  sprintf('title: "%s"', gsub('"', '\\"', fm$title, fixed = TRUE)),
  if (!is.null(subtitle)) sprintf('subtitle: "%s"', subtitle),
  "format: live-html",
  "webr:",
  if (length(pkgs)) c("  packages:", sprintf("    - %s", pkgs)),
  # Must live in each lesson: a lesson's `webr:` key replaces (not merges with)
  # any `webr:` in lessons/_metadata.yml.
  "  # quarto-live's default 30 s limit is too short for some large-data exercises",
  "  # in the browser, and hitting it can break the R session.",
  "  cell-options:",
  "    timelimit: 300",
  "---",
  "",
  "{{< include ../_setup.qmd >}}",
  ""
)
if (length(build_setup)) {
  yaml_lines <- c(yaml_lines, "```{r}", "#| include: false", build_setup, "```", "")
}
if (length(browser_setup)) {
  yaml_lines <- c(yaml_lines, "```{webr}", "#| include: false", browser_setup, "```", "")
}

writeLines(c(yaml_lines, out), outfile)
message(sprintf("%s -> %s  [packages: %s]", infile, outfile, paste(pkgs, collapse = ", ")))
