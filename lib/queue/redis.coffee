consts = require '../consts'
db = require '../db'
_ = require 'underscore'
require '../util'

module.exports = class RedisQueue
  constructor: (options) ->
    {db_index} = options
    @_db = db db_index

  del: -> @_db.del @_queue_name()

  rpush: (msg) -> @_db.rpush @_queue_name(), msg

  blpop: (callback) -> @_db.blpop @_queue_name(), 0, callback

  end: -> @_db.end()

  db: -> @_db

  _queue_name: -> ''

