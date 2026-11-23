#!/usr/bin/env bash
# Terminal USD candlesticks from Kraken's public spot API.
set -u
set -o pipefail

usage() {
    printf '%s\n' 'Usage: bash term-cryptocoin.sh [BTC ETH USDT BNB USDC XRP] [options]' \
        '  --interval MINUTES   1, 5, 15, 30, 60, 240, 1440, 10080, 21600 (default 30)' \
        '  --candles COUNT      1–720 (default 48, limited by terminal width)' \
        '  --watch              Refresh every 60 seconds in an interactive terminal' \
        '  --no-color           Disable red and green candle colors' \
        '  -h, --help           Show this help'
}

fail() {
    printf '%s\n' "$*" >&2
    exit 2
}

interval=30
count=48
watch=0
color=false
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
    color=true
fi
coins=()
while (( $# )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --interval)
            (( $# >= 2 )) || fail '--interval requires a value'
            case "$2" in
                1|5|15|30|60|240|1440|10080|21600) interval=$2 ;;
                *) fail 'Unsupported interval. See --help.' ;;
            esac
            shift ;;
        --candles)
            (( $# >= 2 )) || fail '--candles requires a value'
            [[ $2 =~ ^[1-9][0-9]{0,2}$ ]] && (( $2 <= 720 )) ||
                fail '--candles must be between 1 and 720'
            count=$2
            shift ;;
        --watch) watch=1 ;;
        --no-color) color=false ;;
        BTC|ETH|USDT|BNB|USDC|XRP) coins+=("$1") ;;
        *) fail "Unknown argument: $1. See --help." ;;
    esac
    shift
done

command -v curl >/dev/null || fail 'curl is required'
command -v jq >/dev/null || fail 'jq is required'
if (( watch )) && ! [[ -t 0 && -t 1 ]]; then
    fail '--watch requires an interactive terminal'
fi
if [[ -z ${coins[0]-} ]]; then
    coins=(BTC ETH USDT BNB USDC XRP)
fi
trap 'exit 130' INT

fetch_chart() {
    local coin=$1 limit=$2 pair
    case "$coin" in
        BTC) pair=XBTUSD ;;
        *) pair=${coin}USD ;;
    esac

    curl -q --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        "https://api.kraken.com/0/public/OHLC?pair=${pair}&interval=${interval}" |
        jq -er --arg coin "$coin" --argjson limit "$limit" --argjson interval "$interval" \
            --argjson color "$color" '
            def row($price; $high; $span):
                if $span == 0 then 5 else (($high - $price) / $span * 9 | round) end;
            # Apply direction color to each visible cell so it never spills into the axis.
            def paint($open; $close):
                if ($color | not) or . == " " or $open == $close then .
                elif $close > $open then "\u001b[32m" + . + "\u001b[0m"
                else "\u001b[31m" + . + "\u001b[0m" end;
            def axis:
                tostring | ("              " + .)[-([length, 14] | max):];

            if (.error | type) != "array" then error("invalid Kraken response")
            elif (.error | length) > 0 then error(.error | join(", "))
            else .result | del(.last) | to_entries | .[0].value
            end
            | if type != "array" or length == 0 then error("no candles returned") else . end
            | sort_by(.[0]) | .[-$limit:]
            | map(.[0:5] | map(tonumber)
                | . as [$t, $o, $h, $l, $c]
                | if length != 5 or $l < 0 or $l > ([$o, $c] | min)
                    or $h < ([$o, $c] | max) then error("invalid candle") else . end)
            | . as $candles
            | (map(.[2]) | max) as $high
            | (map(.[3]) | min) as $low
            | ($high - $low) as $span
            | last as [$t, $o, $h, $l, $c]
            | "\($coin)/USD  \($interval)m candles  Kraken",
              "Latest candle opened \($t | strftime("%Y-%m-%d %H:%M UTC")) (in progress)",
              "O \($o)  H \($h)  L \($l)  C \($c)",
              (range(0; 10) as $y |
                ($high - $span * $y / 9 | . * 1e8 | round / 1e8 | axis) + " |" +
                ($candles | map(. as [$_, $open, $top, $bottom, $close]
                  | row($open; $high; $span) as $a
                  | row($close; $high; $span) as $b
                  | if $y >= ([$a, $b] | min) and $y <= ([$a, $b] | max) then
                        if $open < $close then "+" elif $open > $close then "-" else "=" end
                    elif $y >= row($top; $high; $span) and $y <= row($bottom; $high; $span) then "|"
                    else " " end | paint($open; $close)) | join("")))
        '
}

charts=()
while :; do
    width=${COLUMNS:-80}
    # Bash tracks COLUMNS for interactive shells. Use an 80-column fallback.
    [[ $width =~ ^[1-9][0-9]{0,5}$ ]] || width=80
    limit=$((width > 18 ? width - 18 : 1))
    (( limit > count )) && limit=$count
    status=0
    output=
    for i in "${!coins[@]}"; do
        coin=${coins[$i]}
        if chart=$(fetch_chart "$coin" "$limit" 2>&1); then
            charts[$i]=$chart
            output+="$chart"
        else
            status=1
            output+="$coin/USD: fetch failed ($chart)"
            if [[ -n ${charts[$i]-} ]]; then
                output+=$'\nShowing last successful fetch\n'"${charts[$i]}"
            fi
        fi
        output+=$'\n\n'
    done
    if (( watch )) && [[ ${TERM-} != dumb ]]; then
        printf '\033[2J\033[H'
    fi
    printf 'Up: +   Down: -   Flat: =   Wick: |\n\n%s' "$output"
    (( watch )) || exit "$status"
    printf 'Refreshing in 60s. Press q to quit.\n'
    # A timed Bash read keeps watch mode free of external timer commands.
    SECONDS=0
    while (( SECONDS < 60 )); do
        key=
        IFS= read -rsn1 -t "$((60 - SECONDS))" key || break
        [[ $key == q || $key == Q ]] && exit 0
    done
done
