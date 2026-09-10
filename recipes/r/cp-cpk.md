---
title: Cp/Cpk 算錯的三種方式
parent: R 與統計品管
grand_parent: 食譜
nav_order: 2
permalink: /recipes/r/cp-cpk/
---

# Cp/Cpk 算錯的三種方式
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/r/spc/`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/r/spc)

## 問題

這段程式看起來完全合理:

```r
calc_cp <- function(data, usl, lsl) {
  sigma <- sd(data$Size)          # ← 問題在這一行
  (usl - lsl) / (6 * sigma)
}
```

它跑得出數字,數字看起來也很正常。但**它算的不是 Cp**。

## 錯誤一:用整體 sd 當 sigma

Cp/Cpk 定義裡的 sigma 是**組內標準差**(within-subgroup),要從 R̄ 推估:

```
sigma_within = R-bar / d2
```

`sd(x)` 算的是**整體標準差**,包含了組內變異**加上**組間變異。兩者只有在製程完全沒有漂移時才相等。

### 差距有多大

用一組「組內很穩、但組間會漂」的模擬資料(組內 sd = 0.01,組平均在 79.80~79.95 之間跳):

```
sigma 組內 = 0.01167     sigma 整體 = 0.04215

Cp  = 4.286   Cpk = 3.690    ← 用組內(正確的 Cp/Cpk)
Pp  = 1.186   Ppk = 1.021    ← 用整體(其實是 Pp/Ppk)
```

**差了 3.6 倍。** 一個說「製程能力綽綽有餘」,一個說「勉強及格」。

### 但用整體 sd 算出來的東西不是垃圾

它有自己的名字:**Pp / Ppk(製程績效指數)**。

| 指標 | 用哪個 sigma | 回答什麼問題 |
|:--|:--|:--|
| **Cp / Cpk** | 組內 `R̄/d2` | **這台機器有沒有能力做到?** |
| **Pp / Ppk** | 整體 `sd(x)` | **實際交出去的東西表現如何?** |

所以那段程式不是算錯,是**標籤掛錯**。把 Pp 叫成 Cp,溝通就會出事——客戶要 Cpk ≥ 1.33,你報了一個被低估的數字,等於自己扣自己分。

{: .important }
**兩個都算,一起報。差距本身就是資訊。**
- Cp ≈ Pp → 製程穩定,沒有漂移
- Cp ≫ Pp → **機器有能力,但製程中心在漂**
  → 該找的是漂移原因(換料、換班、刀具磨耗、溫度),不是換機器

### 正確寫法

```r
capability <- function(x, n, usl, lsl, target = NULL) {
  lim     <- xbar_r_limits(x, n)      # 只用完整分組
  sigma_w <- lim$sigma_within         # = R-bar / d2
  sigma_o <- sd(x)
  mu      <- mean(x)
  if (is.null(target)) target <- (usl + lsl) / 2

  list(
    Cp  = (usl - lsl) / (6 * sigma_w),                  # 能力
    Cpk = min(usl - mu, mu - lsl) / (3 * sigma_w),
    Pp  = (usl - lsl) / (6 * sigma_o),                  # 績效
    Ppk = min(usl - mu, mu - lsl) / (3 * sigma_o),
    Ca  = (mu - target) / ((usl - lsl) / 2)
  )
}
```

完整版(含防呆與 `sigma = 0` 的處理)在 [`spc.R`](https://github.com/loin123-rgb/dev-cookbook/blob/main/examples/r/spc/spc.R)。

## 錯誤二:Ca 的基準寫死成規格中心

常見寫法:

```r
ca <- (mean(data$Size) - (usl + lsl)/2) / ((usl - lsl)/2)
```

Ca 量的是「製程中心離**目標值**多遠」。預設用規格中心當目標沒錯,但**有些製程的目標本來就刻意不在中間**。

{: .example }
規格 USL = 80、LSL = 79.7,規格中心是 **79.85**。
但如果目標值訂在 **79.9**(例如刻意偏向上限留餘裕,或下限那側的失效後果比較嚴重),
那 Ca 就該以 79.9 為基準。用 79.85 算會得到 0.139,用 79.9 算是 −0.194——
**一個說偏上,一個說偏下,結論完全相反。**

如果介面上已經有一個獨立的「中心線 CL」輸入欄,卻沒有被 Ca 用到,那就是 bug:

```r
# 讓 target 可以傳入,不要寫死
capability(x, n, usl, lsl, target = input$cl)
```

## 錯誤三:拿分組平均去比規格界限

這種寫法很常見:

```r
avg_df$異常 <- (avg_df$Size > UCL) | (avg_df$Size < LCL) |
               (avg_df$Size > usl) | (avg_df$Size < lsl)   # ← 這兩項是錯的
