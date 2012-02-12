config = require './config'

module.exports = switch config.queue
  when 'redis' then require './queue/redis'
  when 'amqp' then require './queue/amqp'
