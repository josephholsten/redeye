consts = require '../consts'
db = require '../db'
_ = require 'underscore'
require '../util'
winston = require 'winston'

module.exports = class RedisQueue
  constructor: (options) ->
    {db_index} = options
    @_db = db db_index

  clear: ->
    winston.debug "Redis queue: #{@_queue_name()} :: CLEAR"
    @_db.del @_queue_name()

  push: (msg) ->
    winston.debug "Redis queue: #{@_queue_name()} <<", message: msg
    @_db.rpush @_queue_name(), msg

  pop: (callback) ->
    queue = @_queue_name()
    @_db.blpop queue, 0, (err, [key, message]) =>
      winston.debug "Redis queue: #{queue} >>", message: message
      callback err, [key, message]

  end: ->
    winston.debug "Redis queue: #{@_queue_name()} :: DESTROY"
    @_db.end()

  db: -> @_db

  _queue_name: -> ''

