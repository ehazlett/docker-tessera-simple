#!/bin/bash
MACHINE_NAME=${1:-}
if [ -z "$MACHINE_NAME" ]; then
    echo "usage: $0 <docker-machine-name>"
    exit 1
fi

# check if machine exists
docker-machine ip $MACHINE_NAME > /dev/null 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo "error: you must have a Docker Machine created"
    exit 1
fi

# check if machine is a swarm master
docker-machine env --swarm $MACHINE_NAME > /dev/null 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo "error: machine must be a Swarm master"
    exit 1
fi

# get directory for tls certs
CERT_DIR=/etc/docker
DRIVER=`docker-machine ls | grep $MACHINE_NAME | awk '{ print $3; }'`
if [ "$DRIVER" = "virtualbox" ]; then
    CERT_DIR=/var/lib/boot2docker
fi

IP=$(docker-machine ip $MACHINE_NAME)
MACHINE_URL=$(docker-machine url $MACHINE_NAME)

$(docker-machine env $MACHINE_NAME)

echo "Starting Graphite"
# start graphite with carbon
docker run \
    -d \
    -p 8000:80 \
    -p 2003:2003 \
    -p 2004:2004 \
    -p 7002:7002 \
    --restart=always \
    --name graphite \
    nickstenning/graphite

echo "Starting Tessera"
# start tessera
docker run \
    -ti \
    -d \
    -p 8080:80 \
    -e GRAPHITE_URL=http://$IP:8000 \
    --restart=always \
    --name tessera \
    ehazlett/tessera-swarm

# wait for graphite to become ready
sleep 5

echo "Starting Interlock"
# start interlock with stats plugin
docker run \
    -ti \
    -d \
    --name interlock \
    --restart=always \
    -e STATS_CARBON_ADDRESS=$IP:2003 \
    -v $CERT_DIR:/certs  \
    ehazlett/interlock:test \
    --swarm-url tcp://$IP:3376 \
    --swarm-tls-ca-cert=/certs/ca.pem \
    --swarm-tls-cert=/certs/server.pem \
    --swarm-tls-key=/certs/server-key.pem \
    --plugin stats \
    -D \
    start

echo "Tessera available at http://$IP:8080"
