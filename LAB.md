# Bash lab: Build a terminal crypto candlestick tracker

**Level:** Beginner with basic terminal navigation · **Time:** 45–60 minutes  
**Tools:** Bash, `curl`, and `jq`. The optional live step uses Kraken's public USD market data and requires internet access. No API key is needed.

You'll build a small tracker that reads OHLC data, classifies candle direction, and renders a text chart. Each step introduces a programming concept and gives you a checkpoint.

## 1. Check your tools and run the finished tracker

From the repository directory, run:

```bash
bash --version
curl --version
jq --version
bash term-cryptocoin.sh --help
```

Optional live preview:

```bash
bash term-cryptocoin.sh BTC --interval 30 --candles 8
```

Expect a BTC/USD header and a text chart. If the live request fails, continue with the offline fixture below.

## 2. Read JSON and identify a candle

Save this synthetic API response locally. The quoted heredoc delimiter `'JSON'` tells Bash to copy its contents literally. The `>` operator writes the file, replacing any existing file with that name.

```bash
cat > lab-candles.json <<'JSON'
{
  "error": [],
  "result": {
    "XXBTZUSD": [
      [1760000400, "100", "105", "99", "104"],
      [1760002200, "104", "106", "100", "101"],
      [1760004000, "101", "103", "100", "101"]
    ],
    "last": 1760004000
  }
}
JSON
jq '.result.XXBTZUSD[0]' lab-candles.json
```

**Checkpoint:** The first row contains a Unix timestamp followed by open, high, low, and close. Its opening price is 100 and its closing price is 104. The fixture shows only the fields used by this lab.

## 3. Extract and classify prices with a pipeline

```bash
jq -r '.result.XXBTZUSD[] | .[1:5] | map(tonumber)
       | . as [$open, $high, $low, $close]
       | if $close > $open then "up"
         elif $close < $open then "down"
         else "flat" end' lab-candles.json
```

The `jq` pipe feeds each value into the next filter. `.[1:5]` takes indices 1 through 4. `tonumber` converts price strings to numbers so comparisons are numeric. `-r` prints strings without JSON quotes.

**Checkpoint:** The command prints `up`, `down`, and `flat` on separate lines. Change the third close to `"102"` and predict the result, then restore `"101"`.

## 4. Start a script with arguments, branching, and a function

Save the code below as `lab-tracker.sh`. Keep both lab files in the same directory and run the script from there.

```bash
#!/usr/bin/env bash
set -u
set -o pipefail

fetch_candles() {
    local symbol=$1 pair
    case "$symbol" in
        BTC) pair=XBTUSD ;;
        ETH|USDT|BNB|USDC|XRP) pair="${symbol}USD" ;;
        *) printf 'Unsupported symbol: %s\n' "$symbol" >&2; return 2 ;;
    esac

    curl -q --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        "https://api.kraken.com/0/public/OHLC?pair=${pair}&interval=30"
}
```

- `$1` is the first positional argument to the function. `local` keeps its variables scoped to the function.
- `case` selects the market symbol. The combined pattern matches any of the five alternatives. `return 2` reports invalid input to the caller.
- Double quotes preserve the URL as one argument. `>&2` sends the diagnostic to standard error so it stays separate from JSON on standard output.
- `set -u` flags unset variables. `pipefail` makes a pipeline report failure when a stage fails.

**Checkpoint:** Run `bash -n lab-tracker.sh` to check its syntax. A successful syntax check prints nothing.

## 5. Parse records, use a Bash loop, and handle failures

Append this block to `lab-tracker.sh`. The parser removes Kraken's `last` cursor before reading the market's candle array.

```bash
print_candles() {
    local rows open high low close direction
    rows=$(jq -er '
        if (.error | type) != "array" then error("invalid response")
        elif (.error | length) > 0 then error(.error | join(", "))
        else .result | del(.last) | to_entries | .[0].value
        end
        | if type != "array" or length == 0 then error("no candles")
          else .[-5:][] end
        | .[1:5] | map(tonumber)
        | . as [$o, $h, $l, $c]
        | (if $c > $o then "+" elif $c < $o then "-" else "=" end) as $mark
        | [$o, $h, $l, $c, $mark] | @tsv
    ') || return 1

    while IFS=$'\t' read -r open high low close direction; do
        printf '%s  O=%s H=%s L=%s C=%s\n' "$direction" "$open" "$high" "$low" "$close"
    done <<< "$rows"
}

if (( $# == 0 )); then
    print_candles < lab-candles.json
else
    status=0
    for coin in "$@"; do
        printf '\n%s/USD\n' "$coin"
        if ! fetch_candles "$coin" | print_candles; then
            printf 'Could not display %s candles.\n' "$coin" >&2
            status=1
        fi
    done
    exit "$status"
fi
```

- `$(...)` captures parser output. Testing its exit status before the loop prevents a parse failure from looking like an empty success.
- `read -r` keeps backslashes literal. `IFS=$'\t'` makes tabs the field separator. The here-string `<<<` feeds the captured rows to the loop.
- `"$@"` preserves each input argument as a separate item. The script continues after a failed coin and returns status 1 if any coin failed.

**Offline checkpoint:** Run `bash lab-tracker.sh` and compare:

```text
+  O=100 H=105 L=99 C=104
-  O=104 H=106 L=100 C=101
=  O=101 H=103 L=100 C=101
```

**Failure checkpoint:** Run `bash lab-tracker.sh DOGE` followed immediately by `printf '%s\n' "$?"`. Expect an unsupported-symbol message and status `1`.

**Live checkpoint:** Run `bash lab-tracker.sh BTC ETH USDT BNB USDC XRP`. Each successful coin prints up to five candles. The latest live candle can still change.

## 6. Turn prices into chart coordinates

One candle occupies one column in the finished tracker. The open and close define the body. The high and low define the wick.

```bash
jq -n '
    def row($price; $top; $bottom):
        if $top == $bottom then 5
        else (($top - $price) / ($top - $bottom) * 9 | round) end;
    [row(110; 110; 90), row(100; 110; 90), row(90; 110; 90), row(100; 100; 100)]
'
```

**Checkpoint:** Expect `[0, 5, 9, 5]`. Terminal rows increase downward, so the highest price maps to row zero. A flat price range maps to the middle and avoids division by zero.

Open `term-cryptocoin.sh` and locate `fetch_chart`. Trace how the renderer loops over ten rows and draws a body mark before testing whether the cell belongs to the wick. Then run `bash term-cryptocoin.sh BTC ETH --interval 60 --candles 12 --watch` in an interactive terminal. Find the timed `read` in the Bash loop and press **q** to exit.

## Practice and review

1. **Array slicing:** In the lab script, change the slice from `.[-5:]` to `.[-2:]`. The offline run should now print only the down and flat candles.
2. **Arrays:** Add a `default_coins=(BTC ETH USDT BNB USDC XRP)` array. Try printing it with `printf '%s\n' "${default_coins[@]}"`, then find how the finished tracker loops over its array.
3. **Error handling:** Temporarily change the fixture's error field to `["simulated failure"]`. The offline script should print a diagnostic and exit with status 1. Restore the fixture afterward.
4. **Explain your work:** Why is `"$@"` quoted? Why does the script validate symbols before building a URL? Why does `jq` handle decimal arithmetic? For this lab, Bash controls the workflow and `jq` handles JSON and decimal-valued prices.
