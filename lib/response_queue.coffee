AsyncQueue = require './async_queue'

module.exports = class ResponseQueue extends AsyncQueue
  _queue_name: -> 'responses'
