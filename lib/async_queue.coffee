config = require './config'

module.exports = switch config.async_queue
  when 'redis' then require './async_queue/redis'
  when 'amqp' then require './async_queue/amqp'
