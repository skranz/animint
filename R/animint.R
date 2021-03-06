#' Convert a ggplot to a list. Called from gg2animint(). 
#' @param p ggplot2 plot
#' @return list representing a ggplot, with elements, ranges, axes, scales, geoms, and options
#' @export
#' @seealso \code{\link{gg2animint}}
gg2list <- function(p){
  plist <- list()
  plistextra <- ggplot2::ggplot_build(p)
  for(sc in plistextra$plot$scales$scales){
    if(sc$scale_name == "manual"){
      plist$scales[[sc$aesthetics]] <- sc$palette(0)
    }else if(sc$scale_name == "brewer"){
      plist$scales[[sc$aesthetics]] <- sc$palette(length(sc$range$range))
    }else if(sc$scale_name == "hue"){
      plist$scales[[sc$aesthetics]] <- sc$palette(length(sc$range$range))
    }else if(sc$scale_name == "linetype_d"){
      plist$scales[[sc$aesthetics]] <- sc$palette(length(sc$range$range))
    }else if(sc$scale_name == "alpha_c"){
      plist$scales[[sc$aesthetics]] <- sc$palette(sc$range$range)
    }else if(sc$scale_name == "size_c"){
      plist$scales[[sc$aesthetics]] <- sc$palette(sc$range$range)
    }else if(sc$scale_name == "gradient"){
      plist$scales[[sc$aesthetics]] <- ggplot2:::scale_map(sc, ggplot2:::scale_breaks(sc))
    }
  }
  for(i in seq_along(plistextra$plot$layers)){
    ## This is the layer from the original ggplot object.
    L <- plistextra$plot$layers[[i]]

    ## for each layer, there is a correpsonding data.frame which
    ## evaluates the aesthetic mapping.
    df <- plistextra$data[[i]]

    ## This extracts essential info for this geom/layer.
    g <- layer2list(L, df, plistextra$panel$ranges[[1]])
    
    ## Idea: use the ggplot2:::coord_transform(coords, data, scales)
    ## function to handle cases like coord_flip. scales is a list of
    ## 12, coords is a list(limits=list(x=NULL,y=NULL)) with class
    ## e.g. c("cartesian","coord"). The result is a transformed data
    ## frame where all the data values are between 0 and 1.
    
    ## TODO: coord_transform maybe won't work for 
    ## geom_dotplot|rect|segment and polar/log transformations, which
    ## could result in something nonlinear. For the time being it is
    ## best to just ignore this, but you can look at the source of
    ## e.g. geom-rect.r in ggplot2 to see how they deal with this by
    ## doing a piecewise linear interpolation of the shape.

    g$data <- ggplot2:::coord_transform(plistextra$plot$coord, g$data,
                                        plistextra$panel$ranges[[1]])
    plist$geoms[[i]] <- g
  }
  # Export axis specification as a combination of breaks and
  # labels, on the relevant axis scale (i.e. so that it can
  # be passed into d3 on the x axis scale instead of on the 
  # grid 0-1 scale). This allows transformations to be used 
  # out of the box, with no additional d3 coding. 
  theme.pars <- ggplot2:::plot_theme(p)  
  
  ## Flip labels if coords are flipped - transform does not take care
  ## of this. Do this BEFORE checking if it is blank or not, so that
  ## individual axes can be hidden appropriately, e.g. #1.
  ranges <- plistextra$panel$ranges[[1]]
  if("flip"%in%attr(plistextra$plot$coordinates, "class")){
    temp <- plistextra$plot$labels$x
    plistextra$plot$labels$x <- plistextra$plot$labels$y
    plistextra$plot$labels$y <- temp
  }
  is.blank <- function(el.name){
    x <- ggplot2::calc_element(el.name, p$theme)
    "element_blank"%in%attr(x,"class")
  }
  plist$axis <- list()
  for(xy in c("x","y")){
    s <- function(tmp)sprintf(tmp, xy)
    plist$axis[[xy]] <- ranges[[s("%s.major")]]
    plist$axis[[s("%slab")]] <- if(is.blank(s("axis.text.%s"))){
      NULL
    }else{
      ranges[[s("%s.labels")]]
    }
    plist$axis[[s("%srange")]] <- ranges[[s("%s.range")]]
    plist$axis[[s("%sname")]] <- if(is.blank(s("axis.title.%s"))){
      ""
    }else{
      plistextra$plot$labels[[xy]]
    }
    plist$axis[[s("%sline")]] <- !is.blank(s("axis.line.%s"))
    plist$axis[[s("%sticks")]] <- !is.blank(s("axis.ticks.%s"))
  }
  
  plist$legend <- getLegendList(plistextra)
  if(length(plist$legend)>0){
    plist$legend <- plist$legend[which(sapply(plist$legend, function(i) length(i)>0))]
  }  # only pass out legends that have guide = "legend" or guide="colorbar"
  
  if("element_blank"%in%attr(theme.pars$plot.title, "class")){
    plist$title <- ""
  } else {
    plist$title <- plistextra$plot$labels$title
  }
  
  plist$options <- list(width=400,height=400)
  plist
}

