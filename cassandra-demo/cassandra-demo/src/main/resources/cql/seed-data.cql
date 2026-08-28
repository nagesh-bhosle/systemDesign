-- Seed data for the sensor_readings table (matches schema.cql and the entity).
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r1', 'sensor-1', '2026-08-28T12:00:00Z', 22.5, 60.0);
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r2', 'sensor-1', '2026-08-28T11:00:00Z', 23.1, 55.0);
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r3', 'sensor-1', '2026-08-28T10:00:00Z', 21.0, 65.0);
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r4', 'sensor-2', '2026-08-28T12:30:00Z', 19.5, 70.0);
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r5', 'sensor-2', '2026-08-28T11:30:00Z', 20.2, 68.0);
INSERT INTO cassandra_demo.sensor_readings (id, sensor_id, timestamp, temperature, humidity) VALUES ('r6', 'sensor-3', '2026-08-28T12:45:00Z', 26.8, 44.0);