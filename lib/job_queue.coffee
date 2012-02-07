RedisQueue = require './redis_queue'

module.exports = class JobQueue extends RedisQueue
  _queue_name: -> 'jobs'
  push_job: (req) -> @rpush req
  pop_job: (callback) -> @blpop callback
  delete_jobs: -> @del()

  fatal: (message) -> @_db.set 'fatal', message # this seems out of place
