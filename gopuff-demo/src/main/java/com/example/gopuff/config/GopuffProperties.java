package com.example.gopuff.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "gopuff")
public class GopuffProperties {

    private Nearby nearby = new Nearby();
    private TravelTime travelTime = new TravelTime();
    private Inventory inventory = new Inventory();
    private Cache cache = new Cache();
    private Orders orders = new Orders();

    public Nearby getNearby() {
        return nearby;
    }

    public void setNearby(Nearby nearby) {
        this.nearby = nearby;
    }

    public TravelTime getTravelTime() {
        return travelTime;
    }

    public void setTravelTime(TravelTime travelTime) {
        this.travelTime = travelTime;
    }

    public Inventory getInventory() {
        return inventory;
    }

    public void setInventory(Inventory inventory) {
        this.inventory = inventory;
    }

    public Cache getCache() {
        return cache;
    }

    public void setCache(Cache cache) {
        this.cache = cache;
    }

    public Orders getOrders() {
        return orders;
    }

    public void setOrders(Orders orders) {
        this.orders = orders;
    }

    public static class Nearby {
        private String strategy = "travel-time-pruned";
        private double pruneRadiusMiles = 60;
        private double maxDriveMinutes = 60;
        private long dcSyncMs = 300_000;

        public String getStrategy() {
            return strategy;
        }

        public void setStrategy(String strategy) {
            this.strategy = strategy;
        }

        public double getPruneRadiusMiles() {
            return pruneRadiusMiles;
        }

        public void setPruneRadiusMiles(double pruneRadiusMiles) {
            this.pruneRadiusMiles = pruneRadiusMiles;
        }

        public double getMaxDriveMinutes() {
            return maxDriveMinutes;
        }

        public void setMaxDriveMinutes(double maxDriveMinutes) {
            this.maxDriveMinutes = maxDriveMinutes;
        }

        public long getDcSyncMs() {
            return dcSyncMs;
        }

        public void setDcSyncMs(long dcSyncMs) {
            this.dcSyncMs = dcSyncMs;
        }
    }

    public static class TravelTime {
        private String provider = "mock";

        public String getProvider() {
            return provider;
        }

        public void setProvider(String provider) {
            this.provider = provider;
        }
    }

    public static class Inventory {
        private String readPath = "cache";

        public String getReadPath() {
            return readPath;
        }

        public void setReadPath(String readPath) {
            this.readPath = readPath;
        }
    }

    public static class Cache {
        private long ttlSeconds = 60;

        public long getTtlSeconds() {
            return ttlSeconds;
        }

        public void setTtlSeconds(long ttlSeconds) {
            this.ttlSeconds = ttlSeconds;
        }
    }

    public static class Orders {
        private String consistency = "postgres-serializable";
        private long lockTtlMs = 8000;
        private int serializationRetries = 3;

        public String getConsistency() {
            return consistency;
        }

        public void setConsistency(String consistency) {
            this.consistency = consistency;
        }

        public long getLockTtlMs() {
            return lockTtlMs;
        }

        public void setLockTtlMs(long lockTtlMs) {
            this.lockTtlMs = lockTtlMs;
        }

        public int getSerializationRetries() {
            return serializationRetries;
        }

        public void setSerializationRetries(int serializationRetries) {
            this.serializationRetries = serializationRetries;
        }
    }
}
