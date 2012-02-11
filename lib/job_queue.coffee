Queue = require './queue'

module.exports = class JobQueue extends Queue
  _queue_name: -> 'jobs'

  fatal: (message) -> @_db.set 'fatal', message # this seems out of place
