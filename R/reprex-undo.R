#' Un-render a reprex
#'
#' @description
#' Recover clean, runnable code from a reprex captured in the wild and write it
#' to user's clipboard. The code is also returned invisibly and optionally
#' written to file. Three different functions address various forms of
#' wild-caught reprex.
#'
#' @param input Character. If has length one and lacks a terminating newline,
#'   interpreted as the path to a file containing reprex code. Otherwise,
#'   assumed to hold reprex code as character vector. If not provided, the
#'   clipboard is consulted for input.
#' @param outfile Optional basename for output file. When `NULL`, no file is
#'   left behind. If `outfile = "foo"`, expect an output file in current working
#'   directory named `foo_clean.R`. If `outfile = NA`, expect on output file in
#'   a location and with basename derived from `input`, if a path, or in
#'   current working directory with basename derived from [tempfile()]
#'   otherwise.
#' @param comment regular expression that matches commented output lines
#' @param prompt character, the prompt at the start of R commands
#' @param continue character, the prompt for continuation lines
#' @return Character vector holding just the clean R code, invisibly
#' @name un-reprex
NULL

#' @describeIn un-reprex Attempts to reverse the effect of [reprex()]. When
#'   `venue = "r"`, this just becomes a wrapper around `reprex_clean()`.
#' @inheritParams reprex
#' @export
#' @examples
#' \dontrun{
#' ## a rendered reprex can be inverted, at least approximately
#' tmp_in <- file.path(tempdir(), "roundtrip-input")
#' x <- reprex({
#'   #' Some text
#'   #+ chunk-label-and-options-cannot-be-recovered, message = TRUE
#'   (x <- 1:4)
#'   #' More text
#'   y <- 2:5
#'   x + y
#' }, html_preview = FALSE, advertise = FALSE, outfile = tmp_in)
#' tmp_out <- file.path(tempdir(), "roundtrip-output")
#' x <- reprex_invert(x, outfile = tmp_out)
#' x
#'
#' # clean up
#' file.remove(
#'   list.files(dirname(tmp_in), pattern = "roundtrip", full.names = TRUE)
#' )
#' }
reprex_invert <- function(input = NULL,
                          outfile = NULL,
                          venue = c("gh", "r", "so", "ds"),
                          comment = opt("#>")) {
  venue <- tolower(venue)
  venue <- match.arg(venue)
  venue <- ds_is_gh(venue)
  venue <- so_is_gh(venue)

  if (venue == "r") {
    return(reprex_clean(input, outfile = outfile, comment = comment))
  }

  reprex_undo(
    input,
    outfile = outfile,
    venue = venue,
    is_md = TRUE,
    comment = comment
  )
}

#' @describeIn un-reprex Assumes R code is top-level, possibly interleaved with
#'   commented output, e.g., a displayed reprex copied from GitHub or the direct
#'   output of `reprex(..., venue = "R")`. This function removes commented
#'   output.
#' @export
#' @examples
#' \dontrun{
#' ## a displayed reprex can be cleaned of commented output
#' tmp <- file.path(tempdir(), "commented-code")
#' x <- c(
#'   "## a regular comment, which is retained",
#'   "(x <- 1:4)",
#'   "#> [1] 1 2 3 4",
#'   "median(x)",
#'   "#> [1] 2.5"
#'   )
#' out <- reprex_clean(x, outfile = tmp)
#' out
#'
#' # clean up
#' file.remove(
#'   list.files(dirname(tmp), pattern = "commented-code", full.names = TRUE)
#' )
#'
#' ## round trip with reprex(..., venue = "R")
#' code_in <- c("x <- rnorm(2)", "min(x)")
#' res <- reprex(input = code_in, venue = "R", advertise = FALSE)
#' res
#' (code_out <- reprex_clean(res))
#' identical(code_in, code_out)
#' }
reprex_clean <- function(input = NULL,
                         outfile = NULL,
                         comment = opt("#>")) {
  reprex_undo(input, outfile = outfile, is_md = FALSE, comment = comment)
}

