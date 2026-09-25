test_that("macro gallery contract contains ten unique views", {
  manifest <- macro_gallery_manifest()
  expect_equal(nrow(manifest), 10L)
  expect_equal(anyDuplicated(manifest$slug), 0L)
  expect_true(all(nzchar(manifest$title)))
  expect_true(all(nzchar(manifest$caption)))
})
