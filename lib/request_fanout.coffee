Fanout = require './fanout'
consts = require './consts'
db = require './db'
_ = require 'underscore'
require './util'

module.exports = class RequestFanout extends Fanout
  _fanout_name: -> 'requests'

  listen: (callback) ->
    super (str) ->
      [source, keys...] = str.split consts.key_sep
      callback source, keys

  request_missing: (source, deps) ->
    request = [source, deps...].join consts.key_sep
    @publish request