#' Convert a layer to a list. Called from gg2list()
#' @param l one layer of the ggplot object
#' @param d one layer of calculated data from ggplot2::ggplot_build(p)
#' @param ranges axes ranges
#' @return list representing a layer, with corresponding aesthetics, ranges, and groups.
#' @export
#' @seealso \code{\link{gg2animint}}
layer2list <- function(l, d, ranges){
  g <- list(geom=l$geom$objname,
            data=d)
  g$aes <- sapply(l$mapping, function(k) as.character(as.expression(k))) # needed for when group, etc. is an expression

  ## use un-named parameters so that they will not be exported
  ## to JSON as a named object, since that causes problems with
  ## e.g. colour.
  g$params <- l$geom_params
  for(p.name in names(g$params)){
    names(g$params[[p.name]]) <- NULL
  }

  ## Make a list of variables to use for subsetting. subord is the
  ## order in which these variables will be accessed in the recursive
  ## JavaScript array structure.

  ## subvars/subord IS in fact useful with geom_segment! For example, in
  ## the first plot in the breakpointError example, the geom_segment has
  ## the following exported data in plot.json

  ## "subord": [
  ##  "showSelected",
  ## "showSelected2" 
  ## ],
  ## "subvars": {
  ##  "showSelected": "segments",
  ## "showSelected2": "bases.per.probe" 
  ## },

  ## This information is used to parse the recursive array data structure
  ## that allows efficient lookup of subsets of data in JavaScript. Look at
  ## the Firebug DOM browser on
  ## http://sugiyama-www.cs.titech.ac.jp/~toby/animint/breakpoints/index.html
  ## and navigate to plot.Geoms.geom3.data. You will see that this is a
  ## recursive array that can be accessed via
  ## data[segments][bases.per.probe] which is an un-named array
  ## e.g. [{row1},{row2},...] which will be bound to the <line> elements by
  ## D3. The key point is that the subord array stores the order of the
  ## indices that will be used to select the current subset of data (in
  ## this case showSelected=segments, showSelected2=bases.per.probe). The
  ## currently selected values of these variables are stored in
  ## plot.Selectors.
  
  some.vars <- c(g$aes[grepl("showSelected",names(g$aes))])
  g$update <- c(some.vars, g$aes[names(g$aes)=="clickSelects"])
  subset.vars <- c(some.vars, g$aes[names(g$aes)=="group"])
  g$subord <- as.list(names(subset.vars))
  g$subvars <- as.list(subset.vars)

  ## Warn if stat_bin is used with animint aes. geom_bar + stat_bin
  ## doesn't make sense with clickSelects/showSelected, since two
  ## clickSelects/showSelected values may show up in the same bin.
  stat <- l$stat
  if(!is.null(stat)){
    is.bin <- stat$objname=="bin"
    has.animint.aes <- any(c("clickSelects","showSelected")%in%names(g$aes))
    if(is.bin & has.animint.aes){
      warning(paste0("stat_bin is unpredictable ",
                    "when used with clickSelects/showSelected.\n",
                     "Use ddply to do the binning ",
                     "or use make_bar if using geom_bar/geom_histogram."))
    }
  }
  
  ## Pre-process some complex geoms so that they are treated as
  ## special cases of basic geoms. In ggplot2, this processing is done
  ## in the draw method of the geoms.
  if(g$geom=="abline"){
    # "Trick" ggplot coord_transform into transforming the slope and intercept
    g$data[,"x"] <- ranges$x.range[1]
    g$data[,"xend"] <- ranges$x.range[2]
    g$data[,"y"] <- g$data$slope*ranges$x.range[1]+g$data$intercept
    g$data[,"yend"] <-  g$data$slope*ranges$x.range[2]+g$data$intercept
    g$data <- as.data.frame(g$data)
    if(g$aes[["group"]]=="1"){ 
      # ggplot2 defaults to adding a group attribute
      # which misleads for situations where there are 
      # multiple lines with the same group. 
      # if the group attribute conveys no additional 
      # information, remove it.
      ## TODO: Figure out a better way to handle this...
      g$aes <- g$aes[-which(names(g$aes)=="group")]
      subset.vars <- c(some.vars, g$aes[names(g$aes)=="group"])
      g$subord <- as.list(names(subset.vars))
      g$subvars <- as.list(subset.vars)
    } 
    g$geom <- "segment"
  } else if(g$geom=="point"){
    # Fill set to match ggplot2 default of filled in circle. 
    if(!"fill"%in%names(g$data) & "colour"%in%names(g$data)){
      g$data[["fill"]] <- g$data[["colour"]]
    }
  } else if(g$geom=="ribbon"){
    # Color set to match ggplot2 default of fill with no outside border.
    if("fill"%in%names(g$data) & !"colour"%in%names(g$data)){
      g$data[["colour"]] <- g$data[["fill"]]
    }
  } else if(g$geom=="density" | g$geom=="area"){
    g$geom <- "ribbon"
  } else if(g$geom=="tile" | g$geom=="raster" | g$geom=="histogram" ){
    # Color set to match ggplot2 default of tile with no outside border.
    if(!"colour"%in%names(g$data) & "fill"%in%names(g$data)){
      g$data[["colour"]] <- g$data[["fill"]]
      # Make outer border of 0 size if size isn't already specified.
      if(!"size"%in%names(g$data)) g$data[["size"]] <- 0 
    }
    g$geom <- "rect"
  } else if(g$geom=="bar"){
    g$geom <- "rect"
  } else if(g$geom=="bin2d"){
    stop("bin2d is not supported in animint. Try using geom_tile() and binning the data yourself.")
  } else if(g$geom=="boxplot"){
    stop("boxplots are not supported. Workaround: rects, lines, and points")
    ## TODO: boxplot support. But it is hard since boxplots are drawn
    ## using multiple geoms and it is not straightforward to deal with
    ## that using our current JS code. There is a straightforward
    ## workaround: combine working geoms (rects, lines, and points).

    g$data$outliers <- sapply(g$data$outliers, FUN=paste, collapse=" @ ") 
    # outliers are specified as a list... change so that they are specified 
    # as a single string which can then be parsed in JavaScript.
    # there has got to be a better way to do this!!
  } else if(g$geom=="violin"){
    x <- g$data$x
    vw <- g$data$violinwidth
    xmin <- g$data$xmin
    xmax <- g$data$xmax
    g$data$xminv <- x-vw*(x-xmin)
    g$data$xmaxv <- x+vw*(xmax-x)
    newdata <- ddply(g$data, .(group), function(df){
                  rbind(arrange(transform(df, x=xminv), y), arrange(transform(df, x=xmaxv), -y))
                })
    newdata <- ddply(newdata, .(group), function(df) rbind(df, df[1,]))
    g$data <- newdata
    g$geom <- "polygon"
  } else if(g$geom=="step"){
    datanames <- names(g$data)
    g$data <- ddply(g$data, .(group), function(df) ggplot2:::stairstep(df))
    g$geom <- "path"
  } else if(g$geom=="contour" | g$geom=="density2d"){
    g$aes[["group"]] <- "piece"
    # reset g$subord, g$subvars now that group aesthetic exists.
    subset.vars <- c(some.vars, g$aes[names(g$aes)=="group"])
    g$subord <- as.list(names(subset.vars))
    g$subvars <- as.list(subset.vars)
    g$geom <- "path"
  } else if(g$geom=="freqpoly"){
    g$geom <- "line"
    # reset g$subord, g$subvars now that group aesthetic exists.
    subset.vars <- c(some.vars, group="group")
    g$subord <- as.list(names(subset.vars))
    g$subvars <- as.list(subset.vars)
  } else if(g$geom=="quantile"){
    g$geom <- "path"
    # reset g$subord, g$subvars now that group aesthetic exists.
    subset.vars <- c(some.vars, group="group")
    g$subord <- as.list(names(subset.vars))
    g$subvars <- as.list(subset.vars)
  } else if(g$geom=="hex"){
    g$geom <- "polygon"
    ## TODO: for interactivity we will run into the same problems as
    ## we did with histograms. Again, if we put several
    ## clickSelects/showSelected values in the same hexbin, then
    ## clicking/hiding hexbins doesn't really make sense. Need to stop
    ## with an error if showSelected/clickSelects is used with hex.
    g$aes[["group"]] <- "group"
    dx <- ggplot2::resolution(g$data$x, FALSE)
    dy <- ggplot2::resolution(g$data$y, FALSE) / sqrt(3) / 2 * 1.15
    hex <- as.data.frame(hexcoords(dx, dy))[,1:2]
    hex <- rbind(hex, hex[1,]) # to join hexagon back to first point
    g$data$group <- as.numeric(interaction(g$data$group, 1:nrow(g$data)))
    ## this has the potential to be a bad assumption - 
    ##   by default, group is identically 1, if the user 
    ##   specifies group, polygons aren't possible to plot
    ##   using d3, because group will have a different meaning
    ##   than "one single polygon".
    newdata <- ddply(g$data, .(group), function(df){
      df$xcenter <- df$x
      df$ycenter <- df$y
      cbind(x=df$x+hex$x, y=df$y+hex$y, df[,-which(names(df)%in%c("x", "y"))])
    })
    g$data <- newdata
    # Color set to match ggplot2 default of tile with no outside border.
    if(!"colour"%in%names(g$data) & "fill"%in%names(g$data)){
      g$data[["colour"]] <- g$data[["fill"]]
      # Make outer border of 0 size if size isn't already specified.
      if(!"size"%in%names(g$data)) g$data[["size"]] <- 0 
    }
    # reset g$subord, g$subvars now that group aesthetic exists.
    subset.vars <- c(some.vars, group="group")
    g$subord <- as.list(names(subset.vars))
    g$subvars <- as.list(subset.vars)    
  } else { 
    ## all other geoms are basic, and keep the same name.
    g$geom
  }
  
  ## idea: if geom is calculated, group is not meaningful - 
  ## it has already been used in the calculation stage, and 
  ## will only confuse the issue later.
  geom.aes.vars = g$aes[which(names(g$aes)%in%c("x", "y", "fill", "colour", "alpha", "size"))]
  grpidx <- which(names(g$aes)=="group")
  if(length(grpidx)>0){
    if(length(geom.aes.vars)>0 & nrow(g$data)!=nrow(l$data) & 
         !g$geom%in%c("ribbon","polygon","line", "path")){
      # need to exclude geom_ribbon and geom_violin, since they are coded to allow group aesthetics
      # because they use the d3 path setup.
      if(g$aes[grpidx]%in%geom.aes.vars){
        ## if the group aesthetic is also mapped to another visual aesthetic, 
        ## then remove the group aesthetic
        g$aes <- g$aes[-which(names(g$aes)=="group")]
        ## remove group from aes listing
        subset.vars <- c(some.vars, g$aes[names(g$aes)=="group"])
        ## recalculate subord/subvars.
        g$subord <- as.list(names(subset.vars))
        g$subvars <- as.list(subset.vars)
      }
    }
  }
  
  
  ## Check g$data for color/fill - convert to hexadecimal so JS can parse correctly.
  for(color.var in c("colour", "color", "fill")){
    if(color.var %in% names(g$data)){
      g$data[,color.var] <- toRGB(g$data[,color.var])
    }
  }
  
  g
}

