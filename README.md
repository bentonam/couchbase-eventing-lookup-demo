# Eventing Airlines and Airports Lookup Demo

--

## Setup

Clone this repository

```bash
git clone https://github.com/bentonam/couchbase-eventing-lookup-demo.git
```
`cd` into the project directory

Go ahead and open up the project in your favorite IDE, if you using Atom just run `atom .` from terminal

This demo runs in a single Docker container, from terminal run the following command:

**Note:** Replace `$URL_TO_BUILD` with a valid rpm build

```bash
docker-compose build \
	--build-arg PACKAGE_URL=$URL_TO_BUILD \
	couchbase
```

This will build and tag the container.  The build reference that I'm using at this time is #1511.

Now start the container

```bash
docker-compose up -d
```

After a few seconds, the Couchbase container will be up and running.  This container has the following services enabled:

- Data
- Index
- Search
- Query
- Eventing

You can open the admin console by going to [http://localhost:8091/ui/index.html]() in a web browser.  The default username is `Administrator` and the `password` is password.  You can change these if you'd like in the `docker-compose.yaml` file.  

![](https://d3vv6lp55qjaqc.cloudfront.net/items/1N2z1z2n3s1b2G2c2S1l/Screen%20Recording%202018-02-06%20at%2010.34%20AM.gif?X-CloudApp-Visitor-Id=1639251&v=95dd8e8e)

![](assets/dashboard.png)

Browse to the [Buckets](http://localhost:8091/ui/index.html#!/buckets) tag and you will see there is two buckets created for you `flight-data` and `metadata`

![](assets/buckets.png)

## Models

This is an Airline / Airport lookup application that uses N1QL.  After loading our initial dataset, we will walk through several different ways to query the dataset, create indexes, and look at how we can perform the same queries without GSI indexes using lookup documents / inverted indexes.

We will have 3 different models in our dataset, 2 of which we will review now.  The airline and airports models are pretty self explanatory and contain information that you would expect to see.  Generally, almost all airlines and airports are assigned both an [IATA](http://www.iata.org/about/members/Pages/airline-list.aspx?All=true) (International Air Transport Association) and [ICAO](http://www.icao.int/) (International Civil Aviation Organization) or [FAA](http://www.faa.gov/) (Federal Aviation Administration)

- Airlines:
	- IATA / FAA: 2 characters
	- ICAO: 3 Characters
- Airports:
	- IATA / FAA: 3 characters
	- ICAO: 4 Characters

Our application will need to find airlines and airports based on their identifying IATA / ICAO / FAA code.  

### Airline

```json
{
  "_id": "airline::2009",
  "_type": "airline",
  "airline_id": 2009,
  "airline_name": "Delta Air Lines",
  "airline_iata": "DL",
  "airline_icao": "DAL",
  "callsign": "DELTA",
  "iso_country": "US",
  "active": true
}
```

#### Airport

```json
{
  "_id": "airport::3605",
  "_type": "airport",
  "airport_id": 3605,
  "airport_ident": "KICT",
  "airport_type": "large_airport",
  "airport_name": "Wichita Dwight D. Eisenhower National Airport",
  "geo": {
    "latitude": 37.64989853,
    "longitude": -97.43309784
  },
  "elevation": 1333,
  "iso_continent": "NA",
  "iso_country": "US",
  "iso_region": "US-KS",
  "municipality": "Wichita",
  "airport_icao": "KICT",
  "airport_iata": "ICT",
  "airport_gps_code": "KICT",
  "airport_local_code": "ICT",
  "timezone_offset": -6,
  "dst": "A",
  "timezone": "America/Chicago"
}
```

## Load Dataset

We need to first load our airline and airport datasets into Couchbase.  Execute the following command:

```bash
docker exec eventing-couchbase \
	fakeit couchbase \
	--server localhost \
	--username Administrator \
	--password password \
	--bucket flight-data \
	/usr/data/models/airlines.yaml,/usr/data/models/airports.yaml
```

This will load the `flight-data` bucket with ~`12,780` documents.  

## Queries

### Airline Codes

Now we want to query the datasets to be able to find airlines and airports based on their IATA or ICAO codes.  While the concept applies to both, for the purposes of this demo we're going to focus on just airlines.  Each Airline has 2 identifying codes a 2 character [IATA](http://www.iata.org/about/members/Pages/airline-list.aspx?All=true) / [FAA](http://www.faa.gov/) Code and a 3 character [ICAO](http://www.icao.int/) code.  Each of these attributes are stored as separate attributes on the airlines document as `airline_iata` and `airline_icao`.

Open the [Query Workbench](http://localhost:8091/ui/index.html#!/query/workbench) and execute the following statements.

##### Index

Create index for Airline IATA codes

```sql
CREATE INDEX idx_airlines_iata_codes ON `flight-data`(
	airline_iata
)
WHERE airline_iata IS NOT NULL
	AND _type = 'airline'
USING GSI;
```

Create index for Airline ICAO codes

```sql
CREATE INDEX idx_airlines_icao_codes ON `flight-data`(
	airline_icao
)
WHERE airline_icao IS NOT NULL
	AND _type = 'airline'
USING GSI;
```

##### Query

```sql
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS airlines
WHERE airlines.airline_iata = 'DL'
	AND airlines._type = 'airline'
UNION
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS airlines
WHERE airlines.airline_icao = 'DL'
	AND airlines._type = 'airline'
LIMIT 1;
```

##### Results

```json
[
  {
    "airline_iata": "DL",
    "airline_icao": "DAL",
    "airline_id": 2009,
    "airline_name": "Delta Air Lines"
  }
]
```

This performs much better as we are now using 2 different indexes for the IATA and ICAO codes.  However, we can improve this query even more.  

##### Index

Drop the previously created indexes as they will no longer be used.

```sql
DROP INDEX `flight-data`.idx_airlines_iata_codes;
```

```sql
DROP INDEX `flight-data`.idx_airlines_icao_codes;
```

## Lookup Documents

Based on our access pattern we want to ultimately find an airline or airport based on their IATA or ICAO code.  Instead of creating separate GSI indexes to satisfy our predicate, we can create lookup documents and achieve the same result still using N1QL but pure KV operations.  

From the Admin Console, flush the `flight-data` bucket or execute the following command from terminal

```bash
docker exec eventing-couchbase \
	couchbase-cli \
	bucket-flush \
	--cluster localhost \
	--username Administrator \
	--password password \
	--bucket flight-data \
	--force
```

Lookup documents are traditionally generated and maintained by the application that is writing the data.  Based on our models above, we'll create a lookup document that allows us to work with both airlines and airports.

```json
{
  "_id": "airport::code::KICT",
  "_type": "code",
  "id": 3605,
  "designation": "airport",
  "code_type": "icao",
  "code": "KICT"
}
```

Execute the following command to load the Airline and Airport documents, as well as the Codes lookup document.

```bash
docker exec eventing-couchbase \
	fakeit couchbase \
	--server localhost \
	--username Administrator \
	--password password \
	--bucket flight-data \
	/usr/data/models/airlines.yaml,/usr/data/models/airports.yaml,/usr/data/models/codes.yaml
```

This will take a few seconds, afterwards you'll have about `32,365` documents in the `flight-data` bucket

Our Codes model is keyed by `{{designation}}::code::{{code}}` i.e. `airline::code::DL`.  Because of how these documents are keyed, we do not even need a GSI index.  Using this predictive key pattern the code is used as part of the key name on the codes document.  Code is essentially an inverted index that we can store a small amout of data and get us back to our parent document.

##### Query

Query by the IATA code

```sql
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS codes
USE KEYS 'airline::code::DL'
INNER JOIN `flight-data` AS airlines
	ON KEYS 'airline::' || TOSTRING( codes.id );
```

Query by the ICAO code

```sql
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS codes
USE KEYS 'airline::code::DAL'
INNER JOIN `flight-data` AS airlines
	ON KEYS 'airline::' || TOSTRING( codes.id );
```

##### Results

```json
[
  {
    "airline_iata": "DL",
    "airline_icao": "DAL",
    "airline_id": 2009,
    "airline_name": "Delta Air Lines"
  }
]
```

We could follow these same queries for Airports, but the result is the same.  Using a lookup document / inverted index is the fastest query we can perform using a key lookup and inner join.  

## Events

So why did we go through this exercise?  Up until now, it has been the responsibility of the applications writing data to maintain these lookup documents / inverted indexes at document write time or they may have used the Kafka connector and had a separate application writing these documents, offloading those operations from their main application.  This is a perfect use case for Events to maintain these lookup documents for us.  

Let's start by flushing our `flight-data` bucket from the Admin Console or you can run the following command in terminal

```bash
docker exec eventing-couchbase \
	couchbase-cli \
	bucket-flush \
	--cluster localhost \
	--username Administrator \
	--password password \
	--bucket flight-data \
	--force
```

From the Admin Console, click on "Eventing"

Click "Add" and fill out the following and then click "Continue"

```
Source bucket: flight-data
Metadata bucket: metadata
Name: func_airline_airports_lookup_codes
Description:
	This event handles creation of lookups documents for airlines
	and airports based on their IATA and ICAO codes
RBAC username: Administrator
RBAC password: password
```

Click "Continue"

This will deploy a shell of our function that looks similar to:

![](assets/eventing.png)

Paste the following code into the editor:

### ES5 Construct (Officially Supported)

```javascript
function OnUpdate(doc, meta) {
    // make sure the document is only an airline or airport document
    if (
        doc._type &&
        'airline,airport'.indexOf(doc._type) !== -1
    ) {
        // loop over the 3 code types and use dynamic references of the
        // _type + code for population
        var codes = [ 'iata', 'icao', 'ident' ];
        for (var i = 0; i < codes.length; i++) {
            // set the value
            const value = doc[doc._type + '_' + codes[i]];
            // if the value exists, upsert it.  i.e. airline_iata,
            // airline_icao, airport_iata, airport_icao, airport_ident
            if (value) {
                // set the document id that we'll use
                var id = doc._type + '::code::' + value;
                // build the lookup document
                var data = {
                    _id: id,
                    _type: 'code',
                    id: doc[doc._type + '_id'],
                    designation: doc._type,
                    code_type: code,
                    code: doc[doc._type + '_' + codes[i]]
                };
                // upsert the code lookup document
                var ups = UPSERT INTO `flight-data` (KEY, VALUE)
                            VALUES (:id, JSON_DECODE(:data));
                ups.execQuery();
            }
        }
    }
}
function OnDelete(meta) {
}
```

### ES6 Construct (Not Officially Supported)

```javascript
function OnUpdate(doc, meta) {
    // make sure the document is only an airline or airport document
    if (
        doc._type &&
       [  'airline', 'airport'].includes(doc._type)
    ) {
        // loop over the 3 code types and use dynamic references of the
        // _type + code for population
        const codes = [ 'iata', 'icao', 'ident' ];
        for (const code of codes) {
            // set the value
            const value = doc[`${doc._type}_${code}`];
            // if the value exists, upsert it.  i.e. airline_iata,
            // airline_icao, airport_iata, airport_icao, airport_ident
            if (value) {
                // set the document id that we'll use
                const id = `${doc._type}::code::${value}`;
                // build the lookup document
                const data = {
                    _id: id,
                    _type: 'code',
                    id: doc[`${doc._type}_id`],
                    designation: doc._type,
                    code_type: code,
                    code: doc[`${doc._type}_${code}`]
                };
                // upsert the code lookup document
                const ups = UPSERT INTO `flight-data` (KEY, VALUE)
                            VALUES (:id, JSON_DECODE(:data));
                ups.execQuery();
            }
        }
    }
}
function OnDelete(meta) {
}
```

We now want to see what a mutation looks like but first we need to deploy our newly created function.

1. Click on "Eventing"
2. Click on your newly defined function `func_airline_airports_lookup_codes`
3. Click on "Deploy", leave the defaults
4. Click "Deploy Function"

Open another tab and open up the documents editor for the [flight-data bucket](http://localhost:8091/ui/index.html#!/buckets/documents?openedBucket=flight-data&bucket=flight-data&pageLimit=10&pageNumber=0).

Add a new document as follows:

**Key:** `airline_2009`

**Document:**

```json
{
  "_id": "airline::2009",
  "_type": "airline",
  "airline_id": 2009,
  "airline_name": "Delta Air Lines",
  "airline_iata": "DL",
  "airline_icao": "DAL",
  "callsign": "DELTA",
  "iso_country": "US",
  "active": true
}
```

After you have added the document, go back to the [Documents](http://localhost:8091/ui/index.html#!/buckets/documents?openedBucket=flight-data&bucket=flight-data&pageLimit=10&pageNumber=0) bucket and now you'll see that there are 3 documents, even though you only added 1.

![](assets/bucket-documents.png)

Let's reload just the airline and airport datasets with our eventing function still deployed.  Execute the following command to load just the airlines and airports documents into the bucket.  

```bash
docker exec eventing-couchbase \
	fakeit couchbase \
	--server localhost \
	--username Administrator \
	--password password \
	--bucket flight-data \
	/usr/data/models/airlines.yaml,/usr/data/models/airports.yaml
```

Now if we open the [Query Workbench](http://localhost:8091/ui/index.html#!/query/workbench) and execute the same look document queries that we previously ran we'll get the same results.

##### Query

Query by the IATA code

```sql
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS codes
USE KEYS 'airline::code::DL'
INNER JOIN `flight-data` AS airlines
	ON KEYS 'airline::' || TOSTRING( codes.id );
```

Query by the ICAO code

```sql
SELECT airlines.airline_id, airlines.airline_name,
	airlines.airline_iata, airlines.airline_icao
FROM `flight-data` AS codes
USE KEYS 'airline::code::DAL'
INNER JOIN `flight-data` AS airlines
	ON KEYS 'airline::' || TOSTRING( codes.id );
```

##### Results

```json
[
  {
    "airline_iata": "DL",
    "airline_icao": "DAL",
    "airline_id": 2009,
    "airline_name": "Delta Air Lines"
  }
]
```

We've successfully implementing and Eventing function to create lookup documents offloading their creation from our application.  
