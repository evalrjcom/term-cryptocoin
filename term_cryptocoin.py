"""Display CoinGecko OHLC candles in a terminal."""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
import os
import shutil
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


COINS = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "USDT": "tether",
    "BNB": "binancecoin",
    "USDC": "usd-coin",
    "XRP": "ripple",
}
PERIODS = {1: "30m", 7: "4h", 30: "4h", 90: "4d"}
API = "https://api.coingecko.com/api/v3"


@dataclass(frozen=True)
class Candle:
    timestamp: datetime
    opening: float
    high: float
    low: float
    close: float


def parse_candles(payload):
    if not isinstance(payload, list) or not payload:
        raise ValueError("CoinGecko returned no candles")
    candles = {}
    for entry in payload:
        if (
            not isinstance(entry, list)
            or len(entry) != 5
            or any(type(value) not in (int, float) or not math.isfinite(value)
                   for value in entry)
        ):
            raise ValueError("CoinGecko returned a malformed candle")
        timestamp, opening, high, low, close = entry
        if not 0 <= low <= min(opening, close) <= max(opening, close) <= high:
            raise ValueError("CoinGecko returned inconsistent OHLC prices")
        timestamp = datetime.fromtimestamp(timestamp / 1000, timezone.utc)
        candles[timestamp] = Candle(timestamp, opening, high, low, close)
    return [candles[timestamp] for timestamp in sorted(candles)]


def fetch_candles(symbol, days, key):
    query = urlencode({"vs_currency": "usd", "days": days})
    request = Request(
        f"{API}/coins/{COINS[symbol]}/ohlc?{query}",
        headers={"Accept": "application/json", "User-Agent": "term-cryptocoin/1.0"},
    )
    if key:
        request.add_header("x-cg-demo-api-key", key)
    with urlopen(request, timeout=10) as response:
        return parse_candles(json.load(response))


def draw_chart(symbol, days, candles, width, color):
    height = 10
    candles = candles[-max(1, width - 16):]
    minimum = min(candle.low for candle in candles)
    maximum = max(candle.high for candle in candles)
    span = maximum - minimum

    def row(price):
        if span == 0:
            return height // 2
        return round((maximum - price) / span * (height - 1))

    chart = [[" "] * len(candles) for _ in range(height)]
    for column, candle in enumerate(candles):
        rising = candle.close > candle.opening
        direction = "=" if candle.close == candle.opening else ("+" if rising else "-")
        if color and direction != "=":
            shade = 32 if rising else 31
            direction = f"\033[{shade}m{direction}\033[0m"
        for y in range(row(candle.high), row(candle.low) + 1):
            chart[y][column] = "|"
        first, last = sorted((row(candle.opening), row(candle.close)))
        for y in range(first, last + 1):
            chart[y][column] = direction

    latest = candles[-1]
    heading = f"{symbol}/USD  {days}d range  {PERIODS[days]} candles  CoinGecko"
    ohlc = (
        f"O {latest.opening:.8g}  H {latest.high:.8g}  "
        f"L {latest.low:.8g}  C {latest.close:.8g}"
    )
    lines = [heading, f"{latest.timestamp:%Y-%m-%d %H:%M UTC} close  {ohlc}"]
    for y, cells in enumerate(chart):
        value = maximum - span * y / (height - 1)
        lines.append(f"{value:>14.8g} |{''.join(cells)}")
    lines.append(f"{candles[0].timestamp:%m-%d %H:%M} to {latest.timestamp:%m-%d %H:%M} UTC")
    return "\n".join(lines)


def describe_error(error):
    if isinstance(error, HTTPError):
        if error.code == 429:
            return "CoinGecko rate limit reached"
        if error.code in (401, 403):
            return f"CoinGecko access denied (HTTP {error.code}). Check COINGECKO_DEMO_API_KEY."
        return f"CoinGecko returned HTTP {error.code}"
    if isinstance(error, URLError):
        return f"connection failed ({error.reason})"
    return str(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coins", nargs="*", type=str.upper,
                        help="symbols to chart (default: BTC ETH USDT BNB USDC XRP)")
    parser.add_argument("--days", type=int, choices=PERIODS, default=1,
                        help="lookback window (default: 1)")
    parser.add_argument("--watch", action="store_true", help="refresh until Ctrl+C")
    parser.add_argument("--refresh", type=int, default=120,
                        help="seconds between watch refreshes (minimum 60, default 120)")
    parser.add_argument("--no-color", action="store_true", help="disable ANSI colors")
    args = parser.parse_args()
    symbols = list(dict.fromkeys(args.coins or COINS))
    for symbol in symbols:
        if symbol not in COINS:
            parser.error(f"unknown coin {symbol}. Choose from {', '.join(COINS)}")
    if args.refresh < 60:
        parser.error("--refresh must be at least 60 seconds")

    interactive = sys.stdout.isatty() and os.environ.get("TERM") != "dumb"
    # Older Windows consoles may display ANSI escapes as text.
    ansi = interactive and (os.name != "nt" or "WT_SESSION" in os.environ)
    color = ansi and not args.no_color and "NO_COLOR" not in os.environ
    key = os.environ.get("COINGECKO_DEMO_API_KEY")
    cache = {}
    while True:
        sections = []
        failed = False
        rate_limited = False
        width = shutil.get_terminal_size((80, 24)).columns
        for symbol in symbols:
            error_message = None
            if rate_limited:
                error_message = "skipped after CoinGecko rate limit"
            else:
                try:
                    cache[symbol] = fetch_candles(symbol, args.days, key)
                except (OSError, ValueError, OverflowError) as error:
                    error_message = describe_error(error)
                    rate_limited = isinstance(error, HTTPError) and error.code == 429
            if error_message:
                failed = True
                status = "showing last successful fetch" if symbol in cache else "no candles"
                sections.append(f"{symbol}: {error_message} ({status})")
            if symbol in cache:
                sections.append(draw_chart(symbol, args.days, cache[symbol], width, color))

        if args.watch and ansi:
            print("\033[2J\033[H", end="")
        print("Up: +   Down: -   Flat: =   Wick: |\n", flush=True)
        print("\n\n".join(sections), end="\n\n", flush=True)
        if not args.watch:
            return int(failed)
        delay = max(args.refresh, 120) if rate_limited else args.refresh
        print(f"Next refresh in {delay}s. Ctrl+C to exit.", flush=True)
        time.sleep(delay)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
