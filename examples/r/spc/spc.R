#' X̄-R 管制圖與製程能力:正確的算法
#'
#' 重點在三件事:
#'   1. 管制常數要完整,不要用 switch 加預設值(N 超出範圍會靜默算錯)
#'   2. 只用「完整分組」算管制界限,不完整的組會把 R-bar 拉低
#'   3. Cp/Cpk 要用組內 sigma(R-bar/d2),不是整體 sd

# ---- 管制圖常數表 (ASTM / AIAG) ----------------------------------------
# d2: 由 R-bar 推估組內 sigma      sigma_within = R-bar / d2
# A2: X-bar 圖界限                 UCL = X-bar-bar ± A2 * R-bar
# D3/D4: R 圖界限                  UCL_R = D4 * R-bar,LCL_R = D3 * R-bar
# c4: 由 s-bar 推估 sigma          sigma_within = s-bar / c4
SPC_CONSTANTS <- data.frame(
  n  = 2:25,
  d2 = c(1.128,1.693,2.059,2.326,2.534,2.704,2.847,2.970,3.078,3.173,3.258,
         3.336,3.407,3.472,3.532,3.588,3.640,3.689,3.735,3.778,3.819,3.858,
         3.895,3.931),
  A2 = c(1.880,1.023,0.729,0.577,0.483,0.419,0.373,0.337,0.308,0.285,0.266,
         0.249,0.235,0.223,0.212,0.203,0.194,0.187,0.180,0.173,0.167,0.162,
         0.157,0.153),
  D3 = c(0,0,0,0,0,0.076,0.136,0.184,0.223,0.256,0.283,0.307,0.328,0.347,
         0.363,0.378,0.391,0.403,0.415,0.425,0.434,0.443,0.451,0.459),
  D4 = c(3.267,2.574,2.282,2.114,2.004,1.924,1.864,1.816,1.777,1.744,1.717,
         1.693,1.672,1.653,1.637,1.622,1.608,1.597,1.585,1.575,1.566,1.557,
         1.548,1.541),
  c4 = c(0.7979,0.8862,0.9213,0.9400,0.9515,0.9594,0.9650,0.9693,0.9727,
         0.9754,0.9776,0.9794,0.9810,0.9823,0.9835,0.9845,0.9854,0.9862,
         0.9869,0.9876,0.9882,0.9887,0.9892,0.9896)
)

#' 取得分組大小 n 的管制常數
#'
#' 超出表格範圍就**報錯**,不要靜默套用別的值。
spc_constants <- function(n) {
  n <- as.integer(n)
  row <- SPC_CONSTANTS[SPC_CONSTANTS$n == n, ]
  if (nrow(row) == 0) {
    stop(sprintf(
      "分組大小 n=%d 沒有對應的管制常數(支援 2~25)。n>25 請改用 X-bar/S 管制圖。", n))
  }
  as.list(row)
}

# ---- 分組 -------------------------------------------------------------

#' 依序把資料切成大小 n 的組,並標示哪些組是完整的
#'
#' @param x 數值向量,依時間排序
#' @param n 每組筆數
make_subgroups <- function(x, n) {
  stopifnot(is.numeric(x), n >= 2)
  g <- ceiling(seq_along(x) / n)
  sizes <- as.integer(table(g))
  data.frame(
    group    = g,
    value    = x,
    complete = sizes[g] == n
  )
}

# ---- 管制界限 ---------------------------------------------------------

#' 計算 X-bar 與 R 管制圖的界限
#'
#' 只使用**完整分組**。不完整的組(例如最後一組只有 3/5 筆)其全距天生偏小,
#' 混進去會讓 R-bar 被低估,管制界限跟著變窄,製造假的失控訊號。
#'
#' @return list(xbar/R 的 CL/UCL/LCL、各組統計、sigma_within、用掉幾組)
xbar_r_limits <- function(x, n) {
  k <- spc_constants(n)
  sub <- make_subgroups(x, n)
  sub <- sub[sub$complete, , drop = FALSE]

  n_groups <- length(unique(sub$group))
  if (n_groups < 2) {
    stop(sprintf("完整分組不足(只有 %d 組)。至少要 2 組才能算管制界限,建議 20~25 組。",
                 n_groups))
  }

  stats <- do.call(rbind, lapply(split(sub$value, sub$group), function(v) {
    data.frame(xbar = mean(v), R = max(v) - min(v))
  }))
  stats$group <- as.integer(rownames(stats))
  stats$index <- seq_len(nrow(stats))
  rownames(stats) <- NULL

  xbb  <- mean(stats$xbar)     # X-bar-bar = 各組平均的平均
  rbar <- mean(stats$R)

  list(
    n              = n,
    n_groups       = n_groups,
    n_used         = nrow(sub),
    n_dropped      = length(x) - nrow(sub),
    stats          = stats,
    xbar_cl        = xbb,
    xbar_ucl       = xbb + k$A2 * rbar,
    xbar_lcl       = xbb - k$A2 * rbar,
    r_cl           = rbar,
    r_ucl          = k$D4 * rbar,
    r_lcl          = k$D3 * rbar,
    sigma_within   = rbar / k$d2,
    constants      = k
  )
}

