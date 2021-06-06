#!/bin/bash

# Dependencies:
#   - xprintidle
#   - units
#   - jq
#   - awk

# Environment variables:
#   - ETHMINER_POOL :: Required. ethminer pool (for balance monitoring)
#   - IDLE_THRESHOLD :: Optional. Default: "10 minutes". Any string usable
#                       with `units`.
#   - DEBUG :: Optional. Set to 1 for debug prints.

SERVICE_NAME=$1

[[ -n "$ETHMINER_POOL" ]] || { echo "Please set ETHMINER_POOL"; exit 1; }
ethminer_address=$(sed 's|.*//\(0x[0-9a-fA-F]\+\).*|\1|' <<<"$ETHMINER_POOL")
short_ethminer_address="$(cut -c1-8 <<<${ethminer_address})...$(cut -c36- <<<${ethminer_address})"

# convert readable idle threshold to seconds
IDLE_THRESHOLD=${IDLE_THRESHOLD:-"10 minutes"}
idle_threshold_ms=$(units --terse "$IDLE_THRESHOLD" milliseconds)

# validate service name
[[ -n "$SERVICE_NAME" ]] || { usage; exit 1; }

usage() {
    echo "Usage: $0 <service-name>"
}

debug() {
    [[ "$DEBUG" = "1" ]] && echo $*
}

get_balance() {
    curl -s "https://api.flexpool.io/v2/miner/balance?coin=ETH&address=${ethminer_address}" \
        | jq '.result.balance * pow(10; -18)'
}

get_effective_hashrate() {
    curl -s "https://api.flexpool.io/v2/miner/stats?coin=ETH&address=${ethminer_address}" \
        | jq '.result.averageEffectiveHashrate * .000001'
}

print_balance() {
    echo "Balance of $ethminer_address: $(get_balance) ETH"
}

exit_handler() {
    echo "Heading out 🏂 Stopping $SERVICE_NAME if needed."
    systemctl --user is-active --quiet "$SERVICE_NAME" && {
        systemctl --user stop "$SERVICE_NAME"
    }
    exit 0
}

trap exit_handler TERM

debug "DISPLAY=$DISPLAY"
debug "XAUTHORITY=$XAUTHORITY"

prev_balance=$(get_balance)
initial_balance=$prev_balance
print_balance

while :; do
    idle_time_ms=$(xprintidle)
    debug "We have been idle for $idle_time_ms ms (waiting for $idle_threshold_ms)"
    if [[ $idle_time_ms -gt $idle_threshold_ms ]]; then
        # ensure it's running
        systemctl --user is-active --quiet "$SERVICE_NAME" || {
            echo "$SERVICE_NAME wasn't running so we're starting that puppy since we've been idle for $IDLE_THRESHOLD"
            systemctl --user start "$SERVICE_NAME"
        }
        new_balance=$(get_balance)
        [[ $new_balance != $prev_balance ]] && {
            ehashrate=$(get_effective_hashrate)
            echo "NEW BALANCE on $short_ethminer_address 🚀: ${new_balance:0:8} (${ehashrate:0:5} MH/s)"
        }
        prev_balance=$new_balance
    else
        # ensure it's not running
        systemctl --user is-active --quiet "$SERVICE_NAME" && {
            echo "$SERVICE_NAME needs to stop since we're no longer idle"
            systemctl --user stop "$SERVICE_NAME"
            # final balance print after transitioning to the stopped state
            print_balance
            new_balance=$(get_balance)
            usd_earned=$(curl -s https://api.coinbase.com/v2/prices/ETH-USD/sell \
                             | jq ".data.amount|tonumber * ($new_balance - $initial_balance)")
            eth_earned=$(awk "BEGIN {printf \"%.8f\n\", $new_balance - $initial_balance}")
            echo "ETH earned this session: $eth_earned (\$${usd_earned:0:5}USD) 💸"
            initial_balance=$new_balance
        }
    fi
    sleep 10
done
