---
title: X̄-R 管制圖:管制界限怎麼算
parent: R 與統計品管
grand_parent: 食譜
nav_order: 1
permalink: /recipes/r/xbar-r-chart/
---

# X̄-R 管制圖:管制界限怎麼算
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/r/spc/spc.R`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/r/spc/spc.R)

## 公式

```
X̄ 圖:  CL = X̄̄            UCL/LCL = X̄̄ ± A2 · R̄
R  圖:  CL = R̄             UCL = D4 · R̄    LCL = D3 · R̄
組內 sigma:  σ̂ = R̄ / d2
```

`A2`、`D3`、`D4`、`d2` 是查表得來的常數,值取決於**分組大小 n**。

麻煩的地方全在這張表怎麼查、以及 X̄̄ 和 R̄ 用哪些資料算。

## 坑一:`switch` 加預設值會靜默算錯

很常見的寫法:

```r
A2 <- switch(as.character(N),
             "2"=1.880, "3"=1.023, "4"=0.729, "5"=0.577, "6"=0.483,
             "7"=0.419, "8"=0.373, "9"=0.337, "10"=0.308,
             0.577)                                    # ← 預設值
```

N 是 2~10 都對。但 N = 12、20、50 的時候呢?**靜默套用 N=5 的 0.577。**

```
  N=5  -> A2=0.577
  N=12 -> A2=0.577      ← 應該是 0.266
  N=20 -> A2=0.577      ← 應該是 0.180
  N=50 -> A2=0.577
```

N=20 時管制界限會變成正確值的 **3.2 倍寬**。這是所有錯誤裡**唯一往「太寬鬆」偏**的一種——界限太寬,真正的失控訊號抓不到。

{: .warning }
如果介面上的分組大小輸入是 `numericInput("group_n", value = 5, min = 2, max = 50)`,
那使用者**可以**輸入 12 或 20,而程式會安靜地給出錯誤的界限。
**輸入範圍和常數表的範圍必須一致。**

### 正確做法:查不到就報錯

```r
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
         1.548,1.541)
)

spc_constants <- function(n) {
  row <- SPC_CONSTANTS[SPC_CONSTANTS$n == as.integer(n), ]
  if (nrow(row) == 0) {
    stop(sprintf("分組大小 n=%d 沒有對應常數(支援 2~25)。n>25 請改用 X̄-S 圖。", n))
  }
  as.list(row)
}
```

**報錯比猜一個值好。** 使用者會看到明確訊息並改輸入;靜默預設值只會產生沒人發現的錯誤結論。

{: .note }
n > 25 時 R 圖的效率會下降,標準做法是改用 **X̄-S 管制圖**(用組內標準差 s 而不是全距 R)。
所以表格停在 25 不是偷懶,是那之後本來就該換工具。

## 坑二:不完整的最後一組會拉低 R̄

資料 38 筆、每組 5 筆 → 前 7 組完整,第 8 組只有 3 筆。

那 3 筆的**全距天生就比較小**(取樣點少,極值出現的機會低)。混進去算 R̄:

```
R-bar 只用完整組    = 0.02784
R-bar 含不完整組    = 0.02489      ← 低估 11%
```

R̄ 被低估 → 管制界限跟著變窄 → **假警報變多**。

```r
xbar_r_limits <- function(x, n) {
  k   <- spc_constants(n)
  g   <- ceiling(seq_along(x) / n)
  sizes <- as.integer(table(g))
  keep  <- sizes[g] == n                    # 只留完整組
  x <- x[keep]; g <- g[keep]

  stats <- do.call(rbind, lapply(split(x, g), function(v)
    data.frame(xbar = mean(v), R = max(v) - min(v))))

  xbb  <- mean(stats$xbar)                  # 各組平均的平均
  rbar <- mean(stats$R)

  list(xbar_cl = xbb, xbar_ucl = xbb + k$A2 * rbar, xbar_lcl = xbb - k$A2 * rbar,
       r_cl = rbar, r_ucl = k$D4 * rbar, r_lcl = k$D3 * rbar,
       sigma_within = rbar / k$d2, stats = stats)
}
```

## 坑三:同一份資料算出兩組不同的界限

最容易發生的情境:**摘要文字和圖表各算各的**。

```r
# 摘要區:沒有過濾不完整組
xbar <- mean(df$Size)
rbar <- mean(r_all$Size)

# 繪圖區:過濾了
valid <- as.integer(names(group_counts[group_counts == N]))
X_bar_bar <- mean(avg_df$Size)   # 只有完整組
```

結果:

```
summary: CL=79.87047  R-bar=0.02524  UCL=79.88503
plot   : CL=79.86976  R-bar=0.02751  UCL=79.88563
```

畫面上的數字和圖上的線**對不起來**。差異很小(0.0006),小到不會有人一眼看出,但足以讓「這個點到底有沒有超出」變成兩種答案。

{: .important }
**管制界限只能有一個計算來源。**
算一次,存在一個地方,摘要、圖表、匯出的 Excel 全部從那裡取用。
這在 Shiny 裡就是把它包成一個 `reactive()`。

```r
limits <- reactive({
  xbar_r_limits(filtered_data()$Size, input$group_n)
})

output$summary   <- renderPrint({ lim <- limits(); ... })
output$main_plot <- renderPlotly({ lim <- limits(); ... })
output$download  <- downloadHandler(content = function(f) { lim <- limits(); ... })
```

另外注意 `X̄̄` 的定義是**各組平均的平均**,不是所有原始值的平均。組都完整時兩者相等,有不完整組時就會不一樣——這也是上面那 0.0007 差異的來源之一。

## 坑四:原始點和分組平均的 x 軸對不齊

```r
add_trace(data = df,     x = ~group, y = ~Size)    # 原始值:x 是「組編號」
add_trace(data = avg_df, x = ~Index, y = ~Size)    # 分組平均:x 是「第幾個完整組」
```

`Index = seq_len(nrow(avg_df))`。只要**中間有任何一組被過濾掉**,`Index` 就不等於 `group`,兩條 trace 會在 x 軸上錯開。

修法:統一用同一個座標。要嘛兩邊都用 `group`,要嘛把原始資料也 join 上 `Index`:

```r
df2 <- merge(df, stats[, c("group", "index")], by = "group")
add_trace(data = df2,   x = ~index, y = ~value)
add_trace(data = stats, x = ~index, y = ~xbar)
```

## 驗證

```bash
cd examples/r/spc
Rscript test_spc.R
```

```
== 管制常數 ==
  PASS   n=5 的 A2 = 0.577
  PASS   n=12 有對應常數(不是套用 n=5)
  PASS   n=50 會報錯而不是靜默回傳預設值

== 不完整分組會被排除 ==
  PASS   只用 7 個完整組
   R-bar 正確 = 0.02784 / 含不完整組 = 0.02489
  PASS   含不完整組會低估 R-bar
...
全部通過
```

## 你該檢查的

- [ ] 常數表用 `switch` 加預設值嗎?N 超出範圍會怎樣?
- [ ] 輸入允許的 N 範圍,和常數表的範圍一致嗎?
- [ ] 不完整的最後一組有沒有被排除?
- [ ] 摘要、圖表、Excel 匯出用的是同一份界限嗎?
- [ ] `X̄̄` 算的是各組平均的平均,還是所有原始值的平均?
