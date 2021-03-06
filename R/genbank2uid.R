#' Get NCBI taxonomy UID from GenBankID
#'
#' @export
#' @param id A GenBank accession alphanumeric string, or a gi numeric string.
#' @param batch_size The number of queries to submit at a time.
#' @param ... Curl args passed on to \code{\link[httr]{GET}}
#' @details See \url{http://www.ncbi.nlm.nih.gov/Sitemap/sequenceIDs.html} for
#' help on why there are two identifiers, and the difference between them.
#'
#' Note that if you pass in > 1 item, if one or more of your items is not
#' found, the entire batch will return \code{NA}'s. To get around this,
#' set \code{batch_size = 1} - so each is sent separtaely to NCBI.
#' However, this of course is much slower than the default, which is to send
#' up to 100 at a time.
#' @return one or more NCBI taxonomic IDs
#' @examples \dontrun{
#' # with accession numbers
#' genbank2uid(id = 'AJ748748')
#' genbank2uid(id = 'Y13155')
#' genbank2uid(id = 'X78312')
#' genbank2uid(id = 'KM495596')
#'
#' # with gi numbers
#' genbank2uid(id = 62689767)
#' genbank2uid(id = 22775511)
#' genbank2uid(id = 156446673)
#'
#' # pass in many accession or gi numbers
#' genbank2uid(c(62689767,156446673))
#' genbank2uid(c('X78312','KM495596'))
#' genbank2uid(list('X78312',156446673))
#'
#' # curl options
#' library('httr')
#' genbank2uid(id = 156446673, config=verbose())
#' }
genbank2uid <- function(id, batch_size = 100, ...) {
  assert(batch_size, c("integer", "numeric"))
  process_batch <- function(id, ...) {
    #removes version number of accession ids
    id <- gsub(pattern = "\\.[0-9]+$", "", id)
    url2 <- paste0(
      ncbi_base(),
      "/entrez/eutils/elink.fcgi?dbfrom=nucleotide&db=taxonomy&id=")
    query <- paste0(url2, paste(id, collapse = "&id="))
    res <- GET(query, ...)
    stop_for_status(res)
    result <- xml_text(xml_find_all(read_xml(con_utf8(res)),
                                    "//LinkSetDb//Link//Id"))
    if (length(result) > length(id)) {
      url3 <- paste0(
        ncbi_base(),
        "/entrez/eutils/esummary.fcgi?db=taxonomy&id=")
      query <- paste0(url3, paste(result, collapse = ","))
      res <- GET(query, ...)
      stop_for_status(res)
      nn <- xml_find_all(read_xml(con_utf8(res)), "//eSummaryResult//DocSum")
      result <- lapply(nn, function(z) {
        list(
          name = xml_text(xml_find_all(z, "Item[@Name=\"ScientificName\"]")),
          id = xml_text(xml_find_all(z, "Item[@Name=\"TaxId\"]"))
        )
      })
    }
    if (length(result) < length(id)) {
      result <- rep(NA_character_, length(id))
    }
    Sys.sleep(0.34) # NCBI limits requests to three per second
    return(result)
  }
  batches <- split(id, ceiling(seq_along(id) / batch_size))
  result <- lapply(batches, function(x) map_unique(x, process_batch, ...))

  if (!is.null(names(result[[1]][[1]]))) {
    result <- lapply(result[[1]], function(z) {
      m <- rep("found", length(z$id))
      m[is.na(z$id)] <- "not found"
      f <- as.uid(z$id, check = FALSE)
      attr(f, "match") <- m
      attr(f, "name") <- z$name
      f
    })
  } else {
    result <- as.uid(unname(unlist(result)))
    matched <- rep("found", length(result))
    matched[is.na(result)] <- "not found"
    attr(result, "match") <- matched
  }

  if (any(is.na(result))) {
    warning("An error occurred looking up taxon ID(s).")
    if (batch_size > 1 && length(id) > 1) {
      warning("NOTE: This function looks up IDs in batches to save time. However, the way that NCBI has implemented the API we use makes it so we cannot tell which IDs failed when a batch failed. Therefore, as few as one ID could be invalid yet still cause the whole batch to be NA. To identify the invalid IDs, set the 'batch_size' option to 1 and rerun the command.")
    }
  }
  return(result)
}

is_acc <- function(x){
  gg <- suppressWarnings(as.numeric(x))
  is.na(gg)
}

#=====================================================================
# get indexes of a unique set of the input
unique_mapping <- function(input) {
  unique_input <- unique(input)
  vapply(input, function(x) which(x == unique_input), numeric(1))
}

#=====================================================================
# run a function on unique values of a iterable
map_unique <- function(input, func, ...) {
  input_class <- class(input)
  unique_input <- unique(input)
  class(unique_input) <- input_class
  func(unique_input, ...)
  # func(unique_input, ...)[unique_mapping(input)]
}
