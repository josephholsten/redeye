conn = require './connection'

module.exports = class RedisAdapter
  constructor: (options = {}) ->
    @redis = options.connection ? conn(options)
    @redis._uses ?= 0
    @redis._uses++
  connect: (callback) ->
    callback() if callback
  end: ->
    unless --@redis._uses
      @redis.end()
