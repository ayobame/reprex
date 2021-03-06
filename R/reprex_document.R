#' reprex output format
#'
#' @description
#' This is an R Markdown output format designed specifically for making
#' "reprexes", typically created via the [reprex()] function, which ultimately
#' renders the document with [reprex_render()]. It is a heavily modified version
#' of [rmarkdown::md_document()]. The arguments have different spheres of
#' influence:
#'   * `venue` potentially affects input preparation and [reprex_render()].
#'   * Add content to the primary input, prior to rendering:
#'     - `advertise`
#'     - `session_info`
#'     - `std_out_err` (also consulted by [reprex_render()])
#'   * Influence knitr package or chunk options:
#'     - `style`
#'     - `comment`
#'     - `tidyverse_quiet`
#'   * `html_preview` is only consulted by [reprex_render()], but it is a formal
#'     argument of `reprex_document()` so that it can be included in the YAML
#'     frontmatter.
#'
#' RStudio users can create new R Markdown documents with the
#' `reprex_document()` format using built-in templates. Do
#' *File > New File > R Markdown ... > From Template* and choose one of:
#'   * reprex (minimal)
#'   * reprex (lots of features)
#'
#' Both include `knit: reprex::reprex_render` in the YAML, which causes the
#' RStudio "Knit" button to use `reprex_render()`. If you render these documents
#' yourself, you should do same.
#'
#' @inheritParams reprex
#' @inheritParams rmarkdown::md_document
#' @return An R Markdown output format to pass to [rmarkdown::render()].
#' @export
#' @examples
#' reprex_document()
reprex_document <- function(venue = c("gh", "r", "rtf", "html", "so", "ds"),

                            advertise       = NULL,
                            session_info    = opt(FALSE),
                            style           = opt(FALSE),
                            comment         = opt("#>"),
                            tidyverse_quiet = opt(TRUE),
                            std_out_err     = opt(FALSE),
                            pandoc_args = NULL,
                            # must exist, so that it is tolerated in the YAML
                            html_preview) {
  venue <- tolower(venue)
  venue <- match.arg(venue)
  venue <- normalize_venue(venue)

  advertise       <- set_advertise(advertise, venue)
  session_info    <- arg_option(session_info)
  style           <- arg_option(style)
  style           <- style_requires_styler(style)
  # html_preview is actually an input for for reprex_render()
  comment         <- arg_option(comment)
  tidyverse_quiet <- arg_option(tidyverse_quiet)
  std_out_err     <- arg_option(std_out_err)

  stopifnot(is_toggle(advertise), is_toggle(session_info), is_toggle(style))
  stopifnot(is.character(comment))
  stopifnot(is_toggle(tidyverse_quiet), is_toggle(std_out_err))

  opts_chunk <- list(
    # fixed defaults
    collapse = TRUE, error = TRUE,
    # explicitly exposed for user configuration
    comment = comment,
    R.options = list(
      tidyverse.quiet = tidyverse_quiet,
      tidymodels.quiet = tidyverse_quiet
    )
  )
  if (isTRUE(style)) {
    opts_chunk[["tidy"]] <- "styler"
  }
  opts_knit <- list(
    upload.fun = switch(
      venue,
      r = identity,
      knitr::imgur_upload
    )
  )

  pandoc_args <- c(
    pandoc_args,
    if (rmarkdown::pandoc_available()) {
      if (rmarkdown::pandoc_version() < "1.16") "--no-wrap" else "--wrap=preserve"
    }
  )

  pre_knit <- NULL
  if (isTRUE(std_out_err) || isTRUE(advertise) || isTRUE(session_info)) {
    pre_knit <- function(input, ...) {

      # I don't know why the pre_knit hook operates on the **original** input
      # instead of the to-be-knitted (post-spinning) input, but I need to
      # operate on the latter. So I brute force the correct path.
      # This is a no-op if input starts as `.Rmd`.
      knit_input <- sub("[.]R$", ".spin.Rmd", input)
      input_lines <- read_lines(knit_input)

      if (isTRUE(advertise)) {
        input_lines <- c(input_lines, "", ad(venue))
      }

      if (isTRUE(std_out_err)) {
        input_lines <- c(
          input_lines, "", std_out_err_stub(input, venue %in% c("gh", "html"))
        )
      }

      if (isTRUE(session_info)) {
        input_lines <- c(
          input_lines, "", si(details = venue %in% c("gh", "html"))
        )
      }

      write_lines(input_lines, knit_input)
    }
  }

  format <- rmarkdown::output_format(
    knitr = rmarkdown::knitr_options(
      opts_knit = opts_knit,
      opts_chunk = opts_chunk
    ),
    pandoc = rmarkdown::pandoc_options(
      to = "commonmark",
      from = rmarkdown::from_rmarkdown(implicit_figures = FALSE),
      ext = ".md",
      args = pandoc_args
    ),
    clean_supporting = FALSE,
    pre_knit = pre_knit,
    base_format = rmarkdown::md_document()
  )
  format
}

std_out_err_stub <- function(input, details = FALSE) {
  txt <- backtick(std_file(input))
  if (details) {
    c(
      "<details style=\"margin-bottom:10px;\">",
      "<summary>Standard output and standard error</summary>",
      txt,
      "</details>"
    )
  } else {
    c("#### Standard output and error", txt)
  }
}

ad <- function(venue) {
  txt <- paste0(
    "Created on `r Sys.Date()` by the ",
    "[reprex package](https://reprex.tidyverse.org) ",
    "(v`r utils::packageVersion(\"reprex\")`)"
  )
  if (venue %in% c("gh", "so", "html")) {
    txt <- paste0("<sup>", txt, "</sup>")
  }
  txt
}

# TO RECONSIDER: once I am convinced that so == gh, I can eliminate the
# `details` argument of `si()`. Empirically, there seems to be no downside
# on SO when we embed session info in the html tags that are favorable for
# GitHub. They apparently are ignored.
si <- function(details = FALSE) {
  txt <- r_chunk(session_info_string())
  if (details) {
    txt <- c(
      "<details style=\"margin-bottom:10px;\">",
      "<summary>Session info</summary>",
      txt,
      "</details>"
    )
  }
  txt
}

session_info_string <- function() {
  if (rlang::is_installed("sessioninfo")) {
    "sessioninfo::session_info()"
  } else {
    "sessionInfo()"
  }
}