#' Convert a list of ggplots to an interactive animation
#' that can be viewed in a web browser. 
#' Two new aesthetics control interactivity:
#' \itemize{
#' \item \code{aes(showSelected=variable)} means that
#'   only the subset of the data that corresponds to
#'   the selected value of variable will be shown.
#' \item \code{aes(clickSelects=variable)} means that clicking
#'   this geom will change the currently selected value of variable.
#' }
#' 
#' Supported ggplot2 geoms: 
#' \itemize{
#' \item point 
#' \item jitter
#' \item line
#' \item rect
#' \item tallrect (new with this package)
#' \item segment
#' \item hline
#' \item vline
#' \item bar
#' \item text
#' \item tile
#' \item raster
#' \item ribbon
#' \item abline
#' \item density
#' \item path
#' \item polygon
#' \item histogram
#' \item violin
#' \item linerange
#' \item step
#' \item contour
#' \item density2d
#' \item area
#' \item freqpoly
#' \item hex
#' }
#' Unsupported geoms: 
#' \itemize{
#' \item rug
#' \item dotplot
#' \item quantile - should *theoretically* work but in practice does not work
#' \item smooth - can be created using geom_line and geom_ribbon
#' \item boxplot - can be created using geom_rect and geom_segment
#' \item crossbar - can be created using geom_rect and geom_segment
#' \item pointrange - can be created using geom_linerange and geom_point
#' \item bin2d - bin using ddply() and then use geom_tile()
#' \item map - can be created using geom_polygon or geom_path
#'}
#' Supported scales: 
#' \itemize{
#' \item alpha, 
#' \item fill/colour (brewer, gradient, identity, manual)
#' \item linetype
#' \item x and y axis scales, manual break specification, label formatting
#' \item x and y axis theme elements: axis.line, axis.ticks, axis.text, axis.title can be set to element_blank(); other theme modifications not supported at this time, but would be possible with custom css files.
#' \item area 
#' \item size
#' }
#' Unsupported scales: 
#' \itemize{
#' \item shape. Open and closed circles can be represented by manipulating fill and colour scales and using default (circle) points, but d3 does not support many R shape types, so mapping between the two is difficult.
#' }
#' 
#' @title gg2animint
#' @aliases animint
#' @param plot.list a named list of ggplots and option lists.
#' @param out.dir directory to store html/js/csv files.
#' @param open.browser Should R open a browser? If yes, be sure to configure your browser to allow access to local files, as some browsers block this by default (e.g. chrome).
#' @return invisible list of ggplots in list format.
#' @export 
#' @seealso \code{\link{ggplot2}}
#' @example examples/gg2animint.R
gg2animint <- function(plot.list, out.dir=tempfile(), open.browser=interactive()){
  ## Check that it is a list and every element is named.
  stopifnot(is.list(plot.list))
  stopifnot(!is.null(names(plot.list)))
  stopifnot(all(names(plot.list)!=""))
  
  plist <- list() ## for extracted plots.
  olist <- list() ## for options.
  df.list <- list() ## for data.frames so we can look at their values
  ## to create an animation.
  
  ## Extract essential info from ggplots, reality checks.
  for(plot.name in names(plot.list)){
    p <- plot.list[[plot.name]]
    if(is.ggplot(p)){
      plist[[plot.name]] <- gg2list(p)
    }else if(is.list(p)){ ## for options.
      olist[[plot.name]] <- p
    }else{
      stop("list items must be ggplots or option lists")
    }
  }
  
  dir.create(out.dir,showWarnings=FALSE)
  i <- 1 #geom counter.
  result <- list(geoms=list(), selectors=list(), plots=list())
  for(plot.name in names(plist)){
    p <- plist[[plot.name]]
    result$plots[[plot.name]]$geoms <- list()
    for(g in p$geoms){
      g$classed <- sprintf("geom%d_%s_%s", i, g$geom, plot.name)
      result$plots[[plot.name]]$geoms <-
        c(result$plots[[plot.name]]$geoms, g$classed)
      df.list[[g$classed]] <- g$data
      ## Construct the selector.
      for(sel.i in seq_along(g$update)){
        v.name <- g$update[[sel.i]]
        col.name <- names(g$update)[[sel.i]]
        if(!v.name %in% names(result$selectors)){
          ## select the first one. TODO: customize.
          result$selectors[[v.name]] <- list(selected=g$data[[col.name]][1])
        }
        result$selectors[[v.name]]$subset <-
          c(result$selectors[[v.name]]$subset, list(g$classed))
      }
      ## Output data to csv.
      csv.name <- sprintf("%s.csv", g$classed)
      write.csv(g$data, file.path(out.dir, csv.name),
                quote=FALSE,row.names=FALSE)
      
      ## Output types
      ## Check to see if character type is d3's rgb type. 
      is.linetype <- function(x){
        x <- tolower(x)
        namedlinetype <- x%in%c("blank", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash")
        xsplit <- sapply(x, function(i) sum(is.na(strtoi(strsplit(i,"")[[1]],16)))==0)
        return(namedlinetype | xsplit)
      }
      g$types <- as.list(sapply(g$data, function(i) paste(class(i), collapse="-")))
      charidx <- which(g$types=="character")
      g$types[charidx] <- sapply(charidx, function(i) 
        if(sum(!is.rgb(g$data[[i]]))==0){"rgb"
        }else if(sum(!is.linetype(g$data[[i]]))==0){"linetype"
        }else "character")
      
      # convert ordered factors to unordered factors so javascript doesn't flip out.
      ordfactidx <- which(g$types=="ordered-factor")
      if(length(ordfactidx)>0){
        for(i in ordfactidx){
          g$data[[i]] <- factor(as.character(g$data[[i]]))
          g$types[[i]] <- "factor"
        }
      }
      
      g$data <- csv.name
      ## Finally save to the master geom list.
      result$geoms[[g$classed]] <- g
      i <- i+1
    }
    result$plots[[plot.name]]$scales <- p$scales
    result$plots[[plot.name]]$options <- p$options
    result$plots[[plot.name]]$ranges <- p$ranges
    result$plots[[plot.name]]$axis <- p$axis
    result$plots[[plot.name]]$title <- p$title
    result$plots[[plot.name]]$legend <- p$legend
  }
  ## add nextgeom so that drawing order is preserved.
  
  if(length(result$geoms)-1>0){
    for(i in 1:(length(result$geoms)-1)){
      result$geoms[[i]]$nextgeom <- result$geoms[[i+1]]$classed
    }
  }
  ## Go through options and add to the list.
  for(v.name in names(olist$duration)){
    for(g.name in result$selectors[[v.name]]$subset){
      result$geoms[[g.name]]$duration <- olist$duration[[v.name]]
    }
  }
  ## Set plot sizes.
  for(d in c("width","height")){
    if(is.list(olist[[d]])){
      if(is.null(names(olist[[d]]))){ #use this size for all plots.
        for(plot.name in names(result$plots)){
          result$plots[[plot.name]]$options[[d]] <- olist[[d]][[1]]
        }
      }else{ #use the size specified for the named plot.
        for(plot.name in names(olist[[d]])){
          result$plots[[plot.name]]$options[[d]] <- olist[[d]][[plot.name]]
        }
      }
    }
  }
  if(is.list(olist$time)){
    ms <- olist$time$ms
    stopifnot(is.numeric(ms))
    stopifnot(length(ms)==1)
    ## NOTE: although we do not use olist$ms for anything in the R
    ## code, it is used to control the number of milliseconds between
    ## animation frames in the JS code.
    v.name <- olist$time$variable
    stopifnot(is.character(v.name))
    stopifnot(length(v.name)==1)
    ## These geoms need to be updated when the v.name variable is
    ## animated, so let's make a list of all possible values to cycle
    ## through, from all the values used in those geoms.
    geom.names <- result$selectors[[v.name]]$subset
    anim.values <- list()
    for(g.name in geom.names){
      g <- result$geoms[[g.name]]
      click.or.show <- names(g$aes) %in% c("clickSelects","showSelected")
      anim.cols <- names(g$aes)[g$aes==v.name & click.or.show]
      g.data <- df.list[[g.name]][,anim.cols,drop=FALSE]
      g.vec <- unlist(g.data)
      anim.values[[g.name]] <- as.character(sort(unique(g.vec)))
    }
    olist$time$sequence <- unique(unlist(anim.values))
    result$time <- olist$time
  }
  ## Finally, copy html/js/json files to out.dir.
  src.dir <- system.file("htmljs",package="animint")
  to.copy <- Sys.glob(file.path(src.dir, "*"))
  file.copy(to.copy, out.dir, overwrite=TRUE, recursive=TRUE)
  json <- RJSONIO::toJSON(result)
  cat(json,file=file.path(out.dir,"plot.json"))
  if(open.browser){
    browseURL(sprintf("%s/index.html",out.dir))
  }
  invisible(result)
  ### An invisible copy of the R list that was exported to JSON.
}


#' Check if character is an RGB hexadecimal color value
#' @param x character 
#' @return True/False value
#' @export 
is.rgb <- function(x){
  grepl("NULL", x) | (grepl("#", x) & nchar(x)==7)
}

#' Convert R colors to RGB hexadecimal color values
#' @param x character
#' @return hexadecimal color value (if is.na(x), return "none" for compatibility with JavaScript)
#' @export
toRGB <- function(x){
  sapply(x, function(i) if(!is.na(i)) rgb(t(col2rgb(as.character(i))), maxColorValue=255) else "none")
} 

#' Function to get legend information from ggplot
#' @param plistextra output from ggplot2::ggplot_build(p)
#' @return list containing information for each legend
#' @export
getLegendList <- function(plistextra){
  plot <- plistextra$plot
  scales = plot$scales
  layers = plot$layers
  default_mapping = plot$mapping
  theme <- ggplot2:::plot_theme(plot)
  position <- theme$legend.position
  # by default, guide boxes are vertically aligned
  theme$legend.box <- if(is.null(theme$legend.box)) "vertical" else theme$legend.box
  
  # size of key (also used for bar in colorbar guide)
  theme$legend.key.width <- if(is.null(theme$legend.key.width)) theme$legend.key.size
  theme$legend.key.height <- if(is.null(theme$legend.key.height)) theme$legend.key.size
  # by default, direction of each guide depends on the position of the guide.
  theme$legend.direction <- if(is.null(theme$legend.direction)){
    if (length(position) == 1 && position %in% c("top", "bottom", "left", "right"))
      switch(position[1], top =, bottom = "horizontal", left =, right = "vertical")
    else
      "vertical"
  }
  # justification of legend boxes
  theme$legend.box.just <-
    if(is.null(theme$legend.box.just)) {
      if (length(position) == 1 && position %in% c("top", "bottom", "left", "right"))
        switch(position, bottom =, top = c("center", "top"), left =, right = c("left", "top"))
      else
        c("center", "center")
    } 
  
  position <- theme$legend.position
  guides = plyr::defaults(plot$guides, guides(colour="legend", fill="legend"))
  labels = plot$labels
  gdefs <- ggplot2:::guides_train(scales = scales, theme = theme, guides = guides, labels = labels)
  if (length(gdefs) != 0) {
    gdefs <- ggplot2:::guides_merge(gdefs)
    gdefs <- ggplot2:::guides_geom(gdefs, layers, default_mapping)
  } else (ggplot2:::zeroGrob())
  names(gdefs) <- sapply(gdefs, function(i) i$title)
  lapply(gdefs, getLegend)
}

#' Function to get legend information for each scale
#' @param mb single entry from ggplot2:::guides_merge() list of legend data
#' @return list of legend information, NULL if guide=FALSE.
getLegend <- function(mb){
  guidetype <- mb$name
  ## The main idea of legends:
  
  ## 1. Here in getLegend I export the legend entries as a list of
  ## rows that can be used in a data() bind in D3.

  ## 2. In add_legend in the JS code I create a <table> for every
  ## legend, and then I bind the legend entries to <tr>, <td>, and
  ## <svg> elements.
  geoms <- sapply(mb$geoms, function(i) i$geom$objname)
  cleanData <- function(orig, key, geom){
    if(nrow(orig)==0) return(data.frame()); # if no rows, return an empty df.
    orig$order <- 1:nrow(orig)
    count.na <- function(x)sum(is.na(x))
    orig.na <- sapply(orig, count.na)>0
    key.na <- sapply(key, count.na)>0
    by <- intersect(names(orig.na)[!orig.na], names(key.na)[!key.na])
    data <- merge(orig, key, by=by)
    data <- data[order(data$order),]
    if(!".label"%in%names(data)) return(data.frame()); # if there are no labels, return an empty df.
    data <- data[,which(colSums(!is.na(data))>0)] # remove cols that are entirely na
    if("colour"%in%names(data)) data[["colour"]] <- toRGB(data[["colour"]]) # color hex values
    if("fill"%in%names(data)) data[["fill"]] <- toRGB(data[["fill"]]) # fill hex values
    names(data) <- paste(geom, names(data), sep="") # aesthetics by geom
    names(data) <- gsub(paste(geom, ".", sep=""), "", names(data), fixed=TRUE) # label isn't geom-specific
    data
  }
#   conflict <- sapply(mb$geoms, function(i) i$geom$objname)
  dataframes <- lapply(mb$geoms, function(i) cleanData(i$data, mb$key, i$geom$objname))
  dataframes <- dataframes[which(sapply(dataframes, nrow)>0)]
  data <- merge_recurse(dataframes)
  data <- lapply(nrow(data):1, function(i) as.list(data[i,]))
  if(guidetype=="none"){
    NULL
  } else{
    list(guide = guidetype, 
         geoms = geoms, 
         title = mb$title, 
         entries = data)
  }
}

#' Function to merge a list of data frames (from the reshape package)
#' @param dfs list of data frames
#' @param ... other arguments to merge
#' @return data frame of merged lists
merge_recurse = function (dfs, ...) 
{
  if (length(dfs) == 1) {
    dfs[[1]]
  }
  else if (length(dfs) == 2) {
    merge(dfs[[1]], dfs[[2]], all.x = TRUE, sort = FALSE, ...)
  }
  else {
    merge(dfs[[1]], Recall(dfs[-1]), all.x = TRUE, sort = FALSE, 
          ...)
  }
}
