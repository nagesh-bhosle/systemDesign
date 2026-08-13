package com.example.gopuff.service.travel;

import com.example.gopuff.entity.DistributionCenter;

public interface TravelTimeService {
    double minutes(double fromLat, double fromLon, DistributionCenter dc);
}
