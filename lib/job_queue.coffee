Queue = require './queue'

module.exports = class JobQueue extends Queue
  _queue_name: -> 'jobs'
