consts = require './consts'
winston = require 'winston'

module.exports = class AuditLog
  constructor: (options) ->
    @_stream = options.stream

  # Write text to the audit stream
  log: (text) ->
    winston.info "Audit", text
    @_stream.write "#{text}\n" if @_stream

  request: (source, keys) ->
    text = [source, keys...].join consts.key_sep
    @log "?#{text}"

  response: (key) ->
    @log "!#{key}"
