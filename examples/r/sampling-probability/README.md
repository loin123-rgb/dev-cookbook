# 多產線混批的抽驗命中機率

食譜說明:<https://loin123-rgb.github.io/dev-cookbook/recipes/r/sampling-probability/>

```bash
Rscript hit_probability.R
```

```r
source("hit_probability.R")

qty  <- c(A = 0, B = 12497, C = 52503)
rate <- c(A = 0, B = 0.1908, C = 0)

hit_distribution(qty, rate, n_batch = 4, m_per_batch = 1)$p_at_least1
batches_needed(qty, rate, conf = 0.95, m_per_batch = 1)
```

沒有外部套件依賴,只用 base R 的 `dbinom()`。
