AsyncQueue = require './async_queue'
consts = require './consts'

module.exports = class RequestQueue extends AsyncQueue
  _queue_name: -> 'requests'

  listen: (callback) ->
    super (str) ->
      [source, keys...] = str.split consts.key_sep
      callback source, keys

  request_missing: (source, deps) ->
    request = [source, deps...].join consts.key_sep
    @publish request
