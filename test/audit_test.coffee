# Tests the audit trail produced by the dispatcher

# Dependencies.
worker = require 'worker'
dispatcher = require 'dispatcher'
debug = require 'debug'
redeye_suite = require './support/redeye_suite'
AuditListener = require './support/audit_listener'

audit = new AuditListener
dispatcher.audit audit

worker 'a', -> @get 'b'; @get 'c'
worker 'b', -> @get 'c'
worker 'c', -> 216

module.exports = redeye_suite ->

  'test result and audit log':

    setup: (db) -> db.publish 'requests', 'a'

    expect: (db, assert, finish) ->
      db.get 'a', (err, str) ->
        order1 = ['?a|b|c', '?b|c', '!c', '!b', '!a'].join ''
        order2 = ['?a|b|c', '!c', '?b|c', '!b', '!a'].join ''
        real_order = audit.messages.join ''
        assert.includes [order1, order2], real_order
        finish()
