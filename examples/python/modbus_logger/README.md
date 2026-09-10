# Modbus 記錄器

食譜說明:
- [輪詢暫存器並寫成 CSV](https://loin123-rgb.github.io/dev-cookbook/recipes/modbus/read-registers-to-csv/)
- [解碼 32-bit 浮點數與縮放值](https://loin123-rgb.github.io/dev-cookbook/recipes/modbus/decode-registers/)

```bash
pip install -r requirements.txt
cp config.example.yaml config.yaml            # 改成你的裝置設定
python logger.py --config config.yaml --once  # 先驗證設定讀得到值
python logger.py --config config.yaml         # 開始長時間記錄,Ctrl+C 結束
```

不確定 word order 時,把讀到的兩個暫存器丟給 `decode.py`,四種解法都印出來讓你挑:

```bash
python decode.py 17244 19661
```
