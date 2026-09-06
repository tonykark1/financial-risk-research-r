select_filing_vintage <- function(data, as_of_date,
                                  keys = c("CIK", "period_end"),
                                  available_col = "available_at") {
  get_information_set(data, as_of_date = as_of_date,
    available_col = available_col, observation_col = "period_end",
    key_cols = keys
  )
}

select_first_filed_vintage <- function(data,
                                       keys = c("CIK", "frequency", "fiscal_year", "fiscal_period"),
                                       available_col = "available_at",
                                       accession_col = "accession") {
  dt <- data.table::as.data.table(data.table::copy(data))
  assert_schema_contract(dt, c(keys, available_col, accession_col), "filing vintage")
  dt[, (available_col) := as_date_utc(get(available_col))]
  data.table::setorderv(dt, c(keys, available_col, accession_col))
  dt[, .SD[1L], by = keys]
}
