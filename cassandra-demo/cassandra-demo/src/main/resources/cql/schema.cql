-- Cassandra demo keyspace
-- The app's application.yml uses the same name (default cassandra_demo).
CREATE KEYSPACE IF NOT EXISTS cassandra_demo WITH REPLICATION = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};

-- Sensor readings, modelled the way Cassandra wants you to think:
--   partition key  = sensor_id  -> all rows for a sensor live on one partition
--   clustering key = timestamp  -> rows are physically ordered newest-first
-- This matches com.example.cassandrademo.model.SensorReading (+ SensorReadingKey).
CREATE TABLE IF NOT EXISTS cassandra_demo.sensor_readings (
    sensor_id   text,
    timestamp   timestamp,
    id          text,
    temperature double,
    humidity    double,
    PRIMARY KEY ((sensor_id), timestamp, id)
) WITH CLUSTERING ORDER BY (timestamp DESC);

-- Snowflake IDs stored by the app.
CREATE TABLE IF NOT EXISTS cassandra_demo.snowflake_ids (
    id           text PRIMARY KEY,
    generated_id bigint,
    worker_id    int,
    created_at   timestamp
);

-- Table used by the consistency demo (writes/reads at explicit consistency levels).
CREATE TABLE IF NOT EXISTS cassandra_demo.consistency_demo (
    id         text PRIMARY KEY,
    value      text,
    written_at timestamp
);