config = require './config'

module.exports = switch config.dictionary
  when 'redis' then require './dictionary/redis'
