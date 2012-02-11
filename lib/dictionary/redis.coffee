db = require '../db'

module.exports = class Redis
  constructor: (options) ->
    {db_index} = options
    @_db = db db_index

  end: ->
    @_db.end()

  db: ->
    @_db

  get: (key) ->
    @_db.get key

  mget: (keys, callback) ->
    @_db.mget keys, callback

  keys: (pattern, callback) ->
    @_db.keys pattern, callback

  set: (key, value) ->
    @_db.set key, value
