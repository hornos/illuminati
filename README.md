## Setup OSX

### Setup Monit
Monit is a sophisticated service orchestrator which is used to controll servers. At first, we introduce a simple local DDNS service based on Monit and dnsmasq. OS X tends to overwrite `/etc/resolv.conf` everytime you change netwokr configuration. There is no way to prepend a custom DNS address in DHCP mode. You have watch this file and inject `localhost` on every change.

Install Monit and dnsmasq:

    brew install monit dnsmasq

Install illuminati:

    cd $HOME; git clone git://github.com/hornos/illuminati.git; cd illuminati

Bootstrap illuminati:

    bin/bootstrap

Start Monit:

    bin/monit start

Check `http://localhost:2812` in your browser. If you change network the localhost DNS should be activated. Change network and check:

    cat /etc/resolv.conf

