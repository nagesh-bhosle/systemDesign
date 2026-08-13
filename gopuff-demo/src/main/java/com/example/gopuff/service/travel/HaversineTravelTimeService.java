package com.example.gopuff.service.travel;

import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.geo.GeoUtils;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(name = "gopuff.travel-time.provider", havingValue = "haversine")
public class HaversineTravelTimeService implements TravelTimeService {

    static final double ASSUMED_MPH = 30.0;

    @Override
    public double minutes(double fromLat, double fromLon, DistributionCenter dc) {
        double miles = GeoUtils.haversineMiles(fromLat, fromLon, dc.getLatitude(), dc.getLongitude());
        return miles / ASSUMED_MPH * 60.0;
    }
}
