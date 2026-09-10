#' 多產線混批的抽驗命中機率
#'
#' 問題:幾條產線各有不同不良率,產出混在一起。連續 n 批、每批抽 m 包,
#'       「至少抽到一次不良」的機率是多少?
#'
#' 直接跑:Rscript hit_probability.R

# ---- 輸入正規化 -------------------------------------------------------

#' 把「19.08」或「0.1908」都轉成 0.1908
#'
#' 這種寬鬆輸入有個無法消除的歧義:0.5 到底是 0.5% 還是 50%?
#' 這裡的規則是 >1 才除以 100,所以 0.5 會被當成 50%。
#' 介面上必須明確標示,或乾脆強制使用者選單位。
normalize_rate <- function(x, strict = FALSE) {
  if (is.null(x) || length(x) == 0) return(0)
  x <- suppressWarnings(as.numeric(x))
  if (is.na(x)) return(0)
  if (x < 0) stop("不良率不能為負數")
  if (strict) {
    if (x > 1) stop("strict 模式下不良率必須是 0~1 的小數")
    return(x)
  }
  if (x > 100) stop(sprintf("不良率 %g 超出範圍(最多 100%%)", x))
  if (x > 1) x / 100 else x
}

# ---- 模型 -------------------------------------------------------------

#' 單抽命中不良的機率:各產線不良率以「產量佔比」加權
#'
#' @param qty  各產線數量,數值向量
#' @param rate 各產線不良率(0~1),與 qty 等長
#'
#' 前提:抽出來那一包是從**混合後的整體**隨機抽的。
#' 如果每一批其實只來自某一條產線,這個加權平均不成立——
#' 那要改成逐批用該線自己的 p。
single_draw_p <- function(qty, rate) {
  stopifnot(length(qty) == length(rate))
  if (any(qty < 0)) stop("數量不能為負數")
  total <- sum(qty)
  if (total <= 0) stop("總數量必須 > 0")
  sum((qty / total) * rate)
}

#' 連續 n 批、每批抽 m 包的命中分布
#'
#' 每批抽 m 包,只要其中任一包不良就算「這批中了」:
#'   p_batch = 1 - (1 - p)^m
#' 然後 n 批的中批數服從 Binomial(n, p_batch)。
#'
#' 用的是二項分布(抽出放回 / 母體極大)。批量相對抽樣數很大時,
#' 與超幾何分布的差異可以忽略;批量很小時要改用 dhyper()。
hit_distribution <- function(qty, rate, n_batch, m_per_batch = 1) {
  stopifnot(n_batch >= 1, m_per_batch >= 1)
  p <- single_draw_p(qty, rate)
  p_batch <- 1 - (1 - p)^m_per_batch
  k <- 0:n_batch
  prob <- dbinom(k, size = n_batch, prob = p_batch)

  list(
    p_single    = p,
    p_batch     = p_batch,
    n_batch     = n_batch,
    m_per_batch = m_per_batch,
    table       = data.frame(k = k, prob = prob, pct = prob * 100),
    p_none      = prob[1],
    p_at_least1 = 1 - prob[1],
    expected    = n_batch * p_batch
  )
}

#' 反解:要抓到至少一次不良的機率達到 conf,需要連續驗幾批?
#'
#' 1 - (1-p_batch)^n >= conf  =>  n >= log(1-conf) / log(1-p_batch)
batches_needed <- function(qty, rate, conf = 0.95, m_per_batch = 1) {
  p <- single_draw_p(qty, rate)
  p_batch <- 1 - (1 - p)^m_per_batch
  if (p_batch <= 0) return(Inf)
  if (p_batch >= 1) return(1)
  ceiling(log(1 - conf) / log(1 - p_batch))
}

# ---- 示範 -------------------------------------------------------------

if (sys.nframe() == 0) {
  qty  <- c(A = 0, B = 12497, C = 52503)
  rate <- c(A = normalize_rate(0),
            B = normalize_rate(19.08),   # 19.08%
            C = normalize_rate(0))

  cat("=== 輸入 ===\n")
  for (nm in names(qty)) {
    cat(sprintf("  %s 產線:數量 %-8s 不良率 %7.4f%%\n", nm, qty[[nm]], rate[[nm]] * 100))
  }
  cat(sprintf("  合計:%d\n\n", sum(qty)))

  res <- hit_distribution(qty, rate, n_batch = 4, m_per_batch = 1)
  cat("=== 單抽命中機率 ===\n")
  cat(sprintf("  p = %.6f (%.4f%%)\n\n", res$p_single, res$p_single * 100))

  cat(sprintf("=== 連續 %d 批、每批抽 %d 包 ===\n", res$n_batch, res$m_per_batch))
  print(within(res$table, {
    prob <- round(prob, 6); pct <- round(pct, 4)
  }), row.names = FALSE)
  cat(sprintf("\n  P(一次都沒中) = %.6f (%.4f%%)\n", res$p_none, res$p_none * 100))
  cat(sprintf("  P(至少中 1 批) = %.6f (%.4f%%)\n", res$p_at_least1, res$p_at_least1 * 100))
  cat(sprintf("  期望中批數 = %.4f\n\n", res$expected))

  cat("=== 每批多抽幾包的效果 ===\n")
  for (m in c(1, 2, 3, 5, 10)) {
    r <- hit_distribution(qty, rate, n_batch = 4, m_per_batch = m)
    cat(sprintf("  每批抽 %2d 包:P(至少中 1 批) = %6.2f%%\n", m, r$p_at_least1 * 100))
  }

  cat("\n=== 要幾批才有 95% 把握抓到 ===\n")
  for (m in c(1, 2, 5)) {
    cat(sprintf("  每批抽 %d 包 -> 需要 %d 批\n", m, batches_needed(qty, rate, 0.95, m)))
  }
}
