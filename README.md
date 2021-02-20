# idleminer

Mine crypto while your computer is idle.

This might or might not be profitable or a good idea for you. It might make
sense if you have a negative power bill from solar and would like a better
return on that power generation than the pennies-on-the-dollar typically
offered by power companies, for example (hmmm, not specific at all, is
it?).

Only `ethminer` through [flexpool](https://flexpool.io/) is supported at
the moment.

## Installation

Install the prerequisites with your system package manager:

  - `xprintidle`
  - `units`
  - `jq`

Then copy the config and systemd units into their appropriate
directories. We use "user" service files since `xprintidle` doesn't work as
root (at least not without X11 authentication shenanigans).

    cp -v idleminer-environment ~/.config
    mkdir -pv ~/.config/systemd/user
    ln -sv $(realpath ethminer.service) ~/.config/systemd/user
    ln -sv $(realpath idleminer.service) ~/.config/systemd/user
    sudo ln -sv $(realpath idleminer.sh) /usr/local/bin/
    sudo ln -sv $(realpath start_ethminer.sh) /usr/local/bin/

then update `~/.config/idleminer-environment` with your miner address, etc.

Reload the `systemctl` daemon (note the lack of `sudo` since we're using
`--user`):

    systemctl --user daemon-reload

Then start `idleminer.service`:

    systemctl --user start idleminer.service

And that's it! Now when your computer is idle (as per `xprintidle`) for
longer than the period specified in your `idleminer-environment` the
`ethminer.service` will be kicked off and start mining. When `xprintidle`
detects user activity again `ethminer.service` will be stopped.

You can monitor the progress of `idleminer.service` and `ethminer.service`
with:

    journalctl --user -xf -u idleminer.service

and

    journalctl --user -xf -u ethminer.service
