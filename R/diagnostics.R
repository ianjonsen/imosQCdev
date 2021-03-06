##' @title run QC diagnostics
##'
##' @description produces a map of all QC''d tracks and generates diagnostic tables to assess QC run
##'
##' @param fit the final foieGras fit object from QC process
##' @param fit1 the initial foieGras fit object from QC process
##' @param diag the standardized SMRU diag file (prior to truncation by metadata CTD start and end dates)
##' @param smru_ssm the ssm-annotated SMRU tables
##' @param meta metadata
##' @param mpath path to write map file
##' @param tpath path to write diagnostic table files
##'
##' @examples
##'
##' @importFrom dplyr "%>%" group_by summarise pull
##' @importFrom sf st_as_sf st_transform st_cast st_bbox
##' @importFrom rnaturalearth ne_countries
##' @importFrom ggplot2 ggplot geom_sf geom_point geom_rect facet_wrap aes theme_minimal xlim ylim ggsave
##' @importFrom lubridate decimal_date
##' @importFrom foieGras grab
##' @importFrom kableExtra kable kable_styling
##' @importFrom assertthat assert_that
##' @importFrom readr write_csv
##'
##' @export

diagnostics <-
  function(fit, fit1, diag, smru_ssm, meta,
           mpath = NULL,
           tpath = NULL) {

    assert_that(!is.null(mpath))
    assert_that(!is.null(tpath))

    ## generate map of predicted locations, subsampled to 6-h resolution
    ## ------------------------------------------------------------------------
    p <- grab(fit, "predicted", as_sf = FALSE) %>%
      rename(ref = id) %>%
      mutate(cid = str_extract(ref, regex("[a-z]+[0-9]+[a-z]?", ignore_case = TRUE)))

    p.lst <- split(p, p$ref)

    ## subsample predicted locs to 6-h resolution
    p_out <- lapply(p.lst, function(x) {
      ts <- subset(fit, id == x$ref[1])$ssm[[1]]$ts
      if (ts <= 6)
        x[seq(1, nrow(x), by = ceiling(6 / ts)),]
      else
        stop("time step is > 6 h, can't subsample to 6 h")
    }) %>%
      do.call(rbind, .)

    p_sf <- p_out %>%
      st_as_sf(., coords = c("lon","lat"),
               crs = 4326) %>%
      st_transform(., crs = 3032) %>%
      group_by(ref)

    p_latest_sf <- p_sf %>%
      filter(date == max(date)) %>%
      summarise(do_union = FALSE) %>%
      st_cast("MULTIPOINT")

    p_sf <- p_sf %>%
      summarise(do_union = FALSE) %>%
      st_cast("MULTIPOINT")

    coast <-
      rnaturalearth::ne_countries(scale = 50, returnclass = "sf") %>%
      sf::st_transform(., crs = "+proj=stere +lat_0=-90 +lat_ts=-71 +lon_0=70 +k=1 +ellps=WGS84 +units=km +no_defs")

    bounds <- sf::st_bbox(p_sf)
    bounds[c("xmin", "xmax")] <-
      extendrange(bounds[c("xmin", "xmax")], f = 0.2)
    bounds[c("ymin", "ymax")] <-
      extendrange(bounds[c("ymin", "ymax")], f = 0.2)

    mp <- ggplot(data = p_sf) +
      geom_sf(data = coast,
              lwd = 0) +
      xlim(bounds[c("xmin", "xmax")]) +
      ylim(bounds[c("ymin", "ymax")])

    mp <- mp + geom_sf(size = 0.05,
                       colour = "dodgerblue",
                       alpha = 0.2) +
      geom_sf(data = p_latest_sf,
              size = 1,
              colour = "firebrick") +
      theme_minimal()
    mp
    ggsave(
        file.path(mpath,
                  paste0("map_", Sys.Date(),".jpg")),
      width = 8,
      height = 10,
      units = "in",
      dpi = 300
    )
    diag <- diag %>% rename(device_id = ref)
    p_out <- p_out %>% rename(device_id = ref)
    dd <-
      diag %>% group_by(device_id) %>% summarise(
        start_date = min(date),
        end_date = max(date)
      )
    meta <- left_join(meta, dd, by = "device_id")
    ## Any device_id's in metadata but not in diag?
    meta_miss <- meta %>% filter(is.na(start_date) & is.na(end_date))
    meta <- meta %>% filter(!is.na(start_date) & !is.na(end_date))

    meta <- meta %>%
      mutate(ctd_start = ifelse(is.na(ctd_start), start_date, ctd_start)) %>%
      mutate(ctd_end = ifelse(is.na(ctd_end), end_date, ctd_end)) %>%
      mutate(ctd_start = as.POSIXct(ctd_start, origin = "1970-01-01", tz = "UTC"),
             ctd_end = as.POSIXct(ctd_end, origin = "1970-01-01", tz = "UTC"))

  ## coverage of standardized diag locations
  ## ------------------------------------------------------------------------
    p1 <- ggplot(diag) +
      geom_point(aes(date, lat), col = "blue") +
      geom_point(data = p_out,
                 aes(date, lat),
                 size = 0.25,
                 col = 'red') +
      geom_rect(
        data = meta,
        aes(
          xmin = start_date,
          xmax = ctd_start,
          ymin = -Inf,
          ymax = Inf
        ),
        alpha = 0.5,
        fill = grey(0.1),
        colour = NA
      ) +
      geom_rect(
        data = meta,
        aes(
          xmin = ctd_end,
          xmax = end_date,
          ymin = -Inf,
          ymax = Inf
        ),
        alpha = 0.5,
        fill = grey(0.1),
        colour = NA
      ) +
      facet_wrap(
        ~ device_id,
        scales = "free",
        ncol = 6,
        nrow = ceiling(length(unique(diag$device_id)) / 6)
      )

  p1
  ggsave(
    file.path(tpath,
              "lat_coverage.jpg"),
    width = 15,
    height = 20,
    units = "in",
    dpi = 150
    )

  p2 <- ggplot(diag) +
    geom_point(aes(date, lon), col = "blue") +
    geom_point(data = p_out,
               aes(date, lon),
               size = 0.25,
               col = 'red') +
    geom_rect(
      data = meta,
      aes(
        xmin = start_date,
        xmax = ctd_start,
        ymin = -Inf,
        ymax = Inf
      ),
      alpha = 0.5,
      fill = grey(0.1),
      colour = NA
    ) +
    geom_rect(
      data = meta,
      aes(
        xmin = ctd_end,
        xmax = end_date,
        ymin = -Inf,
        ymax = Inf
      ),
      alpha = 0.5,
      fill = grey(0.1),
      colour = NA
    ) +
    facet_wrap(
      ~ device_id,
      scales = "free",
      ncol = 6,
      nrow = ceiling(length(unique(diag$device_id)) / 6)
    )

  p2
  ggsave(
    file.path(tpath,
              "lon_coverage.jpg"),
    width = 15,
    height = 20,
    units = "in",
    dpi = 150
  )

  ## generate fit report summary tables
  ## ------------------------------------------------------------------------
  ## summary number of individuals passed by SSM filter stage
  tmp1 <- fit1 %>%
    summarise(nc = sum(converged), nf = sum(!converged))
  tmp <- fit %>%
    summarise(nc = sum(converged), nf = sum(!converged))

  bind_rows(tmp1, tmp) %>%
    mutate(N = rep(length(unique(diag$device_id)), 2)) %>%
    mutate(attempts = c("first","second")) %>%
    select(N, attempts, nc, nf) %>%
    kable("html") %>%
    kable_styling(bootstrap_options = c("striped","hover")) %>%
    cat(., file = file.path(tpath, "n_converged.html"))

  ## summary number of individuals by output file
  ndiag <- smru_ssm$diag %>% pull(ref) %>% unique() %>% length()
  nctd <- smru_ssm$ctd %>% pull(ref) %>% unique() %>% length()
  ndive <- smru_ssm$dive %>% pull(ref) %>% unique() %>% length()
  nhaul <- smru_ssm$haulout %>% pull(ref) %>% unique() %>% length()
  nsum <- smru_ssm$ssummary %>% pull(ref) %>% unique() %>% length()
  nssm <- p_out %>% pull(device_id) %>% unique() %>% length()

  diag_id <- smru_ssm$diag %>% pull(ref) %>% unique()
  meta_id <- bind_rows(meta, meta_miss) %>% pull(device_id)

  diag_not_in_meta <- diag_id[!diag_id %in% meta_id]
  meta_not_in_diag <- meta_id[!meta_id %in% diag_id]

  ndnim <- length(diag_not_in_meta)
  nmnid <- length(meta_not_in_diag)

  data.frame(ndiag, nctd, ndive, nhaul, nsum, nssm, ndnim, nmnid) %>%
    rename(
      diag = ndiag,
      ctd = nctd,
      dive = ndive,
      haulout = nhaul,
      summary = nsum,
      ssm = nssm,
      in_meta_not_in_SMRU = nmnid,
      in_SMRU_not_in_meta = ndnim
    ) %>%
    kable("html") %>%
    kable_styling(bootstrap_options = c("striped", "hover")) %>%
    cat(., file = file.path(tpath, "n_ind.html"))

  write(diag_not_in_meta, file = file.path(tpath, "diag_not_in_meta.txt"))
  write(meta_not_in_diag, file = file.path(tpath, "meta_not_in_diag.txt"))
  }

