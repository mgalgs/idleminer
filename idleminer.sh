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
#   - OVERNIGHT_START :: Optional. Hour after which mining may start.
#   - OVERNIGHT_END :: Optional. Hour after which mining must stop.


SERVICE_NAME=$1
LOGFILE=/tmp/idleminer.log

[[ -n "$ETHMINER_POOL" ]] || { echo "Please set ETHMINER_POOL"; exit 1; }
ethminer_address=$(sed 's|.*//\(0x[0-9a-fA-F]\+\).*|\1|' <<<"$ETHMINER_POOL")
short_ethminer_address="$(cut -c1-8 <<<${ethminer_address})...$(cut -c36- <<<${ethminer_address})"

# convert readable idle threshold to seconds
IDLE_THRESHOLD=${IDLE_THRESHOLD:-"10 minutes"}
idle_threshold_ms=$(units --terse "$IDLE_THRESHOLD" milliseconds)

if [[ -z "$OVERNIGHT_START" || -z "$OVERNIGHT_END" ]]; then
    HAVE_OVERNIGHT_WINDOW=no
else
    HAVE_OVERNIGHT_WINDOW=yes
fi

# validate service name
[[ -n "$SERVICE_NAME" ]] || { usage; exit 1; }

usage() {
    echo "Usage: $0 <service-name>"
}

debug() {
    [[ "$DEBUG" = "1" ]] && {
        echo $* | tee -a "$LOGFILE"
    }
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

check_in_overnight_window() {
    [[ $HAVE_OVERNIGHT_WINDOW = no ]] && {
        debug "No OVERNIGHT_START and OVERNIGHT_END. No time window restrictions."
        return 0
    }
    local hour=$(date +"%-H")
    [[ $hour -ge $OVERNIGHT_START || $hour -lt $OVERNIGHT_END ]] && {
        debug "Allowing start since hour ($hour) >= OVERNIGHT_START " \
              "($OVERNIGHT_START) or hour ($hour) < OVERNIGHT_END ($OVERNIGHT_END)"
        return 0
    }
    debug "Blocking start since hour ($hour) < OVERNIGHT_START " \
          "($OVERNIGHT_START) and hour ($hour) >= OVERNIGHT_END ($OVERNIGHT_END)"
    return 1
}

true > "$LOGFILE"
trap exit_handler TERM

debug "DISPLAY=$DISPLAY"
debug "XAUTHORITY=$XAUTHORITY"

prev_balance=$(get_balance)
initial_balance=$prev_balance
print_balance
echo -n "Will start mining once idle for $IDLE_THRESHOLD"
if [[ $HAVE_OVERNIGHT_WINDOW = yes ]]; then
    echo " and hour >= $OVERNIGHT_START and hour < $OVERNIGHT_END"
else
    echo
fi

while :; do
    idle_time_ms=$(xprintidle)
    debug "We have been idle for $idle_time_ms ms (waiting for $idle_threshold_ms)"

    if check_in_overnight_window; then
        in_overnight_window=yes
    else
        in_overnight_window=no
    fi
    if [[ $idle_time_ms -gt $idle_threshold_ms ]]; then
        sufficiently_idle=yes
    else
        sufficiently_idle=no
    fi

    if [[ $sufficiently_idle = yes ]] && [[ $in_overnight_window = yes ]]; then
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
            echo "$SERVICE_NAME needs to stop " \
                 "(in_overnight_window=$in_overnight_window, sufficiently_idle=$sufficiently_idle)"
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
