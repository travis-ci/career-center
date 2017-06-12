# frozen_string_literal: true

require 'job_board'

require 'l2met-log'

module JobBoard
  class JobQueueReconciler
    include L2met::Log

    def initialize(redis: nil)
      @redis = redis || JobBoard.redis
    end

    attr_reader :redis

    def reconcile!
      log msg: 'starting reconciliation process'
      start_time = Time.now
      stats = { sites: {} }

      redis.smembers('sites').map(&:to_sym).each do |site|
        next if site.to_s.empty?

        stats[:sites][site] = {
          workers: {},
          queues: {}
        }

        log msg: 'reconciling', site: site
        reclaimed, claimed = reconcile_site!(site: site)

        log msg: 'reclaimed jobs', site: site, n: reclaimed
        log msg: 'setting worker claimed jobs', site: site
        stats[:sites][site][:reclaimed] = reclaimed
        stats[:sites][site][:workers].merge!(claimed)

        log msg: 'fetching queue stats', site: site
        stats[:sites][site][:queues].merge!(measure(site))
      end

      log msg: 'finished with reconciliation process'
      stats.merge(time: "#{Time.now - start_time}s")
    end

    private def reconcile_site!(site: '')
      reclaimed = 0
      claimed = {}

      redis.smembers("workers:#{site}").each do |worker|
        worker = worker.to_s.strip
        next if worker.empty?

        if worker_is_current?(site: site, worker: worker)
          claimed[worker] = {
            claimed: redis.llen("worker:#{site}:#{worker}")
          }
        else
          reclaimed += reclaim_jobs_from_worker(site: site, worker: worker)
          claimed[worker] = { claimed: 0 }
        end
      end

      [reclaimed, claimed]
    end

    private def worker_is_current?(site: '', worker: '')
      redis.exists("worker:#{site}:#{worker}")
    end

    private def reclaim_jobs_from_worker(site: '', worker: '')
      reclaimed = 0

      redis.smembers("queues:#{site}").each do |queue_name|
        reclaimed += reclaim!(
          worker: worker, site: site, queue_name: queue_name
        )
      end

      reclaimed
    end

    private def reclaim!(worker: '', site: '', queue_name: '')
      reclaimed = 0
      return reclaimed if worker.empty? || site.empty? || queue_name.empty?

      claims = redis.hgetall("queue:#{site}:#{queue_name}:claims")
      claims.each do |job_id, claimer|
        next unless worker == claimer
        reclaim_job(
          worker: worker, job_id: job_id, site: site, queue_name: queue_name
        )
        reclaimed += 1
      end

      reclaimed
    end

    private def measure(site)
      measured = {}

      redis.smembers("queues:#{site}").each do |queue_name|
        resp = redis.multi do |conn|
          conn.llen("queue:#{site}:#{queue_name}")
          conn.hlen("queue:#{site}:#{queue_name}:claims")
        end

        measured[queue_name] = {
          queued: resp.fetch(0),
          claimed: resp.fetch(1)
        }
      end

      measured
    end

    private def reclaim_job(worker: '', job_id: '', site: '', queue_name: '')
      redis.multi do |conn|
        conn.srem("worker:#{site}:#{worker}:idx", job_id)
        conn.lrem("worker:#{site}:#{worker}", 1, job_id)
        conn.lpush("queue:#{site}:#{queue_name}", job_id)
        conn.hdel("queue:#{site}:#{queue_name}:claims", job_id)
        conn.hdel("queue:#{site}:#{queue_name}:claims:timestamps", job_id)
      end
    end
  end
end
