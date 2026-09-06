r_dir <- testthat::test_path("..", "..", "R")
r_files <- list.files(r_dir, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
invisible(lapply(r_files, source))
