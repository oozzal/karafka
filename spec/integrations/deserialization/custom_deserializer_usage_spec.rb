# frozen_string_literal: true

# Karafka should be able to use custom deserializers on messages after they are declared

setup_karafka

messages = Array.new(100) { |i| "message#{i}" }

class Consumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      DT[message.metadata.partition] << message.payload
    end
  end
end

class CustomDeserializer
  def call(message)
    message.raw_payload[0..6]
  end
end

draw_routes do
  topic DT.topic do
    consumer Consumer
    deserializer CustomDeserializer.new
  end
end

produce_many(DT.topic, messages)

start_karafka_and_wait_until do
  DT[0].size >= 100
end

assert_equal %w[message], DT[0].uniq
assert_equal 100, DT[0].size
