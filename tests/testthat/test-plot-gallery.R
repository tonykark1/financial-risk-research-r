test_that("plot gallery contract contains 30 unique analytical views", {
  manifest <- gallery_manifest()
  expect_equal(nrow(manifest), 30L)
  expect_equal(as.integer(table(manifest$domain)), rep(10L, 3L))
  expect_equal(anyDuplicated(manifest$slug), 0L)
  expect_true(all(nzchar(manifest$title)))
  expect_true(all(nzchar(manifest$caption)))
})
