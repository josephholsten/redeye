amqp = require 'amqp'
winston = require 'winston'

module.exports = class AmqpFanout
  constructor: (options) ->
    @_fanout = ['redeye', options.db_index, @_fanout_name()].join '.'
    @_state = 'new'
    @_callbacks = []

  publish: (msg) ->
    @_when_ready =>
      winston.debug "Rabbit fanout: #{@_fanout} << ", msg
      @_exchange.publish '', msg

  listen: (callback) ->
    @_when_ready =>
      @_queue.subscribe (message) =>
        message = message.data.toString()
        winston.debug "Rabbit fanout: #{@_fanout} >> ", message
        callback message

  end: ->
    winston.debug "Rabbit fanout: #{@_fanout} :: DESTROY"
    @_state = 'closed'
    @_connection.destroySoon()

  _fanout_name: -> ''

  _when_ready: (callback) ->
    @_hold_callbacks callback, (handle_callbacks) =>
      @_connection = amqp.createConnection url: 'amqp://localhost'
      @_connection.once 'ready', =>
        @_connection.queue '', exclusive: true, (@_queue) =>
          @_connection.exchange @_fanout, type: 'fanout', (@_exchange) =>
            @_queue.bind @_fanout, ''
            handle_callbacks()

  _hold_callbacks: (callback, get_ready) ->
    if @_state == 'ready'
      callback()
    else if @_state == 'waiting'
      @_callbacks.push callback
    else
      @_callbacks.push callback
      @_state = 'waiting'
      get_ready =>
        @_state = 'ready'
        f() for f in @_callbacks
        @_callbacks = []
