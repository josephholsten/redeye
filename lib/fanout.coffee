config = require './config'

module.exports = switch config.fanout
  when 'redis' then require './fanout/redis'
  when 'amqp' then require './fanout/amqp'
