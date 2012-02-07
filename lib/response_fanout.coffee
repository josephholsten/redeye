RedisFanout = require './redis_fanout'

module.exports = class ResponseFanout extends RedisFanout
  _fanout_name: -> 'responses'
