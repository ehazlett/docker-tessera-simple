#!/bin/bash
if [ -z "$DOCKER_HOST" ]; then
    echo "you must have docker and set the DOCKER_HOST env var"
    exit 1
fi

TOKEN=$(docker run swarm create)
MACHINE_NAME=${1:-tessera-demo}

# check if machine exists
docker-machine ip $MACHINE_NAME > /dev/null 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo "Creating Swarm"
    # create machine if not exist
    docker-machine create -d virtualbox --swarm --swarm-discovery token://$TOKEN --swarm-master $MACHINE_NAME
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
    -v /Users/ehazlett/.docker/machine/machines/$MACHINE_NAME:/m  \
    ehazlett/interlock:test \
    --swarm-url $MACHINE_URL \
    --swarm-tls-ca-cert=/m/ca.pem \
    --swarm-tls-cert=/m/server.pem \
    --swarm-tls-key=/m/server-key.pem \
    --plugin stats \
    start

echo "Tessera available at http://$IP:8080"
