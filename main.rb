require 'net/http'
require 'json'
require 'graphql/client'
require 'graphql/client/http'
require 'terminal-table'
require 'rainbow'
require 'time'

KEY = ENV.fetch("HSL_API_KEY") do
  abort("Missing HSL API key! Set the 'HSL_API_KEY' variable in your environment.")
end

module Geocoding
  module_function
  def perform_digitransit_request(url)
    uri = URI(url)

    request = Net::HTTP::Get.new(uri)
    request['digitransit-subscription-key'] = KEY

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    json_response = JSON.parse(response.body)
    unless response in Net::HTTPOK
      puts Rainbow("Error encountered!").red
      puts json_response["message"]
      exit
    end
    json_response
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

  def get_address_coordinates(text, size = 5)
    # Handle umlauts
    text = URI.encode_uri_component(text)
    base_url = "https://api.digitransit.fi/geocoding/v1/search?text=#{text}&size=#{size}"
    response = perform_digitransit_request(base_url)
    features = response["features"]
    addresses_with_coordinates = []

    features.each do |feature|
      if feature["geometry"]["type"] == "Point"
        lon, lat = feature["geometry"]["coordinates"]
      end

      properties = feature["properties"]
      label = properties["label"]
      layer = properties["layer"].capitalize!
      confidence = properties["confidence"]

      addresses_with_coordinates << {:label => label, :lat => lat, :lon => lon,
                                     :layer => layer, :confidence => confidence}
    end

    addresses_with_coordinates
  end
end

class Time
  def seconds_since_midnight
    self.hour * 3600 + self.min * 60 + self.sec
  end
end

module HSL
  HTTP = GraphQL::Client::HTTP.new("https://api.digitransit.fi/routing/v2/hsl/gtfs/v1") do
    def headers(context)
      { "digitransit-subscription-key": KEY,
        "Accept-Language": "fi"}
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

#Geocoding::get_locations("60.1871664", "24.833366", 10, "address")
#puts Geocoding::get_address_coordinates("Aalto University", 5).inspect

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

def show_departures_at_stations
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
        line = Rainbow(stoptime.trip.route.short_name).bg(:blue).white
        pickup_type = stoptime.pickup_type
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

        time_in_helsinki = Time.now.getlocal('+03:00')
        departure_unix = Time.at(stoptime.service_day + stoptime.realtime_departure.to_i).getlocal("+02:00")
        time_until_departure = (departure_unix - time_in_helsinki).to_i

        if time_until_departure < 60
          departure_string = Rainbow(departure_string).blink
          line = Rainbow(line).blink
        end

        rows << ["#{line}","#{departure_string}", "#{delayString}", "#{route} to #{headsign}", "#{platform}"] unless pickup_type == "NONE"
      end

      table = Terminal::Table.new :title => title, :headings => ['Line', 'Departure', 'Delay', 'Route', 'Platform'], :rows => rows
      puts table
    end

    sleep(5)
  end
end

def get_address_from_user
  while true
    print "Enter an address to look up: "
    input = gets.chomp
    exit if input == "q"
    potential_addresses = Geocoding::get_address_coordinates(input, 5)
    potential_addresses.each_with_index do |address, index|
      puts "#{index + 1}. #{address[:label]} - #{address[:layer]}"
    end

    while true
      if potential_addresses.empty?
        puts "No results..."
        break
      end
      puts "Enter the number of the address or 'R' to run the search again:"
      input = gets.chomp
        if input == "R"
          break
        elsif input.to_i.between?(1, potential_addresses.length)
          return potential_addresses[input.to_i - 1]
        else
      end
    end
  end
end

def find_stops_by_name(name)
  result = HSL::Client.query(GetStopsByName, variables: {name: name})
  result.data.stops
end

def get_stop_ids(stops)
  stops.map{|stop| stop.gtfs_id}
end

def display_stops(stops)
  stops.each_with_index do |it, index|
    puts "#{index + 1}. #{it.name}, #{it.desc}, #{it.vehicle_mode}"
    puts "Lines at stop: #{it.patterns.map{|p| p.route.short_name}.join(", ")}"
    puts "#{it.gtfs_id}"
  end
