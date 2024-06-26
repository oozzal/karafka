# frozen_string_literal: true

# When working with transactions if all success and the strategy is current, last should be picked

setup_karafka do |config|
  config.kafka[:'transactional.id'] = SecureRandom.uuid
  config.concurrency = 10
end

class Consumer < Karafka::BaseConsumer
  def consume
    sleep(rand / 10)

    DT[:done] << object_id

    transaction do
      messages.each do |message|
        mark_as_consumed!(message, message.offset.to_s)
      end
    end
  end

  def shutdown
    DT[:metadata] << offset_metadata(cache: false)
  end
end

DT[:iterator] = (0..9).cycle

draw_routes do
  topic DT.topic do
    consumer Consumer
    filter VpStabilizer
    offset_metadata(cache: false)
    virtual_partitions(
      partitioner: ->(_msg) { DT[:iterator].next },
      offset_metadata_strategy: :exact
    )
    manual_offset_management true
  end
end

produce_many(DT.topic, DT.uuids(100))

start_karafka_and_wait_until do
  DT[:done].uniq.size >= 10
end

assert_equal fetch_first_offset, false
assert_equal DT[:metadata].last, '99'
