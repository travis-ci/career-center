# frozen_string_literal: true
module JobBoard
  module Services
    class CreateJob
      def self.run(params: {})
        new(params: params).run
      end

      attr_reader :params

      def initialize(params: {})
        @params = params
      end

      def run
        job_id = params.fetch('id')
        queue = assign_queue(params)

        JobBoard::Models.db.transaction do
          JobBoard::Models.redis.multi do |conn|
            conn.sadd('queues', queue)
            conn.rpush(
              "queue:#{queue}",
              job_id
            )
          end

          JobBoard::Models::Job.create(
            job_id: job_id,
            queue: queue,
            data: Sequel.pg_json(params)
          )
        end
      end

      def assign_queue(_job)
        # TODO: implementation
        'gce'
      end
    end
  end
end