-- Seed data for the sensor_readings table (matches schema.cql and the entity).
-- Three sensors, several readings each, newest timestamp first per partition.
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-1', '2026-08-28T12:00:00Z', 'r1', 22.5, 60.0);
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-1', '2026-08-28T11:00:00Z', 'r2', 23.1, 55.0);
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-1', '2026-08-28T10:00:00Z', 'r3', 21.0, 65.0);
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-2', '2026-08-28T12:30:00Z', 'r4', 19.5, 70.0);
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-2', '2026-08-28T11:30:00Z', 'r5', 20.2, 68.0);
INSERT INTO cassandra_demo.sensor_readings (sensor_id, timestamp, id, temperature, humidity) VALUES ('sensor-3', '2026-08-28T12:45:00Z', 'r6', 26.8, 44.0);