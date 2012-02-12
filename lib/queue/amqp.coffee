amqp = require 'amqp'
winston = require 'winston'

module.exports = class AmqpQueue
  constructor: (options) ->
    @_routing_key = ['redeye', options.db_index, @_queue_name()].join '.'
    @_state = 'new'
    @_callbacks = []

  push: (message) ->
    @_when_ready =>
      winston.debug "Rabbit queue: #{@_routing_key} <<", message: message
      @_exchange.publish @_routing_key, new Buffer message, 'utf8'

  pop: (callback) ->
    @_when_ready =>
      @_queue.subscribe ack: true, (message, headers, delivery_info) =>
        message = message.data.toString()
        winston.debug "Rabbit queue: #{@_routing_key} >>", message: message
        callback null, [@_routing_key, message]
        @_queue.shift()

  clear: ->
    @_when_ready =>
      winston.debug "Rabbit queue: #{@_routing_key} :: CLEAR"
      @_queue.destroy()

  end: ->
    winston.debug "Rabbit queue: #{@_routing_key} :: DESTROY"
    @_state = 'closed'
    @_connection.destroySoon()

  _queue_name: -> ''

  _when_ready: (callback) ->
    @_hold_callbacks callback, (handle_callbacks) =>
      @_connection = amqp.createConnection url: 'amqp://localhost'
      @_connection.once 'ready', =>
        @_connection.queue @_routing_key, durable: true, autoDelete: false, (@_queue) =>
          @_exchange = @_connection.exchange()
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