end

class Departure
  attr_reader :stop_name, :short_name, :headsign, :realtime,
              :departure_time_unix, :departure_delay, :line_string,
              :desc

  def initialize(stop_name, short_name, headsign, realtime, departure_time_unix, departure_delay, vehicle_mode, desc)
    @stop_name = stop_name
    @short_name = short_name
    @vehicle_mode = vehicle_mode
    @line_string = create_line_string
    @headsign = headsign
    @realtime = realtime
    @departure_time_unix = departure_time_unix
    @departure_delay = departure_delay
    @desc = desc
  end

  def create_line_string
    @line_string =
      case @vehicle_mode
      when "BUS" then Rainbow(@short_name).bg(:blue).snow.bright
      when "SUBWAY" then Rainbow(@short_name).bg(:darkorange).snow
      when "TRAM" then Rainbow(@short_name).bg(:darkgreen).snow
      when "RAIL" then Rainbow(@short_name).bg(:darkviolet).snow
      when "FERRY" then Rainbow(@short_name).bg(:darkred).snow
      else Rainbow(@short_name).bg(:black).snow
      end
  end

  def departure_time
    Time.at(@departure_time_unix).getlocal("+03:00")
  end

  def seconds_until_departure
    time_in_helsinki = Time.now.getlocal('+03:00')
    (departure_time - time_in_helsinki).to_i
  end

  def delayed?
    departure_delay > 60
  end

  def departure_string
    departure_string = departure_time.utc.getlocal("+03:00").strftime("%I:%M %p")

    if realtime
      departure_string = Rainbow(departure_string).green
      if delayed?
        departure_string = "#{departure_time.utc.getlocal("+03:00").strftime("%I:%M %p")} (+#{departure_delay / 60})"
        departure_string = Rainbow(departure_string).red
      end
    end

    departure_string = Rainbow(departure_string).blink if seconds_until_departure < 59

    departure_string
  end
end

# Returns departures
def departures_at_stops(ids)

  result = HSL::Client.query(GetDeparturesAtStops, variables: {ids: ids})
  result = result.data.stops
  departures = []
  result.each do |stop|
    stop_name = stop.name
    desc = stop.desc
    stop.stoptimes_without_patterns.each do |stoptime|
      headsign = stoptime.headsign
      short_name = stoptime.trip.route.short_name
      realtime = stoptime.realtime
      vehicle_mode = stop.vehicle_mode

      departure_time_unix = stoptime.service_day
      departure_time_unix += realtime ? stoptime.realtime_departure : stoptime.scheduled_departure

      departure_delay = stoptime.departure_delay

      departures << Departure.new(stop_name, short_name, headsign, realtime, departure_time_unix, departure_delay, vehicle_mode, desc)

    end
  end
  departures
end

def display_departures(departures)
  rows = []

  departures.each do |dep|
    delay = dep.departure_delay
    unless dep.realtime
      delay = "-"
    end
    rows << [dep.line_string, dep.headsign, dep.departure_string, delay, dep.stop_name, dep.desc]
  end

  title = "Departures"
  table = Terminal::Table.new :title => title, :headings => ['Line', 'Headsign', 'Departure', 'Delay (s)', 'Stop', 'Location'], :rows => rows
  puts table

  puts "\n#{"Legend (Line):".ljust(20)} #{Rainbow("BUS").bg(:blue).snow.bright} #{Rainbow("METRO").bg(:darkorange).snow} #{Rainbow("TRAM").bg(:darkgreen).snow} #{Rainbow("TRAIN").bg(:darkviolet).snow} #{Rainbow("FERRY").bg(:darkred).snow}"
  puts "#{"Legend (Departure):".ljust(20)} No real-time data #{Rainbow("On time").green} #{Rainbow("Delayed (by X minutes)").red}"
  puts "NB! For #{Rainbow("delayed departures").red} the displayed time is the actual departure time"
