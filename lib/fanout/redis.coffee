consts = require '../consts'
db = require '../db'
_ = require 'underscore'
require '../util'
winston = require 'winston'

module.exports = class RedisFanout
  constructor: (options) ->
    {db_index} = options
    @_db = db db_index
    @_channel = _(@_fanout_name()).namespace db_index

  publish: (msg) ->
    winston.debug "Redis queue: #{@_channel} <<", message: msg
    @_db.publish @_channel, msg

  listen: (callback) ->
    @_db.on 'message', (ch, msg) =>
      winston.debug "Redis queue: #{@_channel} >>", message: msg
      callback msg
    @_db.subscribe @_channel

  end: ->
    winston.debug "Redis queue: #{@_channel} :: DESTROY"
    @_db.end()

  db: -> @_db

  _fanout_name: -> ''
