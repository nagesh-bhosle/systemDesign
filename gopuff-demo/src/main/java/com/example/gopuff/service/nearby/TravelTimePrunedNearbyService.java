package com.example.gopuff.service.nearby;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.geo.GeoUtils;
import com.example.gopuff.service.catalog.DcCatalog;
import com.example.gopuff.service.travel.TravelTimeService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
@ConditionalOnProperty(name = "gopuff.nearby.strategy", havingValue = "travel-time-pruned", matchIfMissing = true)
public class TravelTimePrunedNearbyService implements NearbyService {

    private final DcCatalog catalog;
    private final TravelTimeService travelTime;
    private final GopuffProperties properties;

    public TravelTimePrunedNearbyService(DcCatalog catalog, TravelTimeService travelTime, GopuffProperties properties) {
        this.catalog = catalog;
        this.travelTime = travelTime;
        this.properties = properties;
    }

    @Override
    public List<NearbyDc> findNearby(double lat, double lon) {
        double maxMiles = properties.getNearby().getPruneRadiusMiles();
        double maxMinutes = properties.getNearby().getMaxDriveMinutes();
        List<NearbyDc> result = new ArrayList<>();
        for (DistributionCenter dc : catalog.all()) {
            double miles = GeoUtils.haversineMiles(lat, lon, dc.getLatitude(), dc.getLongitude());
            if (miles > maxMiles) {
                continue;
            }
            double minutes = travelTime.minutes(lat, lon, dc);
            if (minutes <= maxMinutes) {
                result.add(new NearbyDc(dc, miles, minutes));
            }
        }
        result.sort(Comparator.comparingDouble(NearbyDc::driveMinutes));
        return result;
    }
}
