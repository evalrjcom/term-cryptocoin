#!/usr/bin/env bash
# Study copy of term-cryptocoin.sh. Run with Bash, curl, and jq.
# Each numbered comment references the original source line. Continued commands
# are explained as groups so annotations never interrupt shell continuation.
#
# Data structures
#   coins and charts are parallel indexed Bash arrays. charts is a cache of
#   rendered strings. Kraken returns a JSON object with a market-to-rows mapping.
#   jq converts each row to [timestamp, open, high, low, close]. A chart row is
#   a string formed by joining an array of cells. The grid is emitted row by row.
#
# Algorithm and cost per market
#   For N received records and K displayed candles, sorting costs O(N log N).
#   Price extrema take O(K) and rendering uses O(10 × K) cell evaluations.
#   The JSON response occupies O(N) space. In watch mode the shell retains the
#   last successful rendered chart for each requested coin.
# Terminal USD candlesticks from Kraken's public spot API.
# L3: Shell option: report expansions of unset variables as errors.
set -u
# L4: Pipeline status: a failed curl or jq makes the pipeline fail.
set -o pipefail

# L6: Function declaration: help output can be called from the argument parser.
usage() {
    # L7: Lines 7–12: printf repeats one format for each quoted help string. Each trailing backslash joins the next physical line.
    printf '%s\n' 'Usage: bash term-cryptocoin.sh [BTC ETH USDT BNB USDC XRP] [options]' \
        '  --interval MINUTES   1, 5, 15, 30, 60, 240, 1440, 10080, 21600 (default 30)' \
        '  --candles COUNT      1–720 (default 48, limited by terminal width)' \
        '  --watch              Refresh every 60 seconds in an interactive terminal' \
        '  --no-color           Disable red and green candle colors' \
        '  -h, --help           Show this help'
# L13: End the help function.
}

# L15: Function declaration: centralize argument and setup errors.
fail() {
    # L16: Quoted $* joins the arguments into one message. >&2 directs it to standard error.
    printf '%s\n' "$*" >&2
    # L17: Exit the entire script with status 2 for usage errors.
    exit 2
# L18: End the error function.
}

# L20: Scalar assignment: candle duration in minutes.
interval=30
# L21: Scalar assignment: user limit on displayed candles.
count=48
# L22: Integer flag: zero means run once.
watch=0
# L23: Store a JSON boolean as shell text for jq.
color=false
# L24: Test stdout for a terminal, require a usable TERM, and check NO_COLOR. The :- expansion supplies a default for unset or empty values.
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
    # L25: Enable color only when all three conditions hold.
    color=true
# L26: End the terminal capability check.
fi
# L27: Initialize the indexed array that preserves requested coin order.
coins=()
# L28: Loop while the positional argument count is nonzero.
while (( $# )); do
    # L29: Dispatch on the current argument with shell patterns.
    case "$1" in
        # L30: Accept either help spelling and exit successfully.
        -h|--help) usage; exit 0 ;;
        # L31: This option consumes both a flag and a value.
        --interval)
            # L32: Guard access to $2 under set -u. The right side of || runs only on failure.
            (( $# >= 2 )) || fail '--interval requires a value'
            # L33: Validate the interval against a fixed set of supported values.
            case "$2" in
                # L34: Alternation matches any supported duration. Assign the validated value.
                1|5|15|30|60|240|1440|10080|21600) interval=$2 ;;
                # L35: The wildcard catches every other duration.
                *) fail 'Unsupported interval. See --help.' ;;
            # L36: End the nested interval dispatch.
            esac
            # L37: Consume one argument here. The common shift consumes the next one.
            shift ;;
        # L38: This option also takes a value.
        --candles)
            # L39: Reject a missing value before expanding it.
            (( $# >= 2 )) || fail '--candles requires a value'
            # L40: Lines 40–41: require 1–3 digits with no leading zero before doing arithmetic. On failed validation, call fail.
            [[ $2 =~ ^[1-9][0-9]{0,2}$ ]] && (( $2 <= 720 )) ||
                fail '--candles must be between 1 and 720'
            # L42: Store the validated candle count.
            count=$2
            # L43: Consume the extra argument and end this branch.
            shift ;;
        # L44: Set the watch flag.
        --watch) watch=1 ;;
        # L45: Override automatic terminal color detection.
        --no-color) color=false ;;
        # L46: Append the matched symbol as one array element.
        BTC|ETH|USDT|BNB|USDC|XRP) coins+=("$1") ;;
        # L47: Reject unknown flags and symbols via a wildcard.
        *) fail "Unknown argument: $1. See --help." ;;
    # L48: End argument dispatch.
    esac
    # L49: Discard the processed argument by moving the next argument into $1.
    shift
# L50: End the argument loop.
done

