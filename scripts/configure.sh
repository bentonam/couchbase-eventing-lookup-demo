set -m

### DEFAULTS
CLUSTER_USERNAME=${CLUSTER_USERNAME:='Administrator'}
CLUSTER_PASSWORD=${CLUSTER_PASSWORD:='password'}
CLUSTER_NAME=${CLUSTER_NAME:='Demo'}
CLUSTER_RAMSIZE=${CLUSTER_RAMSIZE:=400}
SERVICES=${SERVICES:='data,index,query,fts,eventing'}


echo ' '
printf 'Waiting for Couchbase Server to start'
until $(curl --output /dev/null --silent --head --fail -u Administrator:password http://localhost:8091/pools); do
  printf .
  sleep 1
done

echo ' '
echo Couchbase Server has started

echo Configuring Node Settings
/opt/couchbase/bin/couchbase-cli node-init \
  --cluster localhost:8091 \
  --user=$CLUSTER_USERNAME \
  --password=$CLUSTER_PASSWORD \
  --node-init-data-path=${NODE_INIT_DATA_PATH:='/opt/couchbase/var/lib/couchbase/data'} \
  --node-init-index-path=${NODE_INIT_INDEX_PATH:='/opt/couchbase/var/lib/couchbase/indexes'} \
  --node-init-hostname=${NODE_INIT_HOSTNAME:='127.0.0.1'}

# configure master node
echo Configuring Cluster
CMD="/opt/couchbase/bin/couchbase-cli cluster-init"
CMD="$CMD --cluster localhost:8091"
CMD="$CMD --cluster-username=$CLUSTER_USERNAME"
CMD="$CMD --cluster-password=$CLUSTER_PASSWORD"
CMD="$CMD --cluster-ramsize=$CLUSTER_RAMSIZE"
# is the index service going to be running?
if [[ $SERVICES == *"index"* ]]; then
  CMD="$CMD --index-storage-setting=${INDEX_STORAGE_SETTING:=default}"
  CMD="$CMD --cluster-index-ramsize=${CLUSTER_INDEX_RAMSIZE:=256}"
fi
# is the fts service going to be running?
if [[ $SERVICES == *"index"* ]]; then
  CMD="$CMD --cluster-fts-ramsize=${CLUSTER_FTS_RAMSIZE:=256}"
fi
CMD="$CMD --services=$SERVICES"
eval $CMD

echo Setting the Cluster Name
/opt/couchbase/bin/couchbase-cli setting-cluster \
  --cluster localhost:8091 \
  --user=$CLUSTER_USERNAME \
  --password=$CLUSTER_PASSWORD \
  --cluster-name="$(echo $CLUSTER_NAME)"

# buckets
sleep 3

echo Creating "flight-data" bucket
/opt/couchbase/bin/couchbase-cli bucket-create \
  --cluster localhost:8091 \
  --user=$CLUSTER_USERNAME \
  --password=$CLUSTER_PASSWORD \
  --bucket=flight-data \
  --bucket-ramsize=300 \
  --bucket-type=couchbase \
  --enable-index-replica=0 \
  --enable-flush=1 \
  --bucket-replica=0 \
  --bucket-eviction-policy=valueOnly \
  --wait

sleep 3

echo Creating "metadata" bucket
/opt/couchbase/bin/couchbase-cli bucket-create \
  --cluster localhost:8091 \
  --user=$CLUSTER_USERNAME \
  --password=$CLUSTER_PASSWORD \
  --bucket=metadata \
  --bucket-ramsize=100 \
  --bucket-type=couchbase \
  --enable-index-replica=0 \
  --enable-flush=1 \
  --bucket-replica=0 \
  --bucket-eviction-policy=valueOnly \
  --wait

echo The $CLUSTER_NAME cluster has been successfully configured
