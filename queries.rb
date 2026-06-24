# frozen_string_literal: true
require_relative 'hsl'
module Queries
  # Station IDs:
  # Aalto metro: HSL:2000102
  # Central station: HSL:1000201

  AaltoMetroDepartures = HSL::Client.parse <<-'GRAPHQL'
{
  station(id: "HSL:2000102") {
    name(language: "en")
    gtfsId
    locationType
    vehicleMode
    stoptimesWithoutPatterns(numberOfDepartures: 8) {
      headsign
      trip {
        route {
          shortName
        }
      }
      departureDelay
      scheduledDeparture
      realtimeDeparture
      serviceDay
      }
    }
}
  GRAPHQL

  CentralTramDepartures = HSL::Client.parse <<-'GRAPHQL'
{
  station(id: "HSL:1000001") {
    name(language: "en")
    gtfsId
    locationType
    vehicleMode
    stoptimesWithoutPatterns(numberOfDepartures: 10) {
      headsign
      trip {
        route {
          shortName
        }
      }
      departureDelay
      scheduledDeparture
      realtimeDeparture
      serviceDay
      }
    }
}
  GRAPHQL

  KamppiDepartures = HSL::Client.parse <<-'GRAPHQL'
{
  stations(name: "aalto-yliopisto") {
name(language: "en")
    gtfsId
    locationType
    vehicleMode
    stoptimesWithoutPatterns(numberOfDepartures: 10) {
      headsign
      pickupType  
      trip {
        route {
          shortName
        }
      }
      stop {
        platformCode
      }
      departureDelay
      scheduledDeparture
      realtimeDeparture
      serviceDay
      }
    }
}
  GRAPHQL

  GetStopsByName = HSL::Client.parse <<-'GRAPHQL'
query ($name: String) {
  stops(name: $name) {
    gtfsId
    desc
    name
    code
    lat
    lon
    vehicleMode
    patterns {
      code
      directionId
      headsign
      route {
        gtfsId
        shortName
        longName
        mode
      }
    }
  }
}
  GRAPHQL

  GetDeparturesAtStops = HSL::Client.parse <<-'GRAPHQL'
query ($ids: [String]){
  stops(ids: $ids) {
    name
    desc
    vehicleMode
    stoptimesWithoutPatterns(omitNonPickups: true) {
      scheduledArrival
      realtimeArrival
      arrivalDelay
      scheduledDeparture
      realtimeDeparture
      departureDelay
      realtime
      realtimeState
      serviceDay
      headsign
      trip {
        route {
          shortName
        }
      }
    }
  }  
}
  GRAPHQL

  GetRouteWithLabels = HSL::Client.parse <<-'GRAPHQL'
query ($lat_start: CoordinateValue!, $lon_start: CoordinateValue!, $label_start: String,
$lat_end: CoordinateValue!, $lon_end: CoordinateValue!, $label_end: String ){
  planConnection(
    origin: {location: {coordinate: {latitude: $lat_start, longitude: $lon_start}}, label: $label_start}
    destination: {location: {coordinate: {latitude: $lat_end, longitude: $lon_end}}, label: $label_end}
    first: 3
  ) {
    pageInfo {
      endCursor
    }
    edges {
      node {
        start
        end
        legs {
          from {
            name
          }
          to {
            name
          }
          start {
            scheduledTime
          }
          end {
            scheduledTime
          }
          mode
          headsign
          trip {
            routeShortName
          }
          duration
          realtimeState
        }
        emissionsPerPerson {
          co2
        }
      }
    }
  }
}
  GRAPHQL
end