```

**分組平均永遠不該跟規格界限比。**

理由是統計上的:n 個值取平均之後,散布會縮小成原來的 `1/√n`。

```
個別值 sigma        = 0.01167
N=5 分組平均 sigma  = 0.00522   (= 0.01167 / √5)
```

所以分組平均**幾乎永遠不會超出規格**,即使已經有個別值超出了。把它畫進「異常」判定裡:

- 對抓規格違反來說 → **形同無效**,給人「製程很穩」的錯覺
- 對抓製程失控來說 → 混進了不該有的條件,污染了管制圖的語意

{: .warning }
**管制界限和規格界限是兩套獨立的東西,不要混在同一個旗標裡。**
- **管制界限(UCL/LCL)** ← 由製程自己的變異算出來,比的是**分組平均**,回答「製程穩不穩」
- **規格界限(USL/LSL)** ← 客戶或標準要求,比的是**個別值**,回答「這件東西能不能出貨」

### 正確的分法

```r
# 製程失控:只看管制界限,只看分組平均
signals <- nelson_rules(lim$stats$xbar, lim$xbar_cl, lim$xbar_ucl, lim$xbar_lcl)

# 規格違反:只看個別值
violations <- spec_violations(x, usl, lsl)
```

兩張表分開看。一個製程可以:

| 情況 | 意思 |
|:--|:--|
| 管制內 + 規格內 | 正常 |
| 管制內 + **規格外** | 製程穩定,但**能力不足**——穩定地做出不良品 |
| **管制外** + 規格內 | 有異常訊號,雖然還沒做出不良品,**但趨勢不對** |
| 管制外 + 規格外 | 失控且已經出問題 |

第三種是管制圖真正的價值:**在還沒做出不良品之前就示警**。把規格混進管制判定,就是把這個能力關掉。

## 順帶一提:判異法則的誤報是正常的

3-sigma 界限本身就有約 **0.27%** 的誤報率。20 個點大約有 5% 的機率會出現一個「假的」失控點。

這代表兩件事:

1. 寫測試時**不要斷言「穩定製程不該有任何訊號」**——那種測試會隨機失敗。要驗的是誤報**率**:

   ```r
   fa <- sapply(1:300, function(s) {
     set.seed(s); v <- rnorm(100, 79.86, 0.012); l <- xbar_r_limits(v, 5)
     sum(nelson_rules(l$stats$xbar, l$xbar_cl, l$xbar_ucl, l$xbar_lcl)$rule1)
   })
   mean(fa)   # 0.070,理論值 20 * 0.0027 = 0.054 ✓
   ```

2. 現場看到單一一個超出界限的點,**先複驗再說**,不要立刻停線。連續的、有方向性的訊號(連續 9 點同側、連續 6 點遞增)比單點超出更值得緊張。

## 你該檢查的

如果你手上有在跑的管制圖工具:

- [ ] Cp/Cpk 用的是 `R̄/d2` 還是 `sd(x)`?用 `sd(x)` 的話,那是 Pp/Ppk
- [ ] Ca 的基準是規格中心還是目標值?介面上的 CL 欄位有沒有被用到?
- [ ] 「異常點」的判定裡有沒有混進 USL/LSL?
- [ ] 個別值對規格的檢查在哪裡做?有沒有做?