end

def loop_departure_display(stop_ids)
  loop do
    departures = departures_at_stops(stop_ids)
    system "clear"
    puts "Updated at #{Time.now.utc.strftime("%I:%M:%S %p")}"
    display_departures(departures)
    sleep(5)
  end
end

class Location
  attr_reader :lat, :lon, :label
  def initialize(lat, lon, label)
    @lat = lat.to_f
    @lon = lon.to_f
    @label = label
  end
end

def format_time(time)
  time.strftime("%H:%M")
end

def seconds_to_str(seconds)
  seconds = seconds.to_i
  hours = seconds / 3600
  minutes = (seconds % 3600) / 60

  time = []
  time << "#{hours}h" if hours.positive?
  time << "#{minutes} min" if minutes.positive?
  time.join(" ")
end

def plan_connection()
  puts Rainbow("Start ('q' to quit):").bold
  start_address = get_address_from_user
  start_location = Location.new(start_address[:lat], start_address[:lon], start_address[:label])
  system "clear"
  puts Rainbow("Start: #{start_location.label}").bold
  puts Rainbow("Destination:").bold
  end_address = get_address_from_user
  end_location = Location.new(end_address[:lat], end_address[:lon], end_address[:label])

  system "clear"
  puts Rainbow("Start: #{start_location.label}").bold
  puts Rainbow("Destination: #{end_location.label}").bold

  result = HSL::Client.query(GetRouteWithLabels, variables: {lon_start: start_location.lon,
                                                             lat_start: start_location.lat,
                                                             label_start: start_location.label,
                                                             lon_end: end_location.lon,
                                                             lat_end: end_location.lat,
                                                             label_end: end_location.label})

  edges = result.data.plan_connection.edges

  if edges == []
    puts Rainbow("No routes available :(").bright
    exit!
  else
    puts
  end

  edges.each_with_index do |edge, index|
    route = edge.node
    start_time = Time.parse(route.start)
    end_time = Time.parse(route.end)
    duration = end_time - start_time
    puts Rainbow("Option #{index + 1}:  #{format_time(start_time)} - #{format_time(end_time)} (duration #{seconds_to_str(duration)}):").underline

    route.legs.each do |leg|
      mode = leg.mode
      start_time = Time.parse(leg.start.scheduled_time)
      end_time = Time.parse(leg.end.scheduled_time)

      verb = {"WALK" => "Walk from",
              "BUS" => "Take the bus from",
              "SUBWAY" => "Take the subway from",
              "TRAM" => "Take the tram from",
              "RAIL" => "Take the train from",
              "FERRY" => "Take the ferry from"}

      print Rainbow("#{seconds_to_str(leg.duration)} ".ljust(11)).green.bright
      puts "#{verb[mode]} #{Rainbow(leg.from.name).bright} to #{Rainbow(leg.to.name).bright}"

      unless mode == "WALK"
        line = leg.trip.route_short_name
        headsign = leg.headsign
        puts "\t\t     ↳ #{Rainbow(line).bright} #{headsign}"
        puts "\t\t       Departs at #{format_time(start_time)} (-> #{format_time(end_time)})"
      end
      puts
    end
    puts
  end
end

def main
  system "clear"
  print "Enter '1' to plan a route or '2' to display the departures for a stop: "
  choice = gets.chomp
  if choice == "1"
    loop {plan_connection}
  elsif choice == "2"
    system "clear"
    puts Rainbow("Departure display").bright
    while true
      print "Please enter the name of the stop: "
      input = gets.chomp
      stops = find_stops_by_name(input)
      stop_names = []
      puts Rainbow("\nResults:").bright
      stops.each do |stop|
        stop_names << stop.name
      end
      if stop_names.empty?
        puts "No results :("
        next
      end
      puts stop_names.uniq
      print "\nDoes this sound right? (yes/no): "
      choice = gets.chomp
      unless choice == "no"
        loop_departure_display(get_stop_ids(stops))
      end
    end
  else
      "Please only enter '1' or '2'"
  end
end

main
