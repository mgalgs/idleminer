#!/bin/bash

# Dependencies:
#   - xprintidle
#   - units
#   - jq

# Environment variables:
#   - IDLE_THRESHOLD :: Required. E.g. "10 minutes".
#   - ETHMINER_ADDRESS :: Required. ethminer address to print out balance
#                         as we mine.
#   - DEBUG :: Optional. Set to 1 for debug prints.

# [[ $UID -eq 0 ]] || { echo "Must be run as root. Be better."; exit 1; }

SERVICE_NAME=$1

[[ -n "$ETHMINER_ADDRESS" ]] || { echo "Please set ETHMINER_ADDRESS"; exit 1; }
short_ethminer_address="$(cut -c1-8 <<<${ETHMINER_ADDRESS})...$(cut -c36- <<<${ETHMINER_ADDRESS})"

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
    curl -s https://flexpool.io/api/v1/miner/${ETHMINER_ADDRESS}/balance/ | jq -r '.result * pow(10; -18)'
}

print_balance() {
    echo "Balance of $ETHMINER_ADDRESS: $(get_balance) ETH"
}

prev_balance=$(get_balance)
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
        [[ $new_balance -ne $prev_balance ]] && echo "NEW BALANCE on $short_ethminer_address 🚀: $new_balance"
        prev_balance=$new_balance
    else
        # ensure it's not running
        systemctl --user is-active --quiet "$SERVICE_NAME" && {
            echo "$SERVICE_NAME needs to stop since we're no longer idle"
            systemctl --user stop "$SERVICE_NAME"
            # final balance print after transitioning to the stopped state
            print_balance
        }
    fi
    sleep 10
done
