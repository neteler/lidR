context("projection")

las = lidR:::dummy_las(10)

test_that("projection with epsg code works", {

  expect_equal(projection(las), NA_character_)

  projection(las) <- sp::CRS("+init=epsg:26917")

  expect_equal(las@header@VLR$GeoKeyDirectoryTag$tags[[1]]$`value offset`, 26917)

  projection(las) <- sp::CRS("+init=epsg:26918")

  expect_equal(las@header@VLR$GeoKeyDirectoryTag$tags[[1]]$`value offset`, 26918)
})

las = lidR:::dummy_las(10)

test_that("projection with wkt code works", {

  las@header@PHB$`Global Encoding`$WKT = TRUE

  projection(las) <- sp::CRS("+init=epsg:26917")

  expect_equal(las@header@VLR$GeoKeyDirectoryTag$tags[[1]]$`value offset`, NULL)
  expect_match(las@header@VLR$`WKT OGC CS`$`WKT OGC COORDINATE SYSTEM`, "PROJCS")

  projection(las) <- sp::CRS("+init=epsg:26918")

  expect_equal(las@header@VLR$GeoKeyDirectoryTag$tags[[1]]$`value offset`, NULL)
  expect_match(las@header@VLR$`WKT OGC CS`$`WKT OGC COORDINATE SYSTEM`, "PROJCS")
})

las = lidR:::dummy_las(10)

test_that("epsg works", {

  epsg(las) <- 26917
  expect_equal(las@header@VLR$GeoKeyDirectoryTag$tags[[1]]$`value offset`, 26917)
})
