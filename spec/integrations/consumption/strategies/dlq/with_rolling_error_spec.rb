# frozen_string_literal: true

# Without the independent flag (default) Karafka will accumulate attempts on a batch in a rolling
# fashion when recoverable errors appear over and over again on a set of messages.

setup_karafka(allow_errors: %w[consumer.consume.error]) do |config|
  config.max_messages = 10
end

class Consumer < Karafka::BaseConsumer
  def consume
    # Remove flow edge cases and always require at least 3 messages for the sake of consistency
    if messages.size < 3
      seek(messages.first.offset)

      return
    end

    DT[:ticks] << true

    @runs ||= -1
    @runs += 1

    messages.each do |message|
      raise StandardError if @runs == message.offset

      mark_as_consumed(message)
    end
  end
end

class DlqConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      DT[:broken] << message.raw_payload.to_i
    end
  end
end

draw_routes do
  topic DT.topics[0] do
    consumer Consumer
    dead_letter_queue(topic: DT.topics[1], max_retries: 2)
  end

  topic DT.topics[1] do
    consumer DlqConsumer
  end
end

produce_many(DT.topic, (0..99).to_a.map(&:to_s))

start_karafka_and_wait_until do
  DT[:broken].size >= 3
end

# Consumer will accumulate the retries and apply them on later messages
assert_equal [2, 5, 8], DT[:broken]
