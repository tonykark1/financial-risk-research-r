format_html_table <- function(x, digits = 4L, max_rows = 200L) {
  x <- as.data.frame(utils::head(x, max_rows))
  if (!nrow(x)) return("<p><em>No rows.</em></p>")
  numeric <- vapply(x, is.numeric, logical(1))
  x[numeric] <- lapply(x[numeric], function(z) {
    format(round(z, digits), big.mark = ",", trim = TRUE)
  })
  header <- paste(sprintf("<th>%s</th>", htmltools::htmlEscape(names(x))), collapse = "")
  body <- apply(x, 1L, function(row) {
    paste0("<tr>", paste(sprintf("<td>%s</td>", htmltools::htmlEscape(row)),
      collapse = ""), "</tr>")
  })
  paste0("<table><thead><tr>", header, "</tr></thead><tbody>",
    paste(body, collapse = ""), "</tbody></table>")
}

write_html_report <- function(title, executive_summary, sections, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  section_html <- unlist(lapply(names(sections), function(name) {
    value <- sections[[name]]
    content <- if (is.data.frame(value)) format_html_table(value) else as.character(value)
    paste0("<section><h2>", htmltools::htmlEscape(name), "</h2>", content,
      "</section>")
  }))
  html <- paste0(
    "<!doctype html><html><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width'><title>",
    htmltools::htmlEscape(title), "</title><style>",
    "body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:1100px;margin:40px auto;padding:0 24px;color:#17202a;line-height:1.5}",
    "h1{border-bottom:3px solid #1f618d;padding-bottom:12px}h2{margin-top:32px;color:#1f4e79}",
    ".summary{background:#eef5fa;border-left:5px solid #1f618d;padding:16px 20px}",
    "table{border-collapse:collapse;width:100%;font-size:13px;display:block;overflow-x:auto}",
    "th,td{border:1px solid #d5d8dc;padding:6px 8px;text-align:left;white-space:nowrap}",
    "th{background:#eaf2f8}tr:nth-child(even){background:#fafafa}</style></head><body>",
    "<h1>", htmltools::htmlEscape(title), "</h1><div class='summary'>",
    executive_summary, "</div>", paste(section_html, collapse = ""),
    "<footer><p>Generated ", format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
    " by the deterministic R demo.</p></footer></body></html>"
  )
  writeLines(html, path, useBytes = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

write_markdown_table <- function(x) {
  paste(capture.output(knitr::kable(x, format = "pipe")), collapse = "\n")
}
