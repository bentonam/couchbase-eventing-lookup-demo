#!/bin/bash
set -e

[[ "$1" == "couchbase-server" ]] && {
    echo "Starting Couchbase Server -- Web UI available at http://<ip>:8091 and logs available in /opt/couchbase/var/lib/couchbase/logs"
    # Create directories where couchbase stores its data
    cd /opt/couchbase
    mkdir -p var/lib/couchbase \
             var/lib/couchbase/config \
             var/lib/couchbase/data \
             var/lib/couchbase/stats \
             var/lib/couchbase/logs \
             var/lib/moxi
    cd /

    chown -R couchbase:couchbase var
    ./configure.sh & /opt/couchbase/bin/couchbase-server -- -kernel global_enable_tracing false -noinput

}

exec "$@"
