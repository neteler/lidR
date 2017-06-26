# ===============================================================================
#
# PROGRAMMERS:
#
# jean-romain.roussel.1@ulaval.ca  -  https://github.com/Jean-Romain/lidR
#
# COPYRIGHT:
#
# Copyright 2016 Jean-Romain Roussel
#
# This file is part of lidR R package.
#
# lidR is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# ===============================================================================

grid_catalog <- function(ctg, grid_func, res, filter, buffer, by_file, ...)
{
  Min.X <- Min.Y <- Max.X <- Max.Y <- p <- NULL

  # Store some stuff in readable variables
  callparam = list(...)
  funcname  = lazyeval::expr_text(grid_func)
  exportdir = tempdir() %+%  "/" %+% funcname %+% "/"

  progress  = LIDROPTIONS("progress")
  numcores  = CATALOGOPTIONS("multicore")
  savevrt   = CATALOGOPTIONS("return_virtual_raster")
  memlimwar = CATALOGOPTIONS("memory_limit_warning")

  # Tweak to enable non-standard evaluation of 'func' in grid_metrics-alike functions
  if (!is.null(callparam$func)) {
    if (is.call(callparam$func))
      callparam$func = as.expression(callparam$func)
  }

  # Test of memory to prevent memory overflow
  surface = sum(with(ctg, (Max.X - Min.X) * (Max.Y - Min.Y)))
  npixel  = surface / (res*res)
  nmetric = 3 # Must find a way to access this number
  nbytes  = npixel * nmetric * 8
  class(nbytes) = "object_size"

  if (nbytes > memlimwar & !savevrt)
  {
    size = format(nbytes, "auto")
    text = paste0("The process is expected to return an approximatly ", size, " object. It might be too much.\n")
    choices = c(
      "Proceed anyway",
      "Store the results on my disk an return a virtual raster mosaic",
      "Abort, let me configure myself with 'catalog_options()'")

    cat(text)
    choice = utils::menu(choices)

    if (choice == 2)
      savevrt = TRUE
    else if (choice == 3)
      return(invisible())
  }

  # Create a pattern of clusters to be sequentially processed
  ctg_clusters = catalog_makecluster(ctg, res, buffer, by_file)
  ctg_clusters = apply(ctg_clusters, 1, as.list)

  # Add the path to the saved file (if saved)
  ctg_clusters = lapply(ctg_clusters, function(x)
  {
    x$path = exportdir %+% funcname %+% "_ROI" %+% x$name %+% ".tiff"
    return(x)
  })

  # Enable progress bar
  if (progress) p = utils::txtProgressBar(max = length(ctg_clusters), style = 3)

  # Create or clean the temporary directory
  if (savevrt)
  {
    if (!dir.exists(exportdir))
      dir.create(exportdir)
    else
      unlink(exportdir, recursive = TRUE) ; dir.create(exportdir)
  }

  # Computations done within sequential or parallel loop in .getMetrics
  if (numcores == 1)
  {
    verbose("Computing sequentially the metrics for each cluster...")
    output = lapply(ctg_clusters, apply_grid_func, grid_func = grid_func, ctg = ctg, res = res, filter = filter, param = callparam, save_tiff = savevrt, p = p)
  }
  else
  {
    verbose("Computing in parallel the metrics for each cluster...")
    cl = parallel::makeCluster(numcores, outfile = "")
    parallel::clusterExport(cl, varlist = c(utils::lsf.str(envir = globalenv()), ls(envir = environment())), envir = environment())
    output = parallel::parLapply(cl, ctg_clusters, fun = apply_grid_func, grid_func = grid_func, ctg = ctg, res = res, filter = filter, param = callparam, save_tiff = savevrt, p = p)
    parallel::stopCluster(cl)
  }

  # Post process of the results (return adequate object)
  if (!savevrt)
  {
    # Return a data.table
    ._class = class(output[[1]])
    output = data.table::rbindlist(output)
    data.table::setattr(output, "class", ._class)
  }
  else
  {
    # Build virtual raster mosaic and return it
    ras_lst = list.files(exportdir, full.names = TRUE, pattern = ".tif$")
    save_in = exportdir %+% "/" %+% funcname %+% ".vrt"
    gdalUtils::gdalbuildvrt(ras_lst, save_in)
    output = raster::stack(save_in)
  }

  return(output)
}

# Apply for a given ROI of a catlog a grid_* function
#
# @param X list. the coordinates of the region of interest (rectangular)
# @param grid_func function. the grid_* function to be applied
# @param ctg  Catalog.
# @param res numric. the resolution to apply the grid_* function
# @param filter character. the streaming filter to be applied
# @param param list. the parameter of the function grid_function but res
# @param p progressbar.
apply_grid_func = function(ctg_cluster, grid_func, ctg, res, filter, param, save_tiff, p)
{
  X <- Y <- NULL

  # Variables for readability
  xleft   = ctg_cluster$xleft
  xright  = ctg_cluster$xright
  ybottom = ctg_cluster$ybottom
  ytop    = ctg_cluster$ytop
  name    = "ROI" %+% ctg_cluster$name
  path    = ctg_cluster$path
  xcenter = ctg_cluster$xcenter
  ycenter = ctg_cluster$ycenter
  width   = (ctg_cluster$xrightbuff - ctg_cluster$xleftbuff)/2

  # Extract the ROI as a LAS object
  las = catalog_queries(ctg, xcenter, ycenter, width, width, name, filter, disable_bar = T, no_multicore = T)[[1]]

  # Skip if the ROI fall in a void area
  if (is.null(las)) return(NULL)

  # Because catalog_queries keep point inside the boundingbox (close interval) but point which
  # are exactly on the boundaries are counted twice. Here a post-process to make an open
  # interval on left and bottom edge of the boudingbox.
  las = suppressWarnings(lasfilter(las, X > xleft, Y > ybottom))

  # Very unprobable but who knows...
  if (is.null(las)) return(NULL)

  # Call the function
  param$x = las
  param$res  = res
  m = do.call(grid_func, args = param)

  # Remove the buffer
  m = m[X >= xleft & X <= xright & Y >= ybottom & Y <= ytop]
  as.lasmetrics(m, res)

  # Update progress bar
  if (!is.null(p))
  {
    i = utils::getTxtProgressBar(p) + 1
    utils::setTxtProgressBar(p, i)
  }

  # Return results or write file
  if (!save_tiff)
    return(m)
  else
  {
    if (nrow(m) == 0)
      return(NULL)

    m = as.raster(m)
    raster::writeRaster(m, path, format = "GTiff")
    return(NULL)
  }
}