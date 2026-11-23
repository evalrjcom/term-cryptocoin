# term-cryptocoin

Terminal USD candlestick charts for **BTC, ETH, USDT, BNB, USDC, and XRP**. The Bash tracker uses `curl` and `jq` with Kraken's free public spot API. It requires no API key or account.

```sh
git clone https://github.com/evalrjcom/term-cryptocoin.git
cd term-cryptocoin
bash term-cryptocoin.sh
bash term-cryptocoin.sh BTC ETH XRP --interval 60 --candles 24 --watch
```

Run from Bash with `curl` and `jq` on your PATH. On Windows, use Git Bash or WSL with those tools installed.

- Omit symbols to chart all six. The defaults are 30-minute candles and up to 48 candles per chart.
- Use `--interval` for candle duration in minutes and `--candles` for the maximum number of candles to show. Run `bash term-cryptocoin.sh --help` for all choices. The chart uses `COLUMNS` if set and assumes 80 columns otherwise.
- Use `--watch` in an interactive terminal to refresh every 60 seconds. Press **q** or **Ctrl+C** to exit. If a refresh fails, the tracker labels and displays the last successful chart for that coin when available.
- Bodies use `+` for rising, `-` for falling, and `=` for flat. Wicks use `|`. The chart includes Kraken's current, in-progress candle and shows its UTC opening time and OHLC values.

Data source: [Kraken public OHLC API](https://docs.kraken.com/api-reference/market-data/get-ohlc-data).

## Python tracker

The original CoinGecko tracker is available with `python3 term_cryptocoin.py --help`. It uses Python 3.9+ and accepts an optional CoinGecko Demo API key in `COINGECKO_DEMO_API_KEY`.
