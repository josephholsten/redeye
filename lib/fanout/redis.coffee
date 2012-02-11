consts = require '../consts'
db = require '../db'
_ = require 'underscore'
require '../util'

module.exports = class RedisFanout
  constructor: (options) ->
    {db_index} = options
    @_db = db db_index
    @_channel = _(@_fanout_name()).namespace db_index

  publish: (msg) -> @_db.publish @_channel, msg

  listen: (callback) ->
    @_db.on 'message', (ch, msg) ->
      callback msg
    @_db.subscribe @_channel

  end: -> @_db.end()

  db: -> @_db

  _fanout_name: -> ''
