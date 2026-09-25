run_test_suite <- function(output = "logs/test_results.txt") {
  result <- capture.output({
    testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
  }, type = "output")
  writeLines(result, output, useBytes = TRUE)
  normalizePath(output, winslash = "/", mustWork = TRUE)
}
