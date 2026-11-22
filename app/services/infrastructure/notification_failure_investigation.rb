# frozen_string_literal: true

module Infrastructure
  class NotificationFailureInvestigation
    JOB_CLASSES = %w[
      Infrastructure::NotificationDeliveryJob
      Infrastructure::NotificationReconciliationJob
    ].freeze
    PER_PAGE = 25

    def scope
      SolidQueue::FailedExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: JOB_CLASSES })
    end

    def list(job_class: nil, period: nil, page: 1)
      relation = scope
      relation = relation.where(solid_queue_jobs: { class_name: job_class }) if JOB_CLASSES.include?(job_class)
      relation = relation.where('solid_queue_failed_executions.created_at >= ?', 24.hours.ago) if period == '24h'
      relation = relation.where('solid_queue_failed_executions.created_at >= ?', 7.days.ago) if period == '7d'
      total = relation.count
      pages = [(total.to_f / PER_PAGE).ceil, 1].max
      current_page = [[page.to_i, 1].max, pages].min
      failures = relation.includes(:job)
        .order(created_at: :desc, id: :desc)
        .offset((current_page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      { failures: failures.map { |failure| summarize(failure) }, total: total,
        page: current_page, total_pages: pages }
    end

    def find(id)
      failure = scope.includes(:job).find(id)
      summarize(failure).merge(
        created_at: failure.job.created_at,
        scheduled_at: failure.job.scheduled_at,
        finished_at: failure.job.finished_at,
        active_job_id: failure.job.active_job_id,
        notification_id: notification_id(failure.job)
      )
    end

    def summarize(failure)
      error = failure.error.to_s
      {
        id: failure.id, job_id: failure.job_id,
        job_class: failure.job.class_name, queue: failure.job.queue_name,
        failed_at: failure.created_at, category: classify(error),
        # Never expose raw exception messages/backtraces: they can contain tokens,
        # recipient addresses, request bodies, and other sensitive data.
        summary: 'Execution failed. Review restricted server logs for further details.'
      }
    end

    private

    def classify(error)
      case error
      when /timeout|timed out|deadline exceeded/i then 'Timeout'
      when /unauthorized|forbidden|authentication|invalid.client|401|403/i then 'Authentication / Authorisation'
      when /connection refused|socket|dns|network|host unreachable/i then 'Network'
      when /PG::|ActiveRecord::|database|deadlock/i then 'Database'
      else 'Application / Other'
      end
    end

    def notification_id(job)
      return nil unless job.class_name == JOB_CLASSES.first

      # Active Job serializes positional arguments under the `arguments` key.
      # Accept only a positive integer; do not deserialize or execute job payloads.
      value = job.arguments.is_a?(Hash) ? job.arguments['arguments']&.first : nil
      return nil unless value.is_a?(Integer) && value.positive?

      value
    end
  end
end
