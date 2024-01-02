# frozen_string_literal: true

# When we use exact matching strategy for virtual partitions, metadata should match the most recent
# consecutive offset and not the latest marking offset kept in-memory
# In case materialized offset is behind the one that we marked due to the VPs distribution, "exact"
# value will be assigned from the highest offset of a virtual partition

setup_karafka do |config|
  config.max_messages = 100
  config.concurrency = 10
end

class Consumer < Karafka::BaseConsumer
  def consume
    sleep(messages.first.offset / 10.to_f)

    if messages.first.offset.zero?
      mark_as_consumed!(messages.to_a[1], messages.to_a[1].offset.to_s)
    else
      mark_as_consumed!(messages.first, messages.first.offset.to_s)
    end

    DT[:groups] << messages.map(&:offset)
  end

  def shutdown
    DT[:metadata] << offset_metadata(cache: false)
  end
end

# Make sure we get 100 messages just not to deal with edge cases
class DelayThrottler < Karafka::Pro::Processing::Filters::Base
  def apply!(messages)
    @applied = false
    @cursor = nil

    return if messages.size >= 100

    @cursor = messages.first
    messages.clear
    @applied = true
  end

  def applied?
    @applied
  end

  def action
    applied? ? :seek : :skip
  end
end

DT[:iterator] = (0..9).cycle

draw_routes do
  topic DT.topic do
    consumer Consumer
    manual_offset_management true
    filter(->(*) { DelayThrottler.new })
    virtual_partitions(
      partitioner: ->(_msg) { DT[:iterator].next },
      offset_metadata_strategy: :exact
    )
  end
end

produce_many(DT.topic, DT.uuids(100))

start_karafka_and_wait_until do
  DT[:groups].size >= 10
end

assert_equal %w[10], DT[:metadata].uniq