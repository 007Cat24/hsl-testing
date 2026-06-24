# frozen_string_literal: true

module HSL
  KEY = ENV.fetch("HSL_API_KEY") do
    abort("Missing HSL API key! Set the 'HSL_API_KEY' variable in your environment.")
  end

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
