# 新增一篇食譜

## 1. 建檔

在 `recipes/<分類>/` 底下新增一個 `.md`,front matter 照這個格式:

```yaml
---
title: 食譜標題
parent: Excel 與試算表      # 分類頁的 title,要一字不差
grand_parent: 食譜
nav_order: 4                # 同分類內的排序
permalink: /recipes/excel/your-slug/
---
```

`parent` 打錯字的話,頁面不會出現在左側導覽——**但也不會報錯**,是最常見的失誤。

## 2. 內容骨架

```markdown
# 食譜標題
{: .no_toc }

<details open markdown="block">
  <summary>本頁目錄</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

程式碼:[`examples/...`](https://github.com/loin123-rgb/dev-cookbook/tree/main/examples/...)

## 問題
一段話說清楚痛點,包含實際的數字或錯誤訊息。

## 解法
最小可用的程式碼,附上為什麼這樣寫。

## 踩過的坑
**粗體一句話結論。**
接一段解釋。
```

「踩過的坑」是必寫的。只有解法沒有坑的話,那是文件不是食譜。

## 3. 附上可執行程式碼

放到 `examples/` 對應資料夾,附 `requirements.txt` 或 `package.json` 和一份簡短的 `README.md`。

原則:

- 路徑走 `argparse` / `parseArgs` 參數,不要寫死。
- 單筆失敗不要擋掉整批,包 `try/except` 並印出跳過清單。
- **貼進食譜的程式碼要真的跑過。** 輸出範例直接複製終端機的實際結果,不要憑印象寫。

## 4. 新增分類

在 `recipes/` 底下開資料夾,加一個 `index.md`:

```yaml
---
title: 新分類
parent: 食譜
nav_order: 5
has_children: true
permalink: /recipes/new-category/
---
```

然後把它加進 `index.md` 和 `recipes/index.md` 的索引表格。

## 5. 本機預覽

```bash
bundle exec jekyll serve
```

推上 `main` 後 GitHub Pages 會自動建置,約一到兩分鐘生效。
