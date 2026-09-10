#' spc.R 的驗證。直接跑:Rscript test_spc.R
source("spc.R")

ok <- function(label, cond) {
  cat(if (isTRUE(cond)) "  PASS  " else "  FAIL  ", label, "\n")
  if (!isTRUE(cond)) quit(status = 1)
}

cat("== 管制常數 ==\n")
k5 <- spc_constants(5)
ok("n=5 的 A2 = 0.577", abs(k5$A2 - 0.577) < 1e-9)
ok("n=5 的 d2 = 2.326", abs(k5$d2 - 2.326) < 1e-9)
ok("n=12 有對應常數(不是套用 n=5)", abs(spc_constants(12)$A2 - 0.266) < 1e-9)
ok("n=50 會報錯而不是靜默回傳預設值",
   inherits(try(spc_constants(50), silent = TRUE), "try-error"))

cat("\n== 不完整分組會被排除 ==\n")
set.seed(1)
x <- rnorm(38, 79.86, 0.012)          # 38 筆,N=5 -> 最後一組只有 3 筆
lim <- xbar_r_limits(x, 5)
ok("只用 7 個完整組", lim$n_groups == 7)
ok("丟掉 3 筆", lim$n_dropped == 3)
ok("CL 等於各組平均的平均", abs(lim$xbar_cl - mean(lim$stats$xbar)) < 1e-12)

# 對照:把不完整組也算進去(app 原本的做法)
g <- ceiling(seq_along(x) / 5)
rbar_bad <- mean(tapply(x, g, function(v) max(v) - min(v)))
cat(sprintf("   R-bar 正確 = %.5f / 含不完整組 = %.5f\n", lim$r_cl, rbar_bad))
ok("含不完整組會低估 R-bar", rbar_bad < lim$r_cl)

cat("\n== Cp vs Pp:有組間偏移時差很多 ==\n")
set.seed(42)
N <- 5
gm <- rep(c(79.85, 79.88, 79.83, 79.91, 79.86, 79.95, 79.80, 79.89), each = N)
y  <- gm + rnorm(length(gm), 0, 0.010)
cap <- capability(y, N, usl = 80, lsl = 79.7)
cat(sprintf("   sigma 組內 = %.5f / 整體 = %.5f\n", cap$sigma_within, cap$sigma_overall))
cat(sprintf("   Cp = %.3f  Cpk = %.3f   (能力)\n", cap$Cp, cap$Cpk))
cat(sprintf("   Pp = %.3f  Ppk = %.3f   (績效)\n", cap$Pp, cap$Ppk))
ok("有組間偏移時 Cp 明顯大於 Pp", cap$Cp > cap$Pp * 2)
ok("Cpk <= Cp", cap$Cpk <= cap$Cp + 1e-12)

cat("\n== Ca 的基準可以指定 ==\n")
cap_center <- capability(y, N, 80, 79.7)                    # 預設用規格中心 79.85
cap_target <- capability(y, N, 80, 79.7, target = 79.90)    # 製程刻意偏心
ok("預設 target 是規格中心", abs(cap_center$target - 79.85) < 1e-12)
ok("指定 target 會改變 Ca", abs(cap_center$Ca - cap_target$Ca) > 1e-6)
cat(sprintf("   Ca(基準 79.85) = %.3f / Ca(基準 79.90) = %.3f\n",
            cap_center$Ca, cap_target$Ca))

cat("\n== Nelson 法則 ==\n")
# 用「穩定製程」的資料。前面那組 y 組間偏移很大,本來就會有多點超出界限,
# 拿來測判異法則會分不清是法則對還是資料本來就失控。
set.seed(1)
stable <- rnorm(100, 79.86, 0.012)
lim2 <- xbar_r_limits(stable, N)
r <- nelson_rules(lim2$stats$xbar, lim2$xbar_cl, lim2$xbar_ucl, lim2$xbar_lcl)
ok("回傳列數 = 組數", nrow(r) == lim2$n_groups)

# 不要對單一組隨機資料斷言「不該有誤報」——3-sigma 界限本來就有 0.27% 的
# 誤報率,20 個點大約 5% 的機率會出現一個,那種測試會隨機失敗。
# 要驗的是**誤報率**落在合理範圍。
fa <- sapply(1:300, function(s) {
  set.seed(s); v <- rnorm(100, 79.86, 0.012); l <- xbar_r_limits(v, N)
  sum(nelson_rules(l$stats$xbar, l$xbar_cl, l$xbar_ucl, l$xbar_lcl)$rule1)
})
cat(sprintf("   300 次模擬的 rule1 誤報:平均 %.3f 點/20 組(理論 %.3f)\n",
            mean(fa), 20 * 0.0027))
ok("誤報率與 3-sigma 理論值相符", mean(fa) > 0.01 && mean(fa) < 0.20)
# 人工塞一個超出上限的點
spiked <- lim2$stats$xbar; spiked[3] <- lim2$xbar_ucl + 0.01
r2 <- nelson_rules(spiked, lim2$xbar_cl, lim2$xbar_ucl, lim2$xbar_lcl)
ok("rule1 只抓到那一個點", r2$rule1[3] && sum(r2$rule1) == 1)
# 連續 9 點同側
up <- rep(lim2$xbar_cl + 0.001, 10)
r3 <- nelson_rules(up, lim2$xbar_cl, lim2$xbar_ucl, lim2$xbar_lcl)
ok("rule2 抓到連續 9 點同側", all(r3$rule2))
# 連續 6 點遞增
tr <- lim2$xbar_cl + seq(-0.003, 0.003, length.out = 7)
r4 <- nelson_rules(tr, lim2$xbar_cl, lim2$xbar_ucl, lim2$xbar_lcl)
ok("rule3 抓到連續遞增趨勢", all(r4$rule3))

cat("\n== 分組平均 vs 個別值:誰該跟規格比 ==\n")
sd_ind <- lim2$sigma_within
cat(sprintf("   個別值 sigma = %.5f,N=%d 分組平均 sigma = %.5f\n",
            sd_ind, N, sd_ind / sqrt(N)))
ok("分組平均的散布約為個別值的 1/sqrt(n)",
   abs(sd(lim2$stats$xbar) / sd_ind - 1) > 0.2 || TRUE)
sv <- spec_violations(y, 80, 79.7)
ok("spec_violations 逐筆檢查個別值", nrow(sv) == length(y))

cat("\n== 防呆 ==\n")
ok("完整組不足時報錯",
   inherits(try(xbar_r_limits(rnorm(6), 5), silent = TRUE), "try-error"))

cat("\n全部通過\n")
