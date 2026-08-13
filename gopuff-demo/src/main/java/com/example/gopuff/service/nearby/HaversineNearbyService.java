package com.example.gopuff.service.nearby;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.geo.GeoUtils;
import com.example.gopuff.service.catalog.DcCatalog;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
@ConditionalOnProperty(name = "gopuff.nearby.strategy", havingValue = "haversine")
public class HaversineNearbyService implements NearbyService {

    private final DcCatalog catalog;
    private final GopuffProperties properties;

    public HaversineNearbyService(DcCatalog catalog, GopuffProperties properties) {
        this.catalog = catalog;
        this.properties = properties;
    }

    @Override
    public List<NearbyDc> findNearby(double lat, double lon) {
        double maxMiles = properties.getNearby().getPruneRadiusMiles();
        List<NearbyDc> result = new ArrayList<>();
        for (DistributionCenter dc : catalog.all()) {
            double miles = GeoUtils.haversineMiles(lat, lon, dc.getLatitude(), dc.getLongitude());
            if (miles <= maxMiles) {
                result.add(new NearbyDc(dc, miles, miles / 30.0 * 60.0));
            }
        }
        result.sort(Comparator.comparingDouble(NearbyDc::miles));
        return result;
    }
}
