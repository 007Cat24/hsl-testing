require 'net/http'
require 'json'
require 'graphql/client'
require 'graphql/client/http'
require 'terminal-table'
require 'rainbow'

KEY = '709ec2d5df5242ceb1e2cdf936673e8c'

class Time
  def seconds_since_midnight
    self.hour * 3600 + self.min * 60 + self.sec
  end
end

module HSL
  HTTP = GraphQL::Client::HTTP.new("https://api.digitransit.fi/routing/v2/hsl/gtfs/v1") do
    def headers(context)
      { "digitransit-subscription-key": KEY }
    end
  end

  if File.file?("hsl_schema.json")
    print "Schema found. "
    Schema = GraphQL::Client.load_schema("hsl_schema.json")
  else
    print "Loading schema... "
    Schema = GraphQL::Client.load_schema(HTTP)
    GraphQL::Client.dump_schema(HSL::HTTP, "hsl_schema.json")
  end

  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
  puts "GraphQL client ready!"
end

def perform_digitransit_request(url)
  uri = URI(url)

  request = Net::HTTP::Get.new(uri)
  request['digitransit-subscription-key'] = KEY

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  JSON.parse(response.body)
end

def get_locations(lat, lon, size = 5, type = "address")
  base_url = "https://api.digitransit.fi/geocoding/v1/reverse?point.lat=#{lat}&point.lon=#{lon}&size=#{size}&layers=#{type}"

  response = perform_digitransit_request(base_url)
  features = response["features"]

  puts "Showing #{features.length} locations:"
  features.each_with_index do |feature, index|
    feature = feature["properties"]
    puts "#{index + 1}. #{feature["layer"].capitalize!}: #{feature["label"]}"
  end
end

def get_addresses_by_text(text, size = 5)
  base_url = "https://api.digitransit.fi/geocoding/v1/search?text=#{text}&size=#{size}"

  puts "Searching for #{text}"
  response = perform_digitransit_request(base_url)
  features = response["features"]

  puts "Showing #{features.length} locations:"
  features.each_with_index do |feature, index|
    feature = feature["properties"]
    puts "#{index + 1}. #{feature["layer"].capitalize!}: #{feature["label"]} - confidence: #{feature["confidence"]}"
  end
end

#get_locations("60.1871664", "24.833366", 10, "address")
#get_addresses_by_text("Aalto University", 3)

FirstQuery = HSL::Client.parse <<-'GRAPHQL'
{
  alerts {
    alertDescriptionText
  }
}
GRAPHQL

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
  stations(name: "Tapiola") {
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
          mode
        }
      }
      stop {
        platformCode
      }
      departureDelay
      scheduledDeparture
      realtimeDeparture
      serviceDay
      realtime
      }
    }
}
GRAPHQL

while true
  rows = []

  result = HSL::Client.query(KamppiDepartures).data.stations
  system "clear"
  puts "Updated at #{Time.now.utc.strftime("%I:%M:%S %p")}"

  result.each do |result|
    title = "Next departures at #{result.name} (#{result.vehicle_mode.downcase} #{result.location_type.downcase}):"
    result.stoptimes_without_patterns.each do |stoptime|
      headsign, route = stoptime.headsign, stoptime.trip.route.short_name
      departure_time = Time.at(stoptime.realtime_departure.to_i).utc.strftime("%I:%M %p")
      mode = stoptime.trip.route.mode

      line = stoptime.trip.route.short_name

      if mode == "BUS"
        line = Rainbow(line).bg(:blue).white
      elsif mode == "SUBWAY"
        line = Rainbow(line).bg(184, 73, 31).white.bright
      end

      pickup_type = stoptime.pickup_type
      realtime = stoptime.realtime
      platform = stoptime.stop.platform_code

      delay = stoptime.departure_delay
      scheduled_time = Time.at(stoptime.scheduled_departure).utc.strftime("%I:%M %p")
      if delay > 5
        delayString = " delayed by #{delay} s"
        delayMinutes = Rainbow("(+#{delay / 60})").red
        departure_string = "#{Rainbow(scheduled_time).red} #{delayMinutes}"
      else
        delayString = "-"
        departure_string = Rainbow(departure_time).green
      end

      if realtime == false
        departure_string = Rainbow.uncolor(departure_time)
      end

      time_in_helsinki = Time.now.getlocal('+03:00')
      departure_unix = Time.at(stoptime.service_day + stoptime.realtime_departure.to_i).getlocal("+02:00")
      time_until_departure = (departure_unix - time_in_helsinki).to_i

      if time_until_departure < 60
        departure_string = Rainbow(departure_string).blink
        line = Rainbow(line).blink
      end

      rows << ["#{line}","#{headsign}", "#{departure_string}", "#{delayString}", "#{platform}"] unless pickup_type == "NONE"
    end

    table = Terminal::Table.new :title => title, :headings => ['Line', 'Destination', 'Departure', 'Delay', 'Platform'], :rows => rows
    puts table
  end

  sleep(5)
end
