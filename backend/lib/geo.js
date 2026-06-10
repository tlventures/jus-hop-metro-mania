'use strict';

const EARTH_RADIUS_M = 6_371_000;

/**
 * Haversine great-circle distance in metres between two lat/lng points.
 */
function haversineMeters(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a));
}

/**
 * Return the nearest station from an array and its distance in metres.
 * Each station must have numeric `latitude` and `longitude` fields.
 *
 * @param {number} lat
 * @param {number} lng
 * @param {Array<{id:string, latitude:number, longitude:number}>} stations
 * @returns {{ station: object, distanceM: number } | null}
 */
function nearestStation(lat, lng, stations) {
  let best = null;
  let bestDist = Infinity;
  for (const s of stations) {
    if (!Number.isFinite(s.latitude) || !Number.isFinite(s.longitude)) continue;
    const d = haversineMeters(lat, lng, s.latitude, s.longitude);
    if (d < bestDist) { bestDist = d; best = s; }
  }
  return best ? { station: best, distanceM: bestDist } : null;
}

module.exports = { haversineMeters, nearestStation };
