-- Cassandra demo keyspace
-- The app's application.yml uses the same name (default cassandra_demo).
CREATE KEYSPACE IF NOT EXISTS cassandra_demo WITH REPLICATION = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};

-- Sensor readings. This schema matches com.example.cassandrademo.model.SensorReading
-- (id is the primary key; sensor_id/temperature/humidity/timestamp are columns).
-- NOTE: modelling partition + clustering keys properly is the next improvement
-- batch (see IMPROVEMENT-TODO.md) and will change this table's PRIMARY KEY.
CREATE TABLE IF NOT EXISTS cassandra_demo.sensor_readings (
    id          text PRIMARY KEY,
    sensor_id   text,
    temperature double,
    humidity    double,
    timestamp   timestamp
);

-- Snowflake IDs stored by the app.
CREATE TABLE IF NOT EXISTS cassandra_demo.snowflake_ids (
    id           text PRIMARY KEY,
    generated_id bigint,
    worker_id    int,
    created_at   timestamp
);