RedisFanout = require './redis_fanout'
consts = require './consts'
db = require './db'
_ = require 'underscore'
require './util'

module.exports = class ControlFanout extends RedisFanout
  _fanout_name: -> 'control'

  listen: (callback) ->
    super (ch, str) ->
      callback str

  cycle: (key, deps) ->
    msg = ['cycle', key, deps...].join consts.key_sep
    @publish msg

  quit: -> @publish 'quit'

  reset: -> @publish 'reset'

  resume: (key) -> @publish "resume#{consts.key_sep}#{key}"
