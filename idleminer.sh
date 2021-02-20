#!/bin/bash

# Dependencies:
#   - xprintidle
#   - units
#   - jq

# Environment variables:
#   - IDLE_THRESHOLD :: Required. E.g. "10 minutes".
#   - ETHMINER_POOL :: Required. ethminer pool (for balance monitoring)
#   - DEBUG :: Optional. Set to 1 for debug prints.

SERVICE_NAME=$1

[[ -n "$ETHMINER_POOL" ]] || { echo "Please set ETHMINER_POOL"; exit 1; }
ethminer_address=$(sed 's|.*//\(0x[0-9a-fA-F]\+\).*|\1|' <<<"$ETHMINER_POOL")
short_ethminer_address="$(cut -c1-8 <<<${ethminer_address})...$(cut -c36- <<<${ethminer_address})"

# convert readable idle threshold to seconds
IDLE_THRESHOLD=${IDLE_THRESHOLD:-"10 minutes"}
idle_threshold_ms=$(units --terse "$IDLE_THRESHOLD" milliseconds)

# validate service name
# Not working for user services... :(
# [[ -n "$SERVICE_NAME" ]] || { usage; exit 1; }
# systemctl list-units --full --all | grep -Fq "$SERVICE_NAME" || {
#     echo "Can't find service: $SERVICE_NAME"
#     exit 1;
# }

usage() {
    echo "Usage: $0 <service-name>"
}

debug() {
    [[ "$DEBUG" = "1" ]] && echo $*
}

get_balance() {
    curl -s https://flexpool.io/api/v1/miner/${ethminer_address}/balance/ | jq -r '.result * pow(10; -18)'
}

print_balance() {
    echo "Balance of $ethminer_address: $(get_balance) ETH"
}

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
        [[ $new_balance != $prev_balance ]] && echo "NEW BALANCE on $short_ethminer_address 🚀: $new_balance"
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
            echo "USD earned this session: \$${usd_earned:0:5} 💸"
            initial_balance=$new_balance
        }
    fi
    sleep 10
done
