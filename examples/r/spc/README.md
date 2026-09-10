# X̄-R 管制圖與製程能力

食譜說明:
- [X̄-R 管制圖:管制界限怎麼算](https://loin123-rgb.github.io/dev-cookbook/recipes/r/xbar-r-chart/)
- [Cp/Cpk 算錯的三種方式](https://loin123-rgb.github.io/dev-cookbook/recipes/r/cp-cpk/)

沒有外部套件依賴,只用 base R。

```r
source("spc.R")

x <- c(...)                      # 依時間排序的量測值
lim <- xbar_r_limits(x, n = 5)   # 管制界限(只用完整分組)
cap <- capability(x, n = 5, usl = 80, lsl = 79.7)

cap$Cp   # 能力:用組內 sigma = R-bar/d2
cap$Pp   # 績效:用整體 sd
```

驗證:

```bash
Rscript test_spc.R
```

## 提供的函式

| 函式 | 用途 |
|:--|:--|
| `spc_constants(n)` | 取 d2/A2/D3/D4/c4,**n 超出 2~25 會報錯**而不是靜默回傳預設值 |
| `make_subgroups(x, n)` | 分組並標示哪些組是完整的 |
| `xbar_r_limits(x, n)` | X̄/R 管制界限,只用完整分組 |
| `capability(x, n, usl, lsl, target)` | Cp/Cpk(組內)與 Pp/Ppk(整體)一起回傳 |
| `nelson_rules(...)` | 判異法則 1~4,只作用在管制界限上 |
| `spec_violations(x, usl, lsl)` | 個別值對規格的判定 |