# L52: Look up curl through the shell. Redirect normal lookup output to /dev/null.
command -v curl >/dev/null || fail 'curl is required'
# L53: Require jq for JSON and decimal arithmetic.
command -v jq >/dev/null || fail 'jq is required'
# L54: Combine an arithmetic flag check with a negated terminal test on stdin and stdout.
if (( watch )) && ! [[ -t 0 && -t 1 ]]; then
    # L55: Report that watch mode needs a terminal for display and keyboard input.
    fail '--watch requires an interactive terminal'
# L56: End the watch compatibility check.
fi
# L57: Inspect array index zero. The - expansion substitutes empty text for an unset element.
if [[ -z ${coins[0]-} ]]; then
    # L58: Populate the indexed array with all six defaults.
    coins=(BTC ETH USDT BNB USDC XRP)
# L59: End default selection.
fi
# L60: Handle SIGINT from Ctrl+C with conventional exit status 130.
trap 'exit 130' INT

# L62: Function declaration: fetch and render one market.
fetch_chart() {
    # L63: Use local variables for function inputs and the API pair.
    local coin=$1 limit=$2 pair
    # L64: Translate the coin symbol into the Kraken pair name.
    case "$coin" in
        # L65: Kraken uses XBT for Bitcoin.
        BTC) pair=XBTUSD ;;
        # L66: Braces delimit the variable name before the literal USD suffix.
        *) pair=${coin}USD ;;
    # L67: End the symbol mapping.
    esac

    # L69: Lines 69–70: curl ignores its config file, fails on HTTP errors, suppresses progress, reports errors, and enforces timeouts. Quote the URL so & remains part of it.
    # L71–72: jq reads the pipe. -e sets failure status and -r emits raw strings.
    # --arg passes text and --argjson passes numeric and boolean values.
    curl -q --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        "https://api.kraken.com/0/public/OHLC?pair=${pair}&interval=${interval}" |
        jq -er --arg coin "$coin" --argjson limit "$limit" --argjson interval "$interval" \
            --argjson color "$color" '
            # L73: jq helper: map a price to a chart row.
            def row($price; $high; $span):
                # L74: Invert and scale prices into rows 0–9, rounding to the nearest row. A zero span uses row 5 to avoid division by zero.
                if $span == 0 then 5 else (($high - $price) / $span * 9 | round) end;
            # Apply direction color to each visible cell so it never spills into the axis.
            # L76: jq helper: decorate the current cell according to candle direction.
            def paint($open; $close):
                # L77: Return the cell unchanged for disabled color, blank cells, or equal open and close.
                if ($color | not) or . == " " or $open == $close then .
                # L78: Wrap rising cells in ANSI green followed by a reset.
                elif $close > $open then "\u001b[32m" + . + "\u001b[0m"
                # L79: Wrap falling cells in ANSI red followed by a reset. End the helper.
                else "\u001b[31m" + . + "\u001b[0m" end;
            # L80: jq helper: format a price label.
            def axis:
                # L81: Convert to text, pad on the left, and retain at least 14 characters or the entire number if longer.
                tostring | ("              " + .)[-([length, 14] | max):];

            # L83: Check that the response object contains an error array.
            if (.error | type) != "array" then error("invalid Kraken response")
            # L84: Convert a nonempty provider error array into a jq failure.
            elif (.error | length) > 0 then error(.error | join(", "))
            # L85: Remove the pagination cursor from the result object and select the first market array.
            else .result | del(.last) | to_entries | .[0].value
            # L86: End response dispatch.
            end
            # L87: Fail on missing, invalid, or empty candle data.
            | if type != "array" or length == 0 then error("no candles returned") else . end
            # L88: Sort the array by timestamp and keep only the newest requested records.
            | sort_by(.[0]) | .[-$limit:]
            # L89: Map each record to its first five fields and convert them to numbers.
            | map(.[0:5] | map(tonumber)
                # L90: Destructure the record into timestamp and four OHLC fields.
                | . as [$t, $o, $h, $l, $c]
                # L91: Lines 91–92: require five fields, a nonnegative low, and a high/low range enclosing both open and close.
                | if length != 5 or $l < 0 or $l > ([$o, $c] | min)
                    or $h < ([$o, $c] | max) then error("invalid candle") else . end)
            # L93: Bind the processed array for repeated traversal without replacing the current input.
            | . as $candles
            # L94: Reduce the high field across the visible candle array with max.
            | (map(.[2]) | max) as $high
            # L95: Reduce the low field across the same array with min.
            | (map(.[3]) | min) as $low
            # L96: Compute the price span shared by all plotted cells.
            | ($high - $low) as $span
            # L97: Take the final sorted record for the header.
            | last as [$t, $o, $h, $l, $c]
            # L98: Emit the title, then use the comma generator to emit additional lines from the same input.
            | "\($coin)/USD  \($interval)m candles  Kraken",
              # L99: Format the final timestamp as UTC and label this candle as in progress.
              "Latest candle opened \($t | strftime("%Y-%m-%d %H:%M UTC")) (in progress)",
              # L100: Interpolate the final open, high, low, and close.
              "O \($o)  H \($h)  L \($l)  C \($c)",
              # L101: Outer rendering loop: generate ten row indices.
              (range(0; 10) as $y |
                # L102: Interpolate the price at the row, round to eight decimal places, and add the price-axis separator.
                ($high - $span * $y / 9 | . * 1e8 | round / 1e8 | axis) + " |" +
                # L103: Inner rendering loop: produce one cell for each candle. $_ binds the unused timestamp.
                ($candles | map(. as [$_, $open, $top, $bottom, $close]
                  # L104: Project the open to a row coordinate.
                  | row($open; $high; $span) as $a
                  # L105: Project the close to a row coordinate.
                  | row($close; $high; $span) as $b
                  # L106: Check whether the current row lies between the two body endpoints, inclusive.
                  | if $y >= ([$a, $b] | min) and $y <= ([$a, $b] | max) then
                        # L107: Choose the body glyph by comparing open with close.
                        if $open < $close then "+" elif $open > $close then "-" else "=" end
                    # L108: If outside the body, draw a wick for rows between high and low.
                    elif $y >= row($top; $high; $span) and $y <= row($bottom; $high; $span) then "|"
                    # L109: Use a space outside the candle, color the cell, and join all cells into a row.
                    else " " end | paint($open; $close)) | join("")))
            # End the jq program. The next line closes the Bash string.
        '
