Fanout = require './fanout'
consts = require './consts'
db = require './db'
_ = require 'underscore'
require './util'

module.exports = class ControlFanout extends Fanout
  _fanout_name: -> 'control'

  cycle: (key, deps) ->
    msg = ['cycle', key, deps...].join consts.key_sep
    @publish msg

  quit: -> @publish 'quit'

  reset: -> @publish 'reset'

  resume: (key) -> @publish "resume#{consts.key_sep}#{key}"