# ---- 製程能力 ---------------------------------------------------------

#' 製程能力(Cp/Cpk)與製程績效(Pp/Ppk)
#'
#' 兩者的差別只在用哪個 sigma:
#'   Cp/Cpk  用組內 sigma = R-bar/d2  -> 「這台機器有沒有能力」
#'   Pp/Ppk  用整體 sd                -> 「實際交出去的東西表現如何」
#'
#' 有組間偏移時 Cp 會遠大於 Pp。兩個都報,差距本身就是資訊:
#' 差很多 = 機器有能力,但製程中心在漂 -> 該找的是漂移原因,不是換機器。
#'
#' @param target Ca 的基準。預設用規格中心 (USL+LSL)/2;
#'               若製程刻意偏心(目標值不在中間),要明確傳入實際目標值。
capability <- function(x, n, usl, lsl, target = NULL) {
  stopifnot(usl > lsl)
  lim <- xbar_r_limits(x, n)

  sigma_w <- lim$sigma_within
  sigma_o <- sd(x)
  mu      <- mean(x)
  center  <- (usl + lsl) / 2
  if (is.null(target)) target <- center

  safe_div <- function(num, den) if (is.na(den) || den <= 0) NA_real_ else num / den

  list(
    mean         = mu,
    sigma_within = sigma_w,
    sigma_overall= sigma_o,
    # 能力:機器做得到什麼
    Cp   = safe_div(usl - lsl, 6 * sigma_w),
    Cpk  = safe_div(min(usl - mu, mu - lsl), 3 * sigma_w),
    # 績效:實際交出去的是什麼
    Pp   = safe_div(usl - lsl, 6 * sigma_o),
    Ppk  = safe_div(min(usl - mu, mu - lsl), 3 * sigma_o),
    # 偏移度:相對於 target,不是永遠相對於規格中心
    Ca   = safe_div(mu - target, (usl - lsl) / 2),
    target = target,
    limits = lim
  )
}

# ---- 異常判定 ---------------------------------------------------------

#' Nelson 判異法則(常用的前四條)
#'
#' 注意:這些法則全部作用在**分組平均**與**管制界限**上,
#' 絕對不要拿分組平均去比規格界限 USL/LSL——
#' 分組平均的散布只有個別值的 1/sqrt(n),那樣比幾乎永遠不會超出,
#' 會給人「製程很穩」的錯覺。規格要比的是**個別值**。
nelson_rules <- function(xbar, cl, ucl, lcl) {
  sigma <- (ucl - cl) / 3
  m <- length(xbar)
  z <- (xbar - cl) / sigma

  run_of <- function(flag, len) {
    out <- rep(FALSE, m)
    if (m < len) return(out)
    for (i in seq_len(m - len + 1)) {
      if (all(flag[i:(i + len - 1)])) out[i:(i + len - 1)] <- TRUE
    }
    out
  }

  # 規則 3:連續 6 點遞增或遞減
  trend <- rep(FALSE, m)
  if (m >= 6) {
    d <- diff(xbar)
    for (i in seq_len(m - 5)) {
      seg <- d[i:(i + 4)]
      if (all(seg > 0) || all(seg < 0)) trend[i:(i + 5)] <- TRUE
    }
  }

  data.frame(
    index = seq_len(m),
    xbar  = xbar,
    rule1 = xbar > ucl | xbar < lcl,                       # 單點超出 3 sigma
    rule2 = run_of(z > 0, 9) | run_of(z < 0, 9),           # 連續 9 點同側
    rule3 = trend,                                          # 連續 6 點趨勢
    rule4 = run_of(abs(z) > 2, 2)                           # 連續 2 點超出 2 sigma
  )
}

#' 個別值對規格的判定(這才是該跟 USL/LSL 比的東西)
spec_violations <- function(x, usl, lsl) {
  data.frame(index = seq_along(x), value = x,
             over_usl = x > usl, under_lsl = x < lsl)
}
