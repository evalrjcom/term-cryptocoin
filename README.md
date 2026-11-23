# term-cryptocoin

Terminal candlestick charts for **BTC, ETH, USDT, BNB, USDC, and XRP**. All six use USD quotes from CoinGecko, including the two stablecoins.

## Run

Use Python 3.9 or newer. No packages are required.

```sh
git clone https://github.com/evalrjcom/term-cryptocoin.git
cd term-cryptocoin
python3 term_cryptocoin.py
python3 term_cryptocoin.py BTC ETH --days 7 --watch
```

On Windows, use `py -3` in place of `python3`. The tracker tries the public endpoint without credentials by default. If CoinGecko requires authentication or you have a [Demo API key](https://www.coingecko.com/en/api), set it in your shell:

```sh
export COINGECKO_DEMO_API_KEY='your-key'
```

In PowerShell, use `$env:COINGECKO_DEMO_API_KEY = 'your-key'`. Keep the key out of the repository.

## Chart controls

- Pass one or more ticker symbols to select charts. Omit them to show all six.
- Use `--days 1`, `7`, `30`, or `90`. CoinGecko supplies 30-minute candles for one day, 4-hour candles for seven and 30 days, and 4-day candles for 90 days. The chart shows as many of the latest candles as the terminal width allows.
- Use `--watch` to refresh every two minutes, or choose another interval with `--refresh SECONDS` (minimum 60). Press Ctrl+C to exit. Refreshing checks for newly published candles.
- Bodies use `+` for rising, `-` for falling, and `=` for flat. Wicks use `|`. Use `--no-color` to disable ANSI colors.
- The header shows the latest candle's open, high, low, close, and UTC closing time. Each coin uses its own price scale. Watch mode labels any cached chart shown after a failed refresh.

Data source: [CoinGecko Demo OHLC API](https://docs.coingecko.com/demo/reference/coins-id-ohlc).
