# frozen_string_literal: true

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