# L111: End fetch_chart. The pipeline status is the function status.
}

# L113: Initialize the indexed chart cache. Each index corresponds to the same index in coins.
charts=()
# L114: Start an indefinite loop. The : builtin always succeeds, and run-once mode exits below.
while :; do
    # L115: Read COLUMNS or default to 80.
    width=${COLUMNS:-80}
    # Bash tracks COLUMNS for interactive shells. Use an 80-column fallback.
    # L117: Validate the width before passing it to arithmetic expansion.
    [[ $width =~ ^[1-9][0-9]{0,5}$ ]] || width=80
    # L118: Reserve columns for axis and spacing, with a minimum of one candle.
    limit=$((width > 18 ? width - 18 : 1))
    # L119: Cap the width-derived limit at the requested count.
    (( limit > count )) && limit=$count
    # L120: Reset the per-refresh failure flag.
    status=0
    # L121: Initialize the string buffer for all coin output.
    output=
    # L122: Iterate through the array indices so cached charts can use the same keys.
    for i in "${!coins[@]}"; do
        # L123: Read the symbol at the current array index.
        coin=${coins[$i]}
        # L124: Capture stdout and stderr, then branch on the function exit status.
        if chart=$(fetch_chart "$coin" "$limit" 2>&1); then
            # L125: Cache the successful render for later refreshes.
            charts[$i]=$chart
            # L126: Append the current chart to the display buffer.
            output+="$chart"
        # L127: Handle a failed fetch or render.
        else
            # L128: Remember that this refresh had at least one failure.
            status=1
            # L129: Append the error and its coin to the display buffer.
            output+="$coin/USD: fetch failed ($chart)"
            # L130: Check whether a previous chart exists at this index.
            if [[ -n ${charts[$i]-} ]]; then
                # L131: Append a stale-data label and cached chart. ANSI-C quoting interprets newline escapes.
                output+=$'\nShowing last successful fetch\n'"${charts[$i]}"
            # L132: End cache lookup.
            fi
        # L133: End the success/failure branch.
        fi
        # L134: Separate coin sections with two newlines.
        output+=$'\n\n'
    # L135: End per-coin iteration.
    done
    # L136: Clear the screen only in watch mode with a non-dumb terminal.
    if (( watch )) && [[ ${TERM-} != dumb ]]; then
        # L137: ANSI controls erase the display and move the cursor home.
        printf '\033[2J\033[H'
    # L138: End the screen-clear block.
    fi
    # L139: Print the legend and buffered output. Pass the buffer as data to a fixed format string.
    printf 'Up: +   Down: -   Flat: =   Wick: |\n\n%s' "$output"
    # L140: Exit with the refresh status in one-shot mode.
    (( watch )) || exit "$status"
    # L141: Print the refresh delay and quit control.
    printf 'Refreshing in 60s. Press q to quit.\n'
    # A timed Bash read keeps watch mode free of external timer commands.
    # L143: Reset Bash’s built-in elapsed-seconds counter.
    SECONDS=0
    # L144: Continue reading keys until the time budget expires.
    while (( SECONDS < 60 )); do
        # L145: Reset the key buffer.
        key=
        # L146: Read one silent, raw character with the remaining timeout. Empty IFS prevents trimming and a failed read ends the wait.
        IFS= read -rsn1 -t "$((60 - SECONDS))" key || break
        # L147: Exit successfully on either q or Q.
        [[ $key == q || $key == Q ]] && exit 0
    # L148: End the keyboard wait loop.
    done
# L149: Begin the next refresh by returning to the top of the outer loop.
done
