# The only async queue in redis is a fanout queue
RedisFanout = require '../fanout/redis'
module.exports = class Redis extends RedisFanout
  _fanout_name: ->
    @_queue_name()
