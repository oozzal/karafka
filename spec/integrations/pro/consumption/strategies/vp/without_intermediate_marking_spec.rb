# frozen_string_literal: true

# Karafka should mark correctly the final offset of collective group upon finish

setup_karafka(allow_errors: true) do |config|
  config.max_messages = 1000
  config.concurrency = 100
end

class Consumer < Karafka::BaseConsumer
  def consume
    messages.each { DT[0] << true }
  end
end

draw_routes do
  topic DT.topic do
    consumer Consumer
    max_messages 1000
    virtual_partitions(
      partitioner: ->(_) { rand(1000) }
    )
  end
end

produce_many(DT.topic, DT.uuids(1000))

start_karafka_and_wait_until do
  DT[0].size >= 1000
end

# All should be consumed.
# If anything with message marking would be off, it would return an offset value
assert !fetch_first_offset
