require 'net/http'
require 'json'
require 'graphql/client'
require 'graphql/client/http'
require 'terminal-table'
require 'rainbow'
require 'time'
require_relative 'geocoding'
require_relative 'queries'
require_relative 'hsl'

KEY = ENV.fetch("HSL_API_KEY") do
  abort("Missing HSL API key! Set the 'HSL_API_KEY' variable in your environment.")
end

class Time
  def seconds_since_midnight
    self.hour * 3600 + self.min * 60 + self.sec
  end
end

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
  result = HSL::Client.query(Queries::GetStopsByName, variables: {name: name})
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

  result = HSL::Client.query(Queries::GetDeparturesAtStops, variables: {ids: ids})
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

  result = HSL::Client.query(Queries::GetRouteWithLabels, variables: {lon_start: start_location.lon,
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

Signal.trap("SIGINT") do
  puts
  puts "Exiting..."
  exit
end

main
