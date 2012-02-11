Fanout = require './fanout'

module.exports = class ResponseFanout extends Fanout
  _fanout_name: -> 'responses'
