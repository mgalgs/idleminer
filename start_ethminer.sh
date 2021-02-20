#!/bin/bash

[[ -n "$ETHMINER_POOL" ]] || { echo "Please set ETHMINER_POOL"; exit 1; }

/usr/sbin/ethminer --cuda --pool $ETHMINER_POOL