#' @describeIn un-reprex Assumes R code lines start with a prompt and that
#'   printed output is top-level, e.g., what you'd get from copy/paste from the
#'   R Console. Removes lines of output and strips prompts from lines holding R
#'   commands.
#' @export
#' @examples
#' \dontrun{
#' ## rescue a reprex that was copied from a live R session
#' tmp <- file.path(tempdir(), "live-transcript")
#' x <- c(
#'   "> ## a regular comment, which is retained",
#'   "> (x <- 1:4)",
#'   "[1] 1 2 3 4",
#'   "> median(x)",
#'   "[1] 2.5"
#' )
#' out <- reprex_rescue(x, outfile = tmp)
#' out
#'
#' # clean up
#' file.remove(
#'   list.files(dirname(tmp),pattern = "live-transcript", full.names = TRUE)
#' )
#' }
reprex_rescue <- function(input = NULL,
                          outfile = NULL,
                          prompt = getOption("prompt"),
                          continue = getOption("continue")) {
  reprex_undo(
    input,
    outfile = outfile,
    is_md = FALSE,
    prompt = paste(escape_regex(prompt), escape_regex(continue), sep = "|")
  )
}

reprex_undo <- function(input = NULL,
                        outfile = NULL,
                        venue,
                        is_md = FALSE,
                        comment = NULL, prompt = NULL) {
  where <- locate_input(input)
  src <- switch(
    where,
    clipboard = ingest_clipboard(),
    path      = read_lines(input),
    input     = escape_newlines(sub("\n$", "", input)),
    NULL
  )
  comment <- arg_option(comment)

  outfile_given <- !is.null(outfile)
  infile <- if (where == "path") input else NULL
  if (outfile_given) {
    filebase <- make_filebase(outfile, infile)
    r_file <- r_file_clean(filebase)
    if (would_clobber(r_file)) {
      return(invisible())
    }
  }

  if (is_md) { ## reprex_invert
    x_out <- convert_md_to_r(src, comment = comment, drop_output = TRUE)
  } else if (is.null(prompt)) { ## reprex_clean
    x_out <- src[!grepl(comment, src)]
  } else { ## reprex_rescue
    regex <- paste0("^\\s*", prompt)
    x_out <- src[grepl(regex, src)]
    x_out <- sub(regex, "", x_out)
  }

  if (clipboard_available()) {
    clipr::write_clip(x_out)
    reprex_success("Clean code is on the clipboard.")
  }
  if (outfile_given) {
    write_lines(x_out, r_file)
    reprex_path("Writing clean code as {.code .R} script:", r_file)
  }
  invisible(x_out)
}

convert_md_to_r <- function(lines, comment = "#>", drop_output = FALSE) {
  lines_info <- classify_fenced_lines(lines, comment = comment)
  lines_out <- ifelse(lines_info == "prose" & nzchar(lines), roxygen_comment(lines), lines)
  drop_classes <- c("bt", if (drop_output) "output")
  lines_out[!lines_info %in% drop_classes]
}

## Classify lines in the presence of fenced code blocks.
## Specifically, blocks fenced by three backticks.
## This is true of the output from reprex(..., venue = "gh").
## Classifies each line like so:
##   * bt     = backticks
##   * code   = code inside a fenced block
##   * output = commented output inside a fenced block
##   * prose  = outside a fenced block
classify_fenced_lines <- function(x, comment = "^#>") {
  x_shift <- c("", utils::head(x, -1))
  cumulative_fences <- cumsum(grepl("^```", x_shift))
  wut <- ifelse(grepl("^```", x), "bt",
    ifelse(cumulative_fences %% 2 == 1, "code", "prose")
  )
  wut <- ifelse(wut == "code" & grepl(comment, x), "output", wut)
  wut
}
