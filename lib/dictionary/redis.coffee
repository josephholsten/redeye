db = require '../db'
consts = require '../consts'
winston = require 'winston'

module.exports = class Redis
  constructor: (options) ->
    @db_index = options.db_index
    @_db = db @db_index

  db: ->
    @_db

  get: (args..., callback) ->
    key = args.join consts.arg_sep
    @_db.get key, (err, str) ->
      throw err if err
      callback JSON.parse(str)

  mget: (keys, callback) ->
    @_db.mget keys, callback

  mset: (keys...) ->
    @_db.mset.apply @_db, keys

  keys: (pattern, callback) ->
    @_db.keys pattern, callback

  set: (args..., value) ->
    key = args.join consts.arg_sep
    json = value?.toJSON?() ? value
    @_db.set key, JSON.stringify(json)

  clear: (callback) ->
    @_db.flushdb callback

  end: ->
    @_db.end()
